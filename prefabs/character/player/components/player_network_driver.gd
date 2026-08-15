class_name PlayerNetworkDriver
extends Node

## Binds the production player components to host-authoritative prediction.
##
## MultiplayerSpawner calls configure() before the prefab enters the tree. The
## body and replicated state remain owned by peer 1; only this machine's local
## PlayerInput polls its devices. Gameplay outcomes stay outside movement
## prediction: held intent rides the command flags, edge actions arrive as
## requests, and peer 1 publishes what everyone else draws.

## Edge actions a client asks peer 1 to perform on its behalf.
enum RequestedAction {
	LAMP,
	GRAB,
	TETHER,
	RESPAWN,
}

const HOST_PEER_ID := 1
const HULL_COLLISION_MASK := 1
const PHYSICS_PRIORITY := -70

## Components that act on shared world objects. Only peer 1 runs them, because a
## client applying its own grip or tension would fight the authoritative copy.
const HOST_ONLY_COMPONENTS: Array[StringName] = [
	&"Grab",
	&"Tether",
	&"NoiseEmitter",
	&"Respawn",
]

## Presentation state peer 1 publishes so every machine draws this player's beam,
## lamp, and suit readouts. Replicated by the sibling PresentationSync.
@export var replicated_mining_firing := false
@export var replicated_lamp_lit := true
## Negative until peer 1 has published once. A client that adopted the zero these
## would otherwise start at would report an empty suit and raise its own alarms.
@export var replicated_suit_charge := -1.0
@export var replicated_oxygen := -1.0

var _controlled_peer_id := HOST_PEER_ID
var _configured := false
var _is_authority := false
var _presentation_only := false
var _last_adopted_lamp_lit := true

var _body: CharacterBody3D
var _input: PlayerInput
var _locomotion: PlayerLocomotion
var _collision: PlayerCollisionResponse
var _prediction: ClientPredictor3D
var _mining_tool: PlayerMiningTool
var _lamp: PlayerLamp
var _power: PlayerPowerClient
var _oxygen: PlayerOxygen
var _grab: PlayerGrab
var _tether: PlayerTether
var _respawn: PlayerRespawn


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
	_is_authority = local_peer_id == HOST_PEER_ID
	# A copy that owns no outcome still draws the beam and the lamp; it just does
	# not spend the power, deal the damage, or make the noise a second time.
	_presentation_only = not _is_authority
	visibility.is_local_player = is_local
	_input.enabled = is_local
	_input.captures_mouse = is_local
	# Edge actions are this machine's to raise only for the player it drives; a
	# client's are forwarded to peer 1 as requests rather than applied locally.
	_input.gameplay_actions_enabled = is_local
	camera.current = is_local
	view.applies_fog = is_local
	_body.collision_mask = HULL_COLLISION_MASK

	_locomotion = _body.get_node("Locomotion") as PlayerLocomotion
	_collision = _body.get_node("CollisionResponse") as PlayerCollisionResponse
	_locomotion.externally_driven = true
	_collision.externally_driven = true
	_configure_gameplay_components(is_local)

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


## Wires every gameplay component to the right intent source for this copy: the
## host owns all outcomes, a client predicts its own player and replays others.
func _configure_gameplay_components(is_local: bool) -> void:
	if not _is_authority:
		for component_name in HOST_ONLY_COMPONENTS:
			var component := _body.get_node_or_null(NodePath(component_name))
			if component != null:
				component.process_mode = Node.PROCESS_MODE_DISABLED

	_mining_tool = _body.get_node_or_null("MiningTool") as PlayerMiningTool
	_lamp = _body.get_node_or_null("Lamp") as PlayerLamp
	_power = _body.get_node_or_null("PowerClient") as PlayerPowerClient
	_oxygen = _body.get_node_or_null("Oxygen") as PlayerOxygen
	_grab = _body.get_node_or_null("Grab") as PlayerGrab
	_tether = _body.get_node_or_null("Tether") as PlayerTether
	_respawn = _body.get_node_or_null("Respawn") as PlayerRespawn

	# Only a copy of somebody else's player has no live PlayerInput to read; this
	# machine's own player keeps polling its device, so the beam answers at once.
	var reads_replicated_intent := not _is_authority and not is_local
	if _mining_tool != null:
		_mining_tool.externally_driven = reads_replicated_intent
		_mining_tool.presentation_only = _presentation_only
	if _lamp != null:
		_lamp.presentation_only = _presentation_only
	if _power != null:
		_power.externally_driven = not _is_authority
	if _oxygen != null:
		_oxygen.externally_driven = not _is_authority

	# These act on shared world objects or on the prediction epoch, so off the
	# authority they must not answer their own key even though the key still fires.
	if _grab != null:
		_grab.externally_driven = not _is_authority
	if _tether != null:
		_tether.externally_driven = not _is_authority
	if _respawn != null:
		_respawn.externally_driven = not _is_authority


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
	# The host's own edge actions are already authoritative where they are raised.
	# A client's reach peer 1 as requests, while the local emit still drives its
	# own lamp immediately and the replicated answer confirms or corrects it.
	if is_locally_controlled() and not _is_authority:
		_input.lamp_toggled.connect(_forward_request.bind(RequestedAction.LAMP))
		_input.grab_toggled.connect(_forward_request.bind(RequestedAction.GRAB))
		_input.tether_toggled.connect(_forward_request.bind(RequestedAction.TETHER))
		_input.reset_requested.connect(_forward_request.bind(RequestedAction.RESPAWN))


func _physics_process(delta: float) -> void:
	var flags := 0
	if _input.stabilize_held:
		flags |= ClientPredictor3D.FLAG_STABILIZING
	if _input.sprint_held:
		flags |= ClientPredictor3D.FLAG_SPRINTING
	if _input.mine_held:
		flags |= ClientPredictor3D.FLAG_MINING
	_prediction.physics_step(delta, _input.thrust, _input.look, _input.roll, flags)
	# physics_step has settled, so prediction and any replay are finished and
	# everything below runs exactly once per tick — never inside the movement
	# callback, which the prediction contract keeps free of one-shot effects.
	if _is_authority:
		_republish_accepted_intent()
		_publish_presentation_state()
	else:
		_adopt_presentation_state()


## Writes the intent peer 1 actually accepted into the same PlayerInput
## properties a device would, so no component learns where a control came from.
func _republish_accepted_intent() -> void:
	if is_locally_controlled():
		return
	# This copy's PlayerInput is disabled and polls nothing, so these survive the
	# tick. The driver runs at -70 and the components that read them at 0.
	_input.thrust = _prediction.get_authoritative_thrust()
	_input.mine_held = bool(_prediction.get_authoritative_flags() & ClientPredictor3D.FLAG_MINING)


func _publish_presentation_state() -> void:
	if _mining_tool != null:
		replicated_mining_firing = _mining_tool.is_firing()
	if _lamp != null:
		replicated_lamp_lit = _lamp.is_switched_on()
	if _power != null:
		replicated_suit_charge = _power.charge
	if _oxygen != null:
		replicated_oxygen = _oxygen.oxygen


## Applies peer 1's answer. The lamp is written only when it changes, so a repeat
## of a stale value cannot stamp on a toggle this machine has predicted locally.
func _adopt_presentation_state() -> void:
	if _mining_tool != null and _mining_tool.externally_driven:
		_mining_tool.set_external_fire(replicated_mining_firing)
	if _lamp != null and replicated_lamp_lit != _last_adopted_lamp_lit:
		_last_adopted_lamp_lit = replicated_lamp_lit
		_lamp.set_lit(replicated_lamp_lit)
	if _power != null and replicated_suit_charge >= 0.0:
		_power.set_charge(replicated_suit_charge)
	if _oxygen != null and replicated_oxygen >= 0.0:
		_oxygen.set_oxygen(replicated_oxygen)


func _forward_request(action: RequestedAction) -> void:
	_request_action.rpc_id(HOST_PEER_ID, int(action))


## Peer 1 performs an edge action on behalf of the client that controls this
## player. Sender validation mirrors the predictor's input command.
@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != _controlled_peer_id or sender_id == HOST_PEER_ID:
		return
	if action < 0 or action >= RequestedAction.size():
		return
	_perform_action(action)


func _perform_action(action: int) -> void:
	match action:
		RequestedAction.LAMP:
			if _lamp != null:
				_lamp.toggle()
		RequestedAction.GRAB:
			if _grab != null:
				_grab.toggle_hold()
		RequestedAction.TETHER:
			if _tether != null:
				_tether.toggle_clip()
		RequestedAction.RESPAWN:
			if _respawn != null:
				_respawn.respawn()
				_prediction.authoritative_reset(true)


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
