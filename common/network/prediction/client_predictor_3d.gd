class_name ClientPredictor3D
extends Node

## Reusable host-authoritative prediction for a CharacterBody3D.
##
## The controlling client sends bounded, sequenced movement commands and
## simulates them immediately. Peer 1 uses the newest accepted intent on each
## simulation tick and publishes atomic snapshots through a sibling
## MultiplayerSynchronizer.
## Clients replay unacknowledged commands after each snapshot. A Presentation
## child hides ordinary corrections while remote characters interpolate behind
## a short snapshot buffer.

signal authoritative_reset_received(body_transform: Transform3D)

enum SimulationContext {
	AUTHORITY,
	PREDICTION,
	REPLAY,
}

const HOST_PEER_ID := 1
const FLAG_STABILIZING := 1 << 0
const FLAG_SPRINTING := 1 << 1
const FLAG_MINING := 1 << 2
const ALLOWED_FLAGS := FLAG_STABILIZING | FLAG_SPRINTING | FLAG_MINING
const MAX_LOOK_DELTA := 2048.0
const MAX_REPLAY_COMMANDS := 32
const INPUT_HOLD_USEC := 250_000
const HARD_SNAP_DISTANCE := 2.0
const MATCH_POSITION_EPSILON := 0.05
const MATCH_VELOCITY_EPSILON := 0.1
const MATCH_ROTATION_EPSILON := 0.02
const REMOTE_BUFFER_USEC := 100_000
const REMOTE_EXTRAPOLATION_SECONDS := 0.1
const PRESENTATION_DECAY_RATE := 14.0

@export var authoritative_transform := Transform3D.IDENTITY
@export var authoritative_velocity := Vector3.ZERO
@export var authoritative_auxiliary_state: Dictionary = {}
@export var authoritative_epoch := 1
@export var acknowledged_input_sequence := 0
@export var simulation_active := true
@export var snapshot_sequence := 0

var _body: CharacterBody3D
var _presentation: Node3D
var _controlled_peer_id := HOST_PEER_ID
var _simulate_command := Callable()
var _capture_auxiliary_state := Callable()
var _restore_auxiliary_state := Callable()
var _auxiliary_states_match := Callable()
var _history := ClientPredictionHistory3D.new()
var _pending_remote_command: Dictionary = {}
var _last_remote_command: Dictionary = {}
var _remote_snapshots: Array = []
var _last_received_input_sequence := 0
var _last_remote_input_usec := 0
var _last_reconciled_input_sequence := 0
var _last_consumed_snapshot_sequence := -1
var _latest_authoritative_flags := 0
var _latest_authoritative_thrust := Vector3.ZERO
var _last_local_authoritative_transform := Transform3D.IDENTITY
var _last_local_authoritative_velocity := Vector3.ZERO
var _last_local_authoritative_auxiliary_state: Dictionary = {}
var _has_local_authoritative_snapshot := false
var _snapshot_pending := false
var _configured := false


func configure(
	controlled_peer_id: int,
	presentation: Node3D,
	simulate_command: Callable,
	initially_active := true,
	capture_auxiliary_state := Callable(),
	restore_auxiliary_state := Callable(),
	auxiliary_states_match := Callable(),
) -> void:
	if capture_auxiliary_state.is_valid() != restore_auxiliary_state.is_valid():
		push_error("ClientPredictor3D auxiliary state requires both capture and restore callbacks.")
		return
	if auxiliary_states_match.is_valid() and not capture_auxiliary_state.is_valid():
		push_error(
			"ClientPredictor3D cannot compare auxiliary state without capture and restore callbacks."
		)
		return
	_controlled_peer_id = controlled_peer_id
	_presentation = presentation
	_simulate_command = simulate_command
	_capture_auxiliary_state = capture_auxiliary_state
	_restore_auxiliary_state = restore_auxiliary_state
	_auxiliary_states_match = auxiliary_states_match
	simulation_active = initially_active
	_history.reset(authoritative_epoch)
	_configured = true


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null or not _configured or not _simulate_command.is_valid():
		push_error("ClientPredictor3D must be configured by a CharacterBody3D before _ready().")
		set_physics_process(false)
		return

	var state_sync := get_node_or_null("../StateSync") as MultiplayerSynchronizer
	if state_sync == null:
		push_error("ClientPredictor3D requires a sibling StateSync node.")
		set_physics_process(false)
		return
	state_sync.synchronized.connect(_on_state_synchronized)

	if multiplayer.is_server():
		_publish_authoritative_state()
	else:
		_snapshot_pending = true


func physics_step(
	delta: float,
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> void:
	if _body == null:
		return

	if multiplayer.is_server():
		_server_step(thrust, look_delta, roll, flags)
	else:
		_client_step(delta, thrust, look_delta, roll, flags)


func authoritative_reset(active: bool) -> void:
	if not multiplayer.is_server() or _body == null:
		return
	authoritative_epoch += 1
	acknowledged_input_sequence = 0
	simulation_active = active
	_pending_remote_command.clear()
	_last_remote_command.clear()
	_last_received_input_sequence = 0
	_last_remote_input_usec = 0
	_latest_authoritative_flags = 0
	_latest_authoritative_thrust = Vector3.ZERO
	_publish_authoritative_state()
	_body.reset_physics_interpolation()


func set_authoritative_active(active: bool) -> void:
	if not multiplayer.is_server() or simulation_active == active:
		return
	authoritative_reset(active)


func get_authoritative_flags() -> int:
	return _latest_authoritative_flags


## The thrust peer 1 last simulated. An adapter republishes this so components
## that price themselves off thrust see a remote player's, not a disabled stub's.
func get_authoritative_thrust() -> Vector3:
	return _latest_authoritative_thrust


func get_unacknowledged_input_count() -> int:
	return _history.pending_count()


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _receive_input_command(
	epoch: int,
	sequence: int,
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != _controlled_peer_id or sender_id == HOST_PEER_ID:
		return
	if epoch != authoritative_epoch:
		return
	if sequence <= _last_received_input_sequence:
		return
	if not thrust.is_finite() or not look_delta.is_finite() or not is_finite(roll):
		return

	_last_received_input_sequence = sequence
	_store_remote_command(epoch, sequence, thrust, look_delta, roll, flags)


func _store_remote_command(
	epoch: int,
	sequence: int,
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> void:
	_last_remote_input_usec = Time.get_ticks_usec()
	# Thrust, roll, and flags describe held intent, so keep only their newest
	# values. Mouse look is a per-frame delta, though: accumulate every accepted
	# delta that arrived before this host tick so motion is neither dropped nor
	# repeated like a held input.
	var accumulated_look_delta := look_delta
	if not _pending_remote_command.is_empty():
		accumulated_look_delta += _pending_remote_command["look_delta"]
	_pending_remote_command = {
		"epoch": epoch,
		"sequence": sequence,
		"thrust": thrust.limit_length(1.0),
		"look_delta": accumulated_look_delta.limit_length(MAX_LOOK_DELTA),
		"roll": clampf(roll, -1.0, 1.0),
		"flags": flags & ALLOWED_FLAGS,
	}


func _server_step(thrust: Vector3, look_delta: Vector2, roll: float, flags: int) -> void:
	if simulation_active:
		if _controlled_peer_id == multiplayer.get_unique_id():
			var command := _sanitize_local_command(thrust, look_delta, roll, flags)
			_latest_authoritative_flags = int(command["flags"])
			_latest_authoritative_thrust = command["thrust"]
			_simulate(command, SimulationContext.AUTHORITY)
		else:
			_simulate_latest_remote_command()
	else:
		_pending_remote_command.clear()
		_last_remote_command.clear()
		_latest_authoritative_flags = 0
		_latest_authoritative_thrust = Vector3.ZERO

	_publish_authoritative_state()


func _client_step(
	delta: float,
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> void:
	if _snapshot_pending and _consume_authoritative_snapshot():
		# The caller sampled controls before this component consumed the snapshot.
		# Wait one tick so a reset orientation cannot produce one stale command.
		return

	if _controlled_peer_id == multiplayer.get_unique_id():
		if simulation_active:
			_predict_local_command(thrust, look_delta, roll, flags)
		_decay_presentation(delta)
	else:
		_interpolate_remote_body()


func _predict_local_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> void:
	var sanitized := _sanitize_local_command(thrust, look_delta, roll, flags)
	var command := (
		_history
		. create_command(
			sanitized["thrust"],
			sanitized["look_delta"],
			float(sanitized["roll"]),
			int(sanitized["flags"]),
		)
	)
	_simulate(command, SimulationContext.PREDICTION)
	(
		_history
		. record_state(
			int(command["sequence"]),
			_body.global_transform,
			_body.velocity,
			_capture_current_auxiliary_state(),
		)
	)

	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		(
			_receive_input_command
			. rpc_id(
				HOST_PEER_ID,
				int(command["epoch"]),
				int(command["sequence"]),
				command["thrust"],
				command["look_delta"],
				float(command["roll"]),
				int(command["flags"]),
			)
		)


func _on_state_synchronized() -> void:
	# SceneTree delivers replication during its process phase. Reconciliation
	# waits for the next physics tick before it invokes movement code.
	_snapshot_pending = true


func _consume_authoritative_snapshot() -> bool:
	_snapshot_pending = false
	if snapshot_sequence <= _last_consumed_snapshot_sequence:
		return false
	_last_consumed_snapshot_sequence = snapshot_sequence

	if _controlled_peer_id != multiplayer.get_unique_id():
		_queue_remote_snapshot()
		return false
	if not _has_local_authoritative_snapshot:
		_remember_local_authority_snapshot()
		_reset_local_for_new_epoch()
		return true
	var same_ack_state_changed := _local_authority_snapshot_changed()
	_remember_local_authority_snapshot()
	return _reconcile_local_snapshot(same_ack_state_changed)


func _reconcile_local_snapshot(same_ack_state_changed: bool) -> bool:
	if authoritative_epoch != _history.epoch():
		_reset_local_for_new_epoch()
		return true
	if acknowledged_input_sequence <= _last_reconciled_input_sequence:
		return _handle_nonadvancing_acknowledgement(same_ack_state_changed)
	return _reconcile_advancing_acknowledgement()


func _handle_nonadvancing_acknowledgement(authority_changed: bool) -> bool:
	if acknowledged_input_sequence < _last_reconciled_input_sequence or not authority_changed:
		return false
	# The host can continue simulating held intent while no newer packet is
	# accepted. Its snapshot is current, so replaying the pending tail here would
	# apply elapsed time twice. Rebase and resume with fresh input.
	_hard_resync_same_epoch()
	return true


func _reconcile_advancing_acknowledgement() -> bool:
	var predicted_state := _history.state_for(acknowledged_input_sequence)
	if predicted_state.is_empty():
		_hard_resync_same_epoch()
		return true
	if _prediction_matches_authority(predicted_state):
		_history.acknowledge(acknowledged_input_sequence)
		_last_reconciled_input_sequence = acknowledged_input_sequence
		return false

	var old_visual_transform := _presentation.global_transform
	var old_body_transform := _body.global_transform
	var remaining_commands := _history.acknowledge(acknowledged_input_sequence)
	if remaining_commands.size() > MAX_REPLAY_COMMANDS:
		_hard_resync_same_epoch()
		return true
	_body.global_transform = authoritative_transform
	_body.velocity = authoritative_velocity
	_restore_current_auxiliary_state(authoritative_auxiliary_state)
	for raw_command in remaining_commands:
		var command: Dictionary = raw_command
		_simulate(command, SimulationContext.REPLAY)
		(
			_history
			. record_state(
				int(command["sequence"]),
				_body.global_transform,
				_body.velocity,
				_capture_current_auxiliary_state(),
			)
		)

	_last_reconciled_input_sequence = acknowledged_input_sequence
	var correction_distance := old_body_transform.origin.distance_to(_body.global_position)
	if correction_distance > HARD_SNAP_DISTANCE:
		_presentation.transform = Transform3D.IDENTITY
		_body.reset_physics_interpolation()
	else:
		# The collision body is authoritative immediately. Preserve the old world
		# pose only for camera/mesh presentation and decay that offset smoothly.
		_presentation.global_transform = old_visual_transform
	return false


func _simulate_latest_remote_command() -> void:
	if not _pending_remote_command.is_empty():
		_last_remote_command = _pending_remote_command
		_pending_remote_command = {}
		acknowledged_input_sequence = int(_last_remote_command["sequence"])

	if _last_remote_command.is_empty():
		return
	var command := _last_remote_command.duplicate()
	if Time.get_ticks_usec() - _last_remote_input_usec > INPUT_HOLD_USEC:
		# Preserve zero-g inertia, but never leave thrust or turning held
		# indefinitely when input traffic stalls.
		command["thrust"] = Vector3.ZERO
		command["look_delta"] = Vector2.ZERO
		command["roll"] = 0.0
		command["flags"] = 0
	_latest_authoritative_flags = int(command["flags"])
	_latest_authoritative_thrust = command["thrust"]
	_simulate(command, SimulationContext.AUTHORITY)
	# Mouse motion is an impulse sampled since the previous packet. The held
	# command may run again on the next host tick, but its look delta must not.
	_last_remote_command["look_delta"] = Vector2.ZERO


func _reset_local_for_new_epoch() -> void:
	_history.reset(authoritative_epoch, acknowledged_input_sequence)
	_last_reconciled_input_sequence = acknowledged_input_sequence
	_apply_hard_authoritative_state()
	# A new epoch represents a teleport, respawn, or activation boundary. The
	# input adapter must reset its desired facing to the new authoritative basis.
	authoritative_reset_received.emit(authoritative_transform)


func _hard_resync_same_epoch() -> void:
	# Missing history is unusual (typically a long stall or capacity overflow).
	# Keep command numbering monotonic so the host never rejects newly generated
	# commands as duplicates of packets it already saw.
	_history.clear_pending_keep_sequence(acknowledged_input_sequence)
	_last_reconciled_input_sequence = acknowledged_input_sequence
	_apply_hard_authoritative_state()
	authoritative_reset_received.emit(authoritative_transform)


func _apply_hard_authoritative_state() -> void:
	_body.global_transform = authoritative_transform
	_body.velocity = authoritative_velocity
	_restore_current_auxiliary_state(authoritative_auxiliary_state)
	_presentation.transform = Transform3D.IDENTITY
	_body.reset_physics_interpolation()


func _prediction_matches_authority(predicted_state: Dictionary) -> bool:
	var predicted_transform: Transform3D = predicted_state["transform"]
	var predicted_velocity: Vector3 = predicted_state["velocity"]
	var position_error := predicted_transform.origin.distance_to(authoritative_transform.origin)
	var velocity_error := predicted_velocity.distance_to(authoritative_velocity)
	var predicted_rotation := predicted_transform.basis.get_rotation_quaternion().normalized()
	var authoritative_rotation := (
		authoritative_transform.basis.get_rotation_quaternion().normalized()
	)
	var rotation_error := predicted_rotation.angle_to(authoritative_rotation)
	var predicted_auxiliary_state: Dictionary = predicted_state.get("auxiliary_state", {})
	return (
		position_error <= MATCH_POSITION_EPSILON
		and velocity_error <= MATCH_VELOCITY_EPSILON
		and rotation_error <= MATCH_ROTATION_EPSILON
		and _do_auxiliary_states_match(
			predicted_auxiliary_state,
			authoritative_auxiliary_state,
		)
	)


func _local_authority_snapshot_changed() -> bool:
	if not _has_local_authoritative_snapshot:
		return false
	var previous_rotation := (
		_last_local_authoritative_transform.basis.get_rotation_quaternion().normalized()
	)
	var current_rotation := authoritative_transform.basis.get_rotation_quaternion().normalized()
	return (
		(
			_last_local_authoritative_transform.origin.distance_to(authoritative_transform.origin)
			> MATCH_POSITION_EPSILON
		)
		or (
			_last_local_authoritative_velocity.distance_to(authoritative_velocity)
			> MATCH_VELOCITY_EPSILON
		)
		or previous_rotation.angle_to(current_rotation) > MATCH_ROTATION_EPSILON
		or not _do_auxiliary_states_match(
			_last_local_authoritative_auxiliary_state,
			authoritative_auxiliary_state,
		)
	)


func _remember_local_authority_snapshot() -> void:
	_last_local_authoritative_transform = authoritative_transform
	_last_local_authoritative_velocity = authoritative_velocity
	_last_local_authoritative_auxiliary_state = authoritative_auxiliary_state.duplicate(true)
	_has_local_authoritative_snapshot = true


func _queue_remote_snapshot() -> void:
	var epoch_changed := false
	if not _remote_snapshots.is_empty():
		var newest: Dictionary = _remote_snapshots.back()
		epoch_changed = int(newest["epoch"]) != authoritative_epoch
	if epoch_changed:
		_remote_snapshots.clear()

	(
		_remote_snapshots
		. append(
			{
				"received_usec": Time.get_ticks_usec(),
				"epoch": authoritative_epoch,
				"transform": authoritative_transform,
				"velocity": authoritative_velocity,
			}
		)
	)
	while _remote_snapshots.size() > 8:
		_remote_snapshots.pop_front()

	if _remote_snapshots.size() == 1:
		_body.global_transform = authoritative_transform
		_body.velocity = authoritative_velocity
		_presentation.transform = Transform3D.IDENTITY
		_body.reset_physics_interpolation()


func _interpolate_remote_body() -> void:
	if _remote_snapshots.is_empty():
		return
	var render_usec := Time.get_ticks_usec() - REMOTE_BUFFER_USEC
	while (
		_remote_snapshots.size() >= 2
		and int((_remote_snapshots[1] as Dictionary)["received_usec"]) <= render_usec
	):
		_remote_snapshots.pop_front()

	var first: Dictionary = _remote_snapshots[0]
	if _remote_snapshots.size() >= 2:
		var second: Dictionary = _remote_snapshots[1]
		var first_usec := int(first["received_usec"])
		var second_usec := int(second["received_usec"])
		var span_usec := maxi(second_usec - first_usec, 1)
		var weight := clampf(float(render_usec - first_usec) / float(span_usec), 0.0, 1.0)
		_body.global_transform = (
			(first["transform"] as Transform3D)
			. interpolate_with(
				second["transform"],
				weight,
			)
		)
		_body.velocity = (first["velocity"] as Vector3).lerp(second["velocity"], weight)
		return

	var snapshot_transform: Transform3D = first["transform"]
	var snapshot_velocity: Vector3 = first["velocity"]
	var age_seconds := clampf(
		float(render_usec - int(first["received_usec"])) / 1_000_000.0,
		0.0,
		REMOTE_EXTRAPOLATION_SECONDS,
	)
	snapshot_transform.origin += snapshot_velocity * age_seconds
	_body.global_transform = snapshot_transform
	_body.velocity = snapshot_velocity


func _decay_presentation(delta: float) -> void:
	if _presentation.transform.is_equal_approx(Transform3D.IDENTITY):
		return
	var weight := 1.0 - exp(-PRESENTATION_DECAY_RATE * delta)
	_presentation.transform = (
		_presentation
		. transform
		. interpolate_with(
			Transform3D.IDENTITY,
			weight,
		)
	)


func _publish_authoritative_state() -> void:
	authoritative_transform = _body.global_transform
	authoritative_velocity = _body.velocity
	authoritative_auxiliary_state = _capture_current_auxiliary_state()
	snapshot_sequence += 1


func _sanitize_local_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> Dictionary:
	var safe_thrust := thrust.limit_length(1.0) if thrust.is_finite() else Vector3.ZERO
	var safe_look_delta := (
		look_delta.limit_length(MAX_LOOK_DELTA) if look_delta.is_finite() else Vector2.ZERO
	)
	var safe_roll := clampf(roll, -1.0, 1.0) if is_finite(roll) else 0.0
	return {
		"epoch": authoritative_epoch,
		"sequence": 0,
		"thrust": safe_thrust,
		"look_delta": safe_look_delta,
		"roll": safe_roll,
		"flags": flags & ALLOWED_FLAGS,
	}


func _simulate(command: Dictionary, context: SimulationContext) -> void:
	var fixed_delta := 1.0 / float(Engine.physics_ticks_per_second)
	(
		_simulate_command
		. call(
			command["thrust"],
			command["look_delta"],
			float(command["roll"]),
			int(command["flags"]),
			fixed_delta,
			context,
		)
	)


func _capture_current_auxiliary_state() -> Dictionary:
	if not _capture_auxiliary_state.is_valid():
		return {}
	var captured: Variant = _capture_auxiliary_state.call()
	if captured is not Dictionary:
		push_error("ClientPredictor3D auxiliary capture callback must return a Dictionary.")
		return {}
	return (captured as Dictionary).duplicate(true)


func _restore_current_auxiliary_state(state: Dictionary) -> void:
	if _restore_auxiliary_state.is_valid():
		_restore_auxiliary_state.call(state.duplicate(true))


func _do_auxiliary_states_match(predicted: Dictionary, authoritative: Dictionary) -> bool:
	if _auxiliary_states_match.is_valid():
		return bool(
			(
				_auxiliary_states_match
				. call(
					predicted.duplicate(true),
					authoritative.duplicate(true),
				)
			)
		)
	return predicted == authoritative
