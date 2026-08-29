class_name PlayerNetworkDriver
extends Node

## Binds production movement components to host-authoritative prediction.
##
## MultiplayerSpawner calls configure() before the prefab enters the tree. The
## body and replicated state remain owned by peer 1; only this machine's local
## PlayerInput polls its devices. Game-specific requests and resource state live
## in the sibling PlayerNetworkGameplay so movement replay cannot repeat them.

const HOST_PEER_ID := 1
const AUTHORITY_COLLISION_LAYER := 2
const REPLICA_COLLISION_LAYER := 0
## Layers 1 and 6, `hull` and `ore`. Ore is here because mineral chunks moved off layer 1 --
## a suit that flew through every deposit in multiplayer would be the regression.
##
## NOTE THIS IS NARROWER THAN THE 573 prefab_player.tscn AUTHORS, and it overwrites it. A
## networked suit therefore does not collide with debris, carryables, creatures or hazards.
## That is pre-existing and is not this change's to fix, but it is why the two numbers do
## not match and neither is a typo.
const HULL_COLLISION_MASK := 33
const REPLICA_COLLISION_MASK := 0
const PHYSICS_PRIORITY := -70

var _controlled_peer_id := HOST_PEER_ID
var _is_authority_instance := true
var _is_local_controller := true
var _configured := false
var _authoritative_thrust_fraction := 0.0
## The accepted command's full control set, for the eight positioned thrusters.
## The fraction above cannot say which of them is firing.
var _authoritative_thrust := Vector3.ZERO
var _authoritative_roll := 0.0

var _body: CharacterBody3D
var _input: PlayerInput
var _locomotion: PlayerLocomotion
var _collision: PlayerCollisionResponse
var _prediction: ClientPredictor3D
var _gameplay: PlayerNetworkGameplay


## Must run before MultiplayerSpawner inserts the prefab into SceneTree.
func configure(controlled_peer_id: int, local_peer_id: int) -> void:
	_controlled_peer_id = controlled_peer_id
	_is_authority_instance = local_peer_id == HOST_PEER_ID
	_is_local_controller = local_peer_id == controlled_peer_id
	_body = get_parent() as CharacterBody3D
	var player_root := _body.get_parent() if _body != null else null
	if _body == null or player_root == null:
		push_error("PlayerNetworkDriver must be a child of the player CharacterBody3D.")
		return

	player_root.set_multiplayer_authority(HOST_PEER_ID, true)
	_input = _body.get_node("Input") as PlayerInput
	_input.set_multiplayer_authority(_controlled_peer_id, true)

	var visibility := _body.get_node("Visibility") as PlayerVisibility
	var camera := _body.get_node("Head/HeadCamera") as Camera3D
	var view := _body.get_node("View") as PlayerView
	visibility.is_local_player = _is_local_controller
	_input.enabled = _is_local_controller
	_input.captures_mouse = _is_local_controller
	camera.current = _is_local_controller
	view.applies_fog = _is_local_controller
	_body.collision_layer = (
		AUTHORITY_COLLISION_LAYER if _is_authority_instance else REPLICA_COLLISION_LAYER
	)
	if _is_authority_instance:
		_body.collision_mask = HULL_COLLISION_MASK
	elif _is_local_controller:
		_body.collision_mask = HULL_COLLISION_MASK
	else:
		_body.collision_mask = REPLICA_COLLISION_MASK

	_locomotion = _body.get_node("Locomotion") as PlayerLocomotion
	_collision = _body.get_node("CollisionResponse") as PlayerCollisionResponse
	_locomotion.externally_driven = true
	_collision.externally_driven = true

	_prediction = _body.get_node("Prediction") as ClientPredictor3D
	var presentation := _body.get_node("Head") as Node3D
	(
		_prediction
		. configure(
			_controlled_peer_id,
			presentation,
			Callable(self, "_simulate_network_command"),
			true,
			Callable(self, "_capture_prediction_state"),
			Callable(self, "_restore_prediction_state"),
			Callable(self, "_prediction_states_match"),
		)
	)

	_gameplay = _body.get_node("NetworkGameplay") as PlayerNetworkGameplay
	if _gameplay == null:
		push_error("PlayerNetworkDriver requires a sibling NetworkGameplay node.")
		return
	_gameplay.configure(_controlled_peer_id, local_peer_id)

	# Optional on purpose: a player prefab without voice must still be playable,
	# so this degrades to a silent game rather than a broken one.
	var voice := _body.get_node_or_null("ProximityVoiceChat") as PlayerProximityVoiceChat
	if voice != null:
		voice.configure(_controlled_peer_id, local_peer_id)
	_configured = true


func controlled_peer_id() -> int:
	return _controlled_peer_id


func is_locally_controlled() -> bool:
	return _is_local_controller


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if not _configured:
		push_error("PlayerNetworkDriver.configure() must run before the player enters the tree.")
		set_physics_process(false)
		return
	_prediction.authoritative_reset_received.connect(_on_authoritative_reset_received)


func _physics_process(delta: float) -> void:
	var flags := 0
	if _input.stabilize_held:
		flags |= ClientPredictor3D.FLAG_STABILIZING
	if _input.sprint_held:
		flags |= ClientPredictor3D.FLAG_SPRINTING
	if _is_authority_instance:
		# If prediction is inactive or has no accepted command this tick, held
		# thrust must not leak into resource drain or noise from the previous tick.
		_authoritative_thrust_fraction = 0.0
		_authoritative_thrust = Vector3.ZERO
		_authoritative_roll = 0.0
	_prediction.physics_step(delta, _input.thrust, _input.look, _input.roll, flags)
	(
		_gameplay
		. physics_step(
			delta,
			_authoritative_thrust_fraction,
			_authoritative_thrust,
			_authoritative_roll,
		)
	)


func _simulate_network_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
	fixed_delta: float,
	context: int,
) -> void:
	var stabilizing := bool(flags & ClientPredictor3D.FLAG_STABILIZING)
	var sprinting := bool(flags & ClientPredictor3D.FLAG_SPRINTING)
	var is_authority := context == ClientPredictor3D.SimulationContext.AUTHORITY
	if is_authority:
		_authoritative_thrust_fraction = minf(thrust.length(), 1.0)
		_authoritative_thrust = thrust
		_authoritative_roll = roll
	# Dynamic props are not replicated yet, so even authority only resolves the
	# static hull. Effects fire once per fresh command and are suppressed on
	# replay, which is what lets a client hear its own impacts without a
	# reconciliation pass sounding them all again.
	var emit_effects := context != ClientPredictor3D.SimulationContext.REPLAY
	(
		_locomotion
		. step(
			fixed_delta,
			thrust,
			look_delta,
			roll,
			stabilizing,
			sprinting,
			false,
		)
	)
	_collision.step(fixed_delta, false, emit_effects)


func _capture_prediction_state() -> Dictionary:
	return {
		"locomotion": _locomotion.capture_prediction_state(),
		"collision": _collision.capture_prediction_state(),
	}


func _restore_prediction_state(state: Dictionary) -> void:
	var raw_locomotion: Variant = state.get("locomotion", {})
	if typeof(raw_locomotion) == TYPE_DICTIONARY:
		_locomotion.restore_prediction_state(raw_locomotion)
	var raw_collision: Variant = state.get("collision", {})
	if typeof(raw_collision) == TYPE_DICTIONARY:
		_collision.restore_prediction_state(raw_collision)


func _prediction_states_match(predicted: Dictionary, authoritative: Dictionary) -> bool:
	var predicted_locomotion: Variant = predicted.get("locomotion", {})
	var authoritative_locomotion: Variant = authoritative.get("locomotion", {})
	if (
		typeof(predicted_locomotion) != TYPE_DICTIONARY
		or typeof(authoritative_locomotion) != TYPE_DICTIONARY
		or not _locomotion.prediction_states_match(predicted_locomotion, authoritative_locomotion)
	):
		return false

	var predicted_collision: Variant = predicted.get("collision", {})
	var authoritative_collision: Variant = authoritative.get("collision", {})
	return (
		typeof(predicted_collision) == TYPE_DICTIONARY
		and typeof(authoritative_collision) == TYPE_DICTIONARY
		and _collision.prediction_states_match(predicted_collision, authoritative_collision)
	)


func _on_authoritative_reset_received(_body_transform: Transform3D) -> void:
	_authoritative_thrust_fraction = 0.0
	_authoritative_thrust = Vector3.ZERO
	_authoritative_roll = 0.0
	_input.clear()
