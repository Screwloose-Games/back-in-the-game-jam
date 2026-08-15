class_name PlayerNetworkGameplay
extends Node

## Owns the game-specific half of an online player.
##
## Movement prediction deliberately knows nothing about lamp switches, mining,
## resources, or reset requests. This sibling accepts those inputs separately,
## advances them only on the host, and applies primitive replicated state as
## presentation on clients.

enum Action {
	LAMP_SET,
	RESET,
}

const HOST_PEER_ID := 1
const MINING_INTENT_HOLD_USEC := 250_000
const MINING_INTENT_SEND_USEC := 100_000
const DISABLED_ONLINE_COMPONENTS: Array[StringName] = [
	&"Grab",
	&"Tether",
]
const AUTHORITY_COMPONENTS: Array[StringName] = [
	&"PowerClient",
	&"Oxygen",
	&"Lamp",
	&"MiningTool",
	&"NoiseEmitter",
	&"Respawn",
]

## Host-owned personal gameplay state. GameplaySync publishes these primitive
## values as one late-join-safe snapshot; replicas only use them for presentation.
@export var gameplay_lamp_requested := true
@export var gameplay_mining_active := false
@export var gameplay_mining_endpoint := Vector3.ZERO
@export var gameplay_power_fraction := 1.0
@export var gameplay_oxygen_fraction := 1.0
@export var gameplay_action_ack := 0
@export var gameplay_state_sequence := 0

var _controlled_peer_id := HOST_PEER_ID
var _is_authority_instance := true
var _is_local_controller := true
var _configured := false
var _next_action_sequence := 0
var _last_received_action_sequence := 0
var _pending_lamp_action_sequence := 0
var _local_lamp_requested := true
var _next_mining_sequence := 0
var _last_sent_mining_held := false
var _last_mining_send_usec := 0
var _last_received_mining_sequence := 0
var _last_mining_intent_usec := 0
var _remote_mining_held := false

var _body: CharacterBody3D
var _input: PlayerInput
var _prediction: ClientPredictor3D
var _grab: PlayerGrab
var _tether: PlayerTether
var _power: PlayerPowerClient
var _oxygen: PlayerOxygen
var _lamp: PlayerLamp
var _mining_tool: PlayerMiningTool
var _noise: PlayerNoiseEmitter
var _respawn: PlayerRespawn
var _gameplay_sync: MultiplayerSynchronizer


## PlayerNetworkDriver calls this before MultiplayerSpawner inserts the prefab.
func configure(controlled_peer_id: int, local_peer_id: int) -> void:
	_controlled_peer_id = controlled_peer_id
	_is_authority_instance = local_peer_id == HOST_PEER_ID
	_is_local_controller = local_peer_id == controlled_peer_id
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("PlayerNetworkGameplay must be a child of the player CharacterBody3D.")
		return

	_input = _body.get_node("Input") as PlayerInput
	_prediction = _body.get_node("Prediction") as ClientPredictor3D
	_grab = _body.get_node("Grab") as PlayerGrab
	_tether = _body.get_node("Tether") as PlayerTether
	_power = _body.get_node("PowerClient") as PlayerPowerClient
	_oxygen = _body.get_node("Oxygen") as PlayerOxygen
	_lamp = _body.get_node("Lamp") as PlayerLamp
	_mining_tool = _body.get_node("MiningTool") as PlayerMiningTool
	_noise = _body.get_node("NoiseEmitter") as PlayerNoiseEmitter
	_respawn = _body.get_node("Respawn") as PlayerRespawn

	_input.gameplay_actions_enabled = _is_local_controller
	_grab.externally_driven = true
	_tether.externally_driven = true
	# Grab and tether stay inert online until shared objects have stable network
	# identities. Do not route their input signals or imply wire-level support.
	_power.externally_driven = true
	_oxygen.externally_driven = true
	_lamp.externally_driven = true
	_mining_tool.externally_driven = true
	_noise.externally_driven = true
	_respawn.externally_driven = true
	for component_name in DISABLED_ONLINE_COMPONENTS:
		var component := _body.get_node_or_null(NodePath(component_name))
		if component != null:
			component.process_mode = Node.PROCESS_MODE_DISABLED
	for component_name in AUTHORITY_COMPONENTS:
		var component := _body.get_node_or_null(NodePath(component_name))
		if component != null:
			component.process_mode = (
				Node.PROCESS_MODE_INHERIT if _is_authority_instance else Node.PROCESS_MODE_DISABLED
			)
	_configured = true


func _ready() -> void:
	if not _configured:
		push_error("PlayerNetworkGameplay.configure() must run before the player enters the tree.")
		return
	_gameplay_sync = get_node("../GameplaySync") as MultiplayerSynchronizer
	if _gameplay_sync == null:
		push_error("PlayerNetworkGameplay requires a sibling GameplaySync node.")
		return
	if _is_local_controller:
		_input.lamp_toggled.connect(_on_lamp_toggled)
		_input.reset_requested.connect(_on_reset_requested)
	_local_lamp_requested = (
		_lamp.requested_lit() if _is_authority_instance else gameplay_lamp_requested
	)
	if _is_authority_instance:
		call_deferred("_publish_gameplay_state")
	else:
		_gameplay_sync.synchronized.connect(_on_gameplay_state_synchronized)
		call_deferred("_apply_gameplay_presentation")


## Called once per movement-driver tick after accepted thrust has been simulated.
func physics_step(delta: float, authoritative_thrust_fraction: float) -> void:
	if not _configured:
		return
	if _is_authority_instance:
		_step_authoritative_gameplay(delta, authoritative_thrust_fraction)
	elif _is_local_controller:
		_step_local_gameplay()


## Kept as a small seam so no-network tests can exercise local presentation
## without running the predictor or constructing a fake remote peer.
func _step_local_gameplay() -> void:
	_mining_tool.preview_step(_input.mine_held)
	_send_mining_intent()


func _step_authoritative_gameplay(delta: float, thrust_fraction: float) -> void:
	# Match the solo player's physics phase followed by process/node order so a
	# nearly empty battery gives each system the same priority online and off.
	_mining_tool.authority_step(delta, _authoritative_mining_held())
	_noise.authority_step(delta, thrust_fraction, _mining_tool.is_firing())
	_power.authority_step(delta)
	_oxygen.authority_step(delta, thrust_fraction)
	_lamp.authority_step(delta)
	_publish_gameplay_state()


func _authoritative_mining_held() -> bool:
	if _controlled_peer_id == HOST_PEER_ID:
		return _input.mine_held
	if _last_mining_intent_usec == 0:
		return false
	if Time.get_ticks_usec() - _last_mining_intent_usec > MINING_INTENT_HOLD_USEC:
		_remote_mining_held = false
	return _remote_mining_held


func _publish_gameplay_state() -> void:
	if not _is_authority_instance or not is_instance_valid(_lamp):
		return
	gameplay_lamp_requested = _lamp.requested_lit()
	gameplay_mining_active = _mining_tool.is_firing()
	gameplay_mining_endpoint = _mining_tool.beam_endpoint()
	gameplay_power_fraction = _power.fraction()
	gameplay_oxygen_fraction = _oxygen.fraction()
	gameplay_state_sequence += 1


func _apply_gameplay_presentation() -> void:
	if _is_authority_instance or not is_instance_valid(_lamp):
		return
	_power.apply_network_fraction(gameplay_power_fraction)
	_oxygen.apply_network_fraction(gameplay_oxygen_fraction)
	var applied_lamp_requested := gameplay_lamp_requested
	var lamp_request_pending := gameplay_action_ack < _pending_lamp_action_sequence
	if _is_local_controller and lamp_request_pending:
		applied_lamp_requested = _local_lamp_requested
	else:
		_local_lamp_requested = gameplay_lamp_requested
		_pending_lamp_action_sequence = 0
	(
		_lamp
		. apply_network_presentation(
			applied_lamp_requested,
			applied_lamp_requested and gameplay_power_fraction > 0.0,
			gameplay_power_fraction,
		)
	)
	if not _is_local_controller:
		(
			_mining_tool
			. apply_network_presentation(
				gameplay_mining_active,
				gameplay_mining_endpoint,
			)
		)


func _on_gameplay_state_synchronized() -> void:
	_apply_gameplay_presentation()


func _on_lamp_toggled() -> void:
	_local_lamp_requested = not _local_lamp_requested
	_pending_lamp_action_sequence = _request_action(Action.LAMP_SET, _local_lamp_requested)
	if not _is_authority_instance:
		(
			_lamp
			. apply_network_presentation(
				_local_lamp_requested,
				_local_lamp_requested and gameplay_power_fraction > 0.0,
				gameplay_power_fraction,
			)
		)


func _on_reset_requested() -> void:
	_request_action(Action.RESET, false)


func _request_action(action: Action, value: bool) -> int:
	_next_action_sequence += 1
	var sequence := _next_action_sequence
	if _is_authority_instance:
		_apply_action_request(sequence, action, value)
	else:
		var peer := multiplayer.multiplayer_peer
		if (
			peer != null
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			and multiplayer.get_unique_id() != HOST_PEER_ID
		):
			(
				_receive_action_request
				. rpc_id(
					HOST_PEER_ID,
					sequence,
					action,
					value,
				)
			)
	return sequence


@rpc("any_peer", "call_remote", "reliable", 0)
func _receive_action_request(sequence: int, action: int, value: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accepts_action_request(sender_id, sequence, action):
		return
	_last_received_action_sequence = sequence
	_apply_action_request(sequence, action as Action, value)


func _accepts_action_request(sender_id: int, sequence: int, action: int) -> bool:
	return (
		sender_id == _controlled_peer_id
		and sender_id != HOST_PEER_ID
		and sequence > _last_received_action_sequence
		and action >= Action.LAMP_SET
		and action <= Action.RESET
	)


func _apply_action_request(sequence: int, action: Action, value: bool) -> void:
	match action:
		Action.LAMP_SET:
			_lamp.set_lit(value)
		Action.RESET:
			_respawn.respawn()
			_clear_remote_mining_intent()
			_mining_tool.authority_step(0.0, false)
			_prediction.authoritative_reset(true)
	gameplay_action_ack = sequence
	_publish_gameplay_state()


func _send_mining_intent() -> void:
	var peer := multiplayer.multiplayer_peer
	if (
		peer == null
		or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED
		or multiplayer.get_unique_id() == HOST_PEER_ID
	):
		return
	var now_usec := Time.get_ticks_usec()
	if (
		_input.mine_held == _last_sent_mining_held
		and now_usec - _last_mining_send_usec < MINING_INTENT_SEND_USEC
	):
		return
	_next_mining_sequence += 1
	(
		_receive_mining_intent
		. rpc_id(
			HOST_PEER_ID,
			_prediction.authoritative_epoch,
			_next_mining_sequence,
			_input.mine_held,
		)
	)
	_last_sent_mining_held = _input.mine_held
	_last_mining_send_usec = now_usec


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _receive_mining_intent(epoch: int, sequence: int, held: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accepts_mining_intent(sender_id, epoch, sequence):
		return
	_last_received_mining_sequence = sequence
	_last_mining_intent_usec = Time.get_ticks_usec()
	_remote_mining_held = held


func _accepts_mining_intent(sender_id: int, epoch: int, sequence: int) -> bool:
	return (
		sender_id == _controlled_peer_id
		and sender_id != HOST_PEER_ID
		and epoch == _prediction.authoritative_epoch
		and sequence > _last_received_mining_sequence
	)


func _clear_remote_mining_intent() -> void:
	_remote_mining_held = false
	_last_mining_intent_usec = 0
