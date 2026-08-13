class_name MultiplayerDrillWorld
extends Node3D

## Drill-specific authoritative world boundary.
##
## MultiplayerSessionShell and ClientPredictor3D know nothing about ore. This
## node turns accepted player intent into authoritative SDF edits and owns
## crystal release and collection. A late joiner receives one bounded field
## snapshot, then the same ordered live carve deltas as an existing peer.
## Generated meshes never cross the network: every peer remeshes locally.

signal replica_ready
signal replica_sync_failed(description: String)
signal status_changed(description: String)
signal crystal_collected(peer_id: int, total: int)

const HOST_PEER_ID := WebRTCSession.HOST_PEER_ID
const CLIENT_PEER_ID := WebRTCSession.CLIENT_PEER_ID
const ORE_ENTRY_INDEX := 0
const DRILL_TICK_SECONDS := 1.0 / 20.0
const MAX_DRILL_TICKS_PER_FRAME := 3
const SNAPSHOT_CHUNK_VALUES := 2048
const MAX_SNAPSHOT_VALUES := 65_536
const MAX_OPERATION_RADIUS := 1.0
const MAX_OPERATION_AMOUNT := 0.25
const MAX_SYNC_ATTEMPTS := 3
const SYNC_RETRY_SECONDS := 0.75
const HOST_SYNC_REQUEST_INTERVAL_MSEC := 500

@export var world_epoch := 1
@export var operation_sequence := 0
@export var crystal_state := OreNode.CrystalState.EMBEDDED
@export var crystal_transform := Transform3D.IDENTITY
@export var crystal_linear_velocity := Vector3.ZERO
@export var crystal_angular_velocity := Vector3.ZERO
@export var host_collected := 0
@export var client_collected := 0
@export var state_serial := 0

var _settings: DrillSettings
var _players: Node3D
var _ore_node: OreNode
var _initial_field := PackedFloat32Array()
var _queued_live_operations: Array[Dictionary] = []
var _incoming_field_snapshot := PackedFloat32Array()
var _expected_snapshot_values := 0
var _sync_baseline_sequence := 0
var _last_applied_sequence := 0
var _drill_accumulator := 0.0
var _host_active := false
var _replica_is_ready := false
var _sync_in_progress := false
var _built := false
var _resync_scheduled := false
var _replica_sync_attempts := 0
var _last_host_sync_request_msec := 0
var _sync_generation := 0
var _last_replica_state_serial := -1
var _last_replica_crystal_transform := Transform3D.IDENTITY
var _last_replica_linear_velocity := Vector3.ZERO
var _last_replica_angular_velocity := Vector3.ZERO


func configure(players: Node3D, settings: DrillSettings) -> void:
	_players = players
	_settings = settings if settings != null else DrillSettings.new()


func build_world() -> void:
	if _built:
		return
	if _players == null:
		push_error("MultiplayerDrillWorld must be configured before build_world().")
		return

	var entry: Dictionary = DrillKnobs.ORE_NODES[ORE_ENTRY_INDEX]
	_ore_node = OreNode.new()
	_ore_node.name = "SharedOreNode"
	_ore_node.position = entry["position"]
	_ore_node.add_to_group(&"multiplayer_drill_ore")
	add_child(_ore_node)
	_ore_node.set_release_authority(false)
	(
		_ore_node
		. build(
			int(entry["seed"]),
			float(entry["hardness"]),
			_settings.escape_clearance,
		)
	)
	_ore_node.crystal_freed.connect(_on_crystal_freed)
	_initial_field = _ore_node.export_field_values()
	crystal_transform = _ore_node.get_crystal().global_transform
	_built = true
	status_changed.emit("Shared ore field generated from seed %d." % int(entry["seed"]))


func activate_host() -> void:
	if not _built:
		return
	_host_active = true
	_replica_is_ready = true
	_sync_in_progress = false
	_ore_node.set_release_authority(true)
	_publish_crystal_state()
	status_changed.emit("Peer 1 owns drilling, crystal physics, and collection.")


func activate_client() -> void:
	if not _built:
		return
	_host_active = false
	_replica_is_ready = false
	_sync_in_progress = false
	_resync_scheduled = false
	_replica_sync_attempts = 0
	_sync_generation += 1
	_ore_node.set_release_authority(false)
	_invalidate_replica_crystal_cache()
	status_changed.emit("Waiting for the host's ore snapshot.")


func reset_for_lobby() -> void:
	_host_active = false
	_replica_is_ready = false
	_sync_in_progress = false
	_resync_scheduled = false
	_replica_sync_attempts = 0
	_last_host_sync_request_msec = 0
	_sync_generation += 1
	_drill_accumulator = 0.0
	_queued_live_operations.clear()
	_incoming_field_snapshot.clear()
	_expected_snapshot_values = 0
	_sync_baseline_sequence = 0
	_last_applied_sequence = 0
	world_epoch += 1
	operation_sequence = 0
	host_collected = 0
	client_collected = 0
	crystal_state = OreNode.CrystalState.EMBEDDED
	crystal_linear_velocity = Vector3.ZERO
	crystal_angular_velocity = Vector3.ZERO
	state_serial += 1
	_invalidate_replica_crystal_cache()
	if not _built:
		return
	_ore_node.set_release_authority(false)
	_ore_node.import_field_values(_initial_field)
	_ore_node.reset_crystal_to_embedded()
	_ore_node.run_pending_work()
	crystal_transform = _ore_node.get_crystal().global_transform


func request_replica_sync() -> void:
	if multiplayer.is_server() or not _built or _sync_in_progress:
		return
	_resync_scheduled = false
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _replica_sync_attempts >= MAX_SYNC_ATTEMPTS:
		_terminal_replica_sync_failure("Ore synchronization failed after three attempts.")
		return
	_replica_sync_attempts += 1
	_request_world_sync.rpc_id(HOST_PEER_ID)


func is_replica_ready() -> bool:
	return _replica_is_ready


func prepare_for_replica_peer() -> void:
	if multiplayer.is_server():
		_last_host_sync_request_msec = 0


func get_ore_nodes() -> Array[OreNode]:
	var result: Array[OreNode] = []
	if _ore_node != null:
		result.append(_ore_node)
	return result


func get_rock_fraction() -> float:
	return _ore_node.get_rock_fraction() if _ore_node != null else 0.0


func get_widest_opening() -> float:
	return _ore_node.get_widest_opening() if _ore_node != null else 0.0


func get_collected_total() -> int:
	return host_collected + client_collected


func _process(_delta: float) -> void:
	_update_local_drill_preview()
	if not multiplayer.is_server() and _built and not _sync_in_progress:
		_apply_replica_crystal_state_if_changed()


func _physics_process(delta: float) -> void:
	if not _host_active or not multiplayer.is_server() or not _built:
		return
	_drill_accumulator += delta
	var ticks := 0
	while _drill_accumulator >= DRILL_TICK_SECONDS and ticks < MAX_DRILL_TICKS_PER_FRAME:
		_drill_accumulator -= DRILL_TICK_SECONDS
		_run_host_drill_tick()
		ticks += 1
	if ticks == MAX_DRILL_TICKS_PER_FRAME:
		_drill_accumulator = minf(_drill_accumulator, DRILL_TICK_SECONDS)
	_collect_reachable_crystal()
	_publish_crystal_state()


func _run_host_drill_tick() -> void:
	for player in _get_players():
		if not player.is_ready_for_mining() or not player.get_authoritative_drill_active():
			continue
		var hit := _nearest_hit(player.get_drill_origin(), player.get_drill_direction())
		if hit.is_empty() or bool(hit["is_crystal"]):
			continue
		var hit_point: Vector3 = hit["position"]
		var amount := _settings.carve_rate * DRILL_TICK_SECONDS
		if _ore_node.carve(hit_point, _settings.carve_radius, amount):
			_record_carve_operation(player.controlled_peer_id, hit_point, amount)


func _record_carve_operation(source_peer: int, world_point: Vector3, amount: float) -> void:
	operation_sequence += 1
	_last_applied_sequence = operation_sequence
	var operation := {
		"epoch": world_epoch,
		"sequence": operation_sequence,
		"node_index": ORE_ENTRY_INDEX,
		"local_point": _ore_node.to_local(world_point),
		"radius": _settings.carve_radius,
		"amount": amount,
		"source_peer": source_peer,
	}
	(
		_receive_carve_operation
		. rpc(
			world_epoch,
			operation_sequence,
			ORE_ENTRY_INDEX,
			operation["local_point"],
			_settings.carve_radius,
			amount,
			source_peer,
		)
	)
	_pulse_player_drill(source_peer, world_point)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_carve_operation(
	epoch: int,
	sequence: int,
	node_index: int,
	local_point: Vector3,
	radius: float,
	amount: float,
	source_peer: int,
) -> void:
	var operation := {
		"epoch": epoch,
		"sequence": sequence,
		"node_index": node_index,
		"local_point": local_point,
		"radius": radius,
		"amount": amount,
		"source_peer": source_peer,
	}
	if not _replica_is_ready:
		_queued_live_operations.append(operation)
		return
	if not _apply_replica_operation(operation):
		_schedule_replica_resync()


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_world_sync() -> void:
	if not multiplayer.is_server() or not _host_active:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != CLIENT_PEER_ID:
		return
	var now := Time.get_ticks_msec()
	if (
		_last_host_sync_request_msec > 0
		and now - _last_host_sync_request_msec < HOST_SYNC_REQUEST_INTERVAL_MSEC
	):
		return
	_last_host_sync_request_msec = now
	var baseline := operation_sequence
	var field_snapshot := _ore_node.export_field_values()
	_begin_world_sync.rpc_id(sender_id, world_epoch, baseline, field_snapshot.size())
	var offset := 0
	while offset < field_snapshot.size():
		var end := mini(offset + SNAPSHOT_CHUNK_VALUES, field_snapshot.size())
		var chunk := field_snapshot.slice(offset, end)
		_receive_world_sync_chunk.rpc_id(sender_id, world_epoch, offset, chunk)
		offset = end
	(
		_finish_world_sync
		. rpc_id(
			sender_id,
			world_epoch,
			baseline,
			crystal_state,
			crystal_transform,
			crystal_linear_velocity,
			crystal_angular_velocity,
			host_collected,
			client_collected,
			state_serial,
		)
	)


@rpc("authority", "call_remote", "reliable", 0)
func _begin_world_sync(epoch: int, baseline: int, snapshot_values: int) -> void:
	if not _built:
		return
	if snapshot_values <= 0 or snapshot_values > MAX_SNAPSHOT_VALUES:
		_terminal_replica_sync_failure("The host sent an invalid ore snapshot size.")
		return
	_sync_in_progress = true
	_replica_is_ready = false
	world_epoch = epoch
	_last_applied_sequence = 0
	operation_sequence = baseline
	_sync_baseline_sequence = baseline
	_expected_snapshot_values = snapshot_values
	_incoming_field_snapshot.clear()
	# StateSync can continue delivering newer crystal snapshots while the field
	# chunks arrive. A sentinel lets finish preserve such a newer discrete state
	# instead of overwriting it with the state captured at the field baseline.
	state_serial = -1
	_ore_node.set_release_authority(false)
	_ore_node.reset_crystal_to_embedded()
	status_changed.emit("Receiving %d authoritative ore values…" % snapshot_values)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_world_sync_chunk(epoch: int, offset: int, values: PackedFloat32Array) -> void:
	if not _sync_in_progress or epoch != world_epoch:
		return
	if offset != _incoming_field_snapshot.size():
		_fail_replica_sync(
			(
				"Ore snapshot chunk began at %d; expected %d."
				% [offset, _incoming_field_snapshot.size()]
			),
			false,
		)
		return
	if offset + values.size() > _expected_snapshot_values:
		_fail_replica_sync("Ore snapshot exceeded its announced size.", false)
		return
	_incoming_field_snapshot.append_array(values)


@rpc("authority", "call_remote", "reliable", 0)
func _finish_world_sync(
	epoch: int,
	baseline: int,
	synced_crystal_state: int,
	synced_crystal_transform: Transform3D,
	synced_linear_velocity: Vector3,
	synced_angular_velocity: Vector3,
	synced_host_collected: int,
	synced_client_collected: int,
	synced_state_serial: int,
) -> void:
	if not _sync_in_progress or epoch != world_epoch:
		return
	if baseline != _sync_baseline_sequence:
		_fail_replica_sync("The ore snapshot baseline changed while downloading.", false)
		return
	if _incoming_field_snapshot.size() != _expected_snapshot_values:
		_fail_replica_sync(
			(
				"Ore snapshot stopped at value %d of %d."
				% [_incoming_field_snapshot.size(), _expected_snapshot_values]
			),
			false,
		)
		return
	if not _ore_node.import_field_values(_incoming_field_snapshot):
		_fail_replica_sync(
			"The ore snapshot did not match this build's field layout.",
			false,
		)
		return

	_last_applied_sequence = baseline
	operation_sequence = baseline
	if state_serial <= synced_state_serial:
		crystal_state = synced_crystal_state
		crystal_transform = synced_crystal_transform
		crystal_linear_velocity = synced_linear_velocity
		crystal_angular_velocity = synced_angular_velocity
		host_collected = synced_host_collected
		client_collected = synced_client_collected
		state_serial = synced_state_serial
	_ore_node.run_pending_work()
	_invalidate_replica_crystal_cache()
	_apply_replica_crystal_state_if_changed()
	var live_operations_applied := _apply_queued_live_operations(baseline)
	_sync_in_progress = false
	_incoming_field_snapshot.clear()
	_expected_snapshot_values = 0
	if not live_operations_applied:
		_schedule_replica_resync()
		return
	_replica_is_ready = true
	_replica_sync_attempts = 0
	status_changed.emit("Shared ore matches host snapshot %d." % operation_sequence)
	replica_ready.emit()


func _apply_queued_live_operations(baseline: int) -> bool:
	var applied_everything := true
	for operation in _queued_live_operations:
		if (
			int(operation.get("epoch", -1)) == world_epoch
			and int(operation.get("sequence", 0)) > baseline
		):
			if not _apply_replica_operation(operation):
				applied_everything = false
				break
	_queued_live_operations.clear()
	return applied_everything


func _apply_replica_operation(operation: Dictionary) -> bool:
	var epoch := int(operation.get("epoch", -1))
	var sequence := int(operation.get("sequence", 0))
	if epoch != world_epoch or sequence <= _last_applied_sequence:
		return true
	if sequence != _last_applied_sequence + 1:
		_replica_is_ready = false
		status_changed.emit(
			"Ore operation gap: expected %d, received %d." % [_last_applied_sequence + 1, sequence]
		)
		return false
	if int(operation.get("node_index", -1)) != ORE_ENTRY_INDEX:
		return false

	var local_point: Vector3 = operation.get("local_point", Vector3.INF)
	var radius := float(operation.get("radius", 0.0))
	var amount := float(operation.get("amount", 0.0))
	if (
		not local_point.is_finite()
		or radius <= 0.0
		or radius > MAX_OPERATION_RADIUS
		or amount <= 0.0
		or amount > MAX_OPERATION_AMOUNT
	):
		return false
	var world_point := _ore_node.to_global(local_point)
	_ore_node.carve(world_point, radius, amount)
	_last_applied_sequence = sequence
	operation_sequence = maxi(operation_sequence, sequence)
	_pulse_player_drill(int(operation.get("source_peer", 0)), world_point)
	return true


func _fail_replica_sync(description: String, retryable := true) -> void:
	_sync_in_progress = false
	_replica_is_ready = false
	_incoming_field_snapshot.clear()
	_expected_snapshot_values = 0
	if retryable:
		status_changed.emit(description)
		_schedule_replica_resync()
	else:
		_terminal_replica_sync_failure(description)


func _terminal_replica_sync_failure(description: String) -> void:
	_sync_in_progress = false
	_replica_is_ready = false
	_resync_scheduled = false
	_incoming_field_snapshot.clear()
	_expected_snapshot_values = 0
	status_changed.emit(description)
	replica_sync_failed.emit(description)


func _schedule_replica_resync() -> void:
	if _resync_scheduled or multiplayer.is_server():
		return
	_resync_scheduled = true
	call_deferred("_retry_replica_sync", _sync_generation)


func _retry_replica_sync(generation: int) -> void:
	await get_tree().create_timer(SYNC_RETRY_SECONDS).timeout
	if generation != _sync_generation:
		return
	_resync_scheduled = false
	if not _replica_is_ready and not _sync_in_progress:
		request_replica_sync()


func _nearest_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if _ore_node == null:
		return {}
	return _ore_node.cast(origin, direction.normalized(), _settings.drill_range)


func _update_local_drill_preview() -> void:
	if _players == null or not _built:
		return
	var local_player := (
		_players.get_node_or_null(str(multiplayer.get_unique_id())) as MultiplayerDrillPlayer
	)
	if local_player == null or not local_player.is_local_drill_active():
		if local_player != null:
			local_player.show_drill_preview(Vector3.ZERO, false, false)
		return
	var origin := local_player.get_drill_origin()
	var direction := local_player.get_drill_direction()
	var hit := _nearest_hit(origin, direction)
	var endpoint := origin + direction * _settings.drill_range
	var has_hit := false
	if not hit.is_empty():
		endpoint = hit["position"]
		has_hit = true
	local_player.show_drill_preview(endpoint, has_hit, true)


func _collect_reachable_crystal() -> void:
	if crystal_state != OreNode.CrystalState.FREE:
		return
	var crystal := _ore_node.get_crystal()
	var winner: MultiplayerDrillPlayer
	var winner_distance := INF
	for player in _get_players():
		if not player.is_ready_for_mining():
			continue
		var distance := player.global_position.distance_to(crystal.global_position)
		if distance > _settings.collect_radius:
			continue
		if (
			winner == null
			or distance < winner_distance
			or (
				is_equal_approx(distance, winner_distance)
				and player.controlled_peer_id < winner.controlled_peer_id
			)
		):
			winner = player
			winner_distance = distance
	if winner == null:
		return
	_ore_node.collect_crystal()
	crystal_state = OreNode.CrystalState.COLLECTED
	if winner.controlled_peer_id == HOST_PEER_ID:
		host_collected += 1
	else:
		client_collected += 1
	state_serial += 1
	crystal_collected.emit(winner.controlled_peer_id, get_collected_total())


func _publish_crystal_state() -> void:
	if _ore_node == null:
		return
	var new_state := _ore_node.get_crystal_state()
	if new_state != crystal_state:
		crystal_state = new_state
		state_serial += 1
	var crystal := _ore_node.get_crystal()
	crystal_transform = crystal.global_transform
	crystal_linear_velocity = crystal.linear_velocity
	crystal_angular_velocity = crystal.angular_velocity


func _apply_replica_crystal_state_if_changed() -> void:
	if (
		state_serial == _last_replica_state_serial
		and crystal_transform.is_equal_approx(_last_replica_crystal_transform)
		and crystal_linear_velocity.is_equal_approx(_last_replica_linear_velocity)
		and crystal_angular_velocity.is_equal_approx(_last_replica_angular_velocity)
	):
		return
	(
		_ore_node
		. apply_crystal_replica_state(
			crystal_state,
			crystal_transform,
			crystal_linear_velocity,
			crystal_angular_velocity,
		)
	)
	_last_replica_state_serial = state_serial
	_last_replica_crystal_transform = crystal_transform
	_last_replica_linear_velocity = crystal_linear_velocity
	_last_replica_angular_velocity = crystal_angular_velocity


func _invalidate_replica_crystal_cache() -> void:
	_last_replica_state_serial = -1
	_last_replica_crystal_transform = Transform3D.IDENTITY
	_last_replica_linear_velocity = Vector3.ZERO
	_last_replica_angular_velocity = Vector3.ZERO


func _on_crystal_freed(_node: OreNode) -> void:
	if not _host_active or not multiplayer.is_server():
		return
	crystal_state = OreNode.CrystalState.FREE
	state_serial += 1
	_publish_crystal_state()
	status_changed.emit("The crystal is loose. Fly into it to collect it.")


func _pulse_player_drill(peer_id: int, world_point: Vector3) -> void:
	if _players == null:
		return
	var player := _players.get_node_or_null(str(peer_id)) as MultiplayerDrillPlayer
	if player != null and peer_id != multiplayer.get_unique_id():
		player.pulse_remote_drill(world_point)


func _get_players() -> Array[MultiplayerDrillPlayer]:
	var result: Array[MultiplayerDrillPlayer] = []
	if _players == null:
		return result
	for child in _players.get_children():
		var player := child as MultiplayerDrillPlayer
		if player != null:
			result.append(player)
	return result
