class_name PlayerNetworkDriver
extends Node

## Binds the production player components to host-authoritative prediction.
##
## MultiplayerSpawner calls configure() before the prefab enters the tree. The
## body and replicated state remain owned by peer 1; only this machine's local
## PlayerInput polls its devices. Shared gameplay effects are deliberately not
## part of movement prediction.

const HOST_PEER_ID := 1
const HULL_COLLISION_MASK := 1
const PHYSICS_PRIORITY := -70
const DISABLED_ONLINE_COMPONENTS: Array[StringName] = [
	&"Grab",
	&"Tether",
	&"Hands",
	&"PowerClient",
	&"Oxygen",
	&"Lamp",
	&"MiningTool",
	&"NoiseEmitter",
	&"Respawn",
]

var _controlled_peer_id := HOST_PEER_ID
var _configured := false

var _body: CharacterBody3D
var _input: PlayerInput
var _locomotion: PlayerLocomotion
var _collision: PlayerCollisionResponse
var _prediction: ClientPredictor3D


## Must run before MultiplayerSpawner inserts the prefab into SceneTree.
func configure(controlled_peer_id: int, local_peer_id: int) -> void:
	_controlled_peer_id = controlled_peer_id
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
	var is_local := local_peer_id == _controlled_peer_id
	visibility.is_local_player = is_local
	_input.enabled = is_local
	_input.captures_mouse = is_local
	# Edge actions need individual request/validation protocols. Movement remains
	# available while this first online slice keeps those effects host-owned.
	_input.gameplay_actions_enabled = false
	camera.current = is_local
	view.applies_fog = is_local
	_body.collision_mask = HULL_COLLISION_MASK

	_locomotion = _body.get_node("Locomotion") as PlayerLocomotion
	_collision = _body.get_node("CollisionResponse") as PlayerCollisionResponse
	_locomotion.externally_driven = true
	_collision.externally_driven = true
	for component_name in DISABLED_ONLINE_COMPONENTS:
		var component := _body.get_node_or_null(NodePath(component_name))
		if component != null:
			component.process_mode = Node.PROCESS_MODE_DISABLED

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
	_configured = true


func controlled_peer_id() -> int:
	return _controlled_peer_id


func is_locally_controlled() -> bool:
	return multiplayer.get_unique_id() == _controlled_peer_id


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
	_prediction.physics_step(delta, _input.thrust, _input.look, _input.roll, flags)


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
	# Shared rigid bodies and gameplay events are outside this movement protocol.
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
	(
		_collision
		. step(
			fixed_delta,
			false,
			context == ClientPredictor3D.SimulationContext.AUTHORITY,
		)
	)


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
	_input.clear()
