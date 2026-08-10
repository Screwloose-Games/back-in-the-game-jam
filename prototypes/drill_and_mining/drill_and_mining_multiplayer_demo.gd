class_name DrillAndMiningMultiplayerDemo
extends Node3D

## Two-player, host-authoritative drilling proof.
##
## The reusable session shell owns connection UX. MultiplayerSpawner owns player
## lifecycle. ClientPredictor3D owns movement transport. MultiplayerDrillWorld
## is the only layer that understands SDF edits, snapshot/delta replication, crystal
## physics, collection, and late-join convergence.

const PLAYER_SCENE := preload("res://prototypes/drill_and_mining/multiplayer_drill_player.tscn")
const HOST_PEER_ID := WebRTCSession.HOST_PEER_ID
const CLIENT_PEER_ID := WebRTCSession.CLIENT_PEER_ID
const HOST_SPAWN := Vector3(-0.9, 0.0, 5.0)
const CLIENT_SPAWN := Vector3(0.9, 0.0, 5.0)
const CLIENT_WORLD_SYNC_TIMEOUT_MSEC := 15_000
const STATUS_ACTIVE := Color(0.42, 1.0, 0.7)
const STATUS_WARNING := Color(0.95, 0.76, 0.38)

@export var settings: DrillSettings

var _network_attempt_id := 0
var _entry_running := false
var _briefing_seen := false
var _last_crystal_state := -1
var _world_status := "Shared ore is ready."

@onready var _session_shell: MultiplayerSessionShell = $MultiplayerSessionShell
@onready var _network_session: NetworkSession = $MultiplayerSessionShell/NetworkSession
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _players: Node3D = $Players
@onready var _drill_world: MultiplayerDrillWorld = $DrillWorld
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _game_hud: CanvasLayer = $GameHud
@onready var _session_readout: Label = %SessionReadout
@onready var _ore_readout: Label = %OreReadout
@onready var _crystal_readout: Label = %CrystalReadout
@onready var _score_readout: Label = %ScoreReadout
@onready var _notice_readout: Label = %NoticeReadout
@onready var _briefing: CanvasLayer = $Briefing
@onready var _briefing_session: Label = %BriefingSession
@onready var _briefing_ready: Label = %BriefingReady
@onready var _enter_button: Button = %EnterButton
@onready var _capture_prompt: PanelContainer = %CapturePrompt
@onready var _capture_button: Button = %CaptureButton


func _ready() -> void:
	if settings == null:
		settings = DrillSettings.new()
	_player_spawner.spawn_function = _spawn_player
	_drill_world.configure(_players, settings)
	(
		_session_shell
		. configure(
			"DRILL & MINING · MULTIPLAYER",
			"Two miners · one host-authoritative ore field",
			"Cut one shared crystal free. Either miner can drill or collect it.",
		)
	)
	_session_shell.attempt_started.connect(_on_attempt_started)
	_session_shell.attempt_cancelled.connect(_on_attempt_cancelled)

	_network_session.multiplayer_peer_ready.connect(_on_multiplayer_peer_ready)
	_network_session.direct_connection_opened.connect(_on_direct_connection_opened)
	_network_session.peer_left.connect(_on_peer_left)
	_network_session.session_failed.connect(_on_session_failed)
	_network_session.session_closed.connect(_on_session_closed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_drill_world.replica_ready.connect(_on_world_replica_ready)
	_drill_world.replica_sync_failed.connect(_on_world_replica_sync_failed)
	_drill_world.status_changed.connect(_on_world_status_changed)
	_drill_world.crystal_collected.connect(_on_crystal_collected)
	_enter_button.pressed.connect(_on_enter_pressed)
	_capture_button.pressed.connect(_on_capture_pressed)

	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_apply_web_render_profile()
	_begin_startup_preparation()


func _process(_delta: float) -> void:
	if not _game_hud.visible:
		_capture_prompt.visible = false
		return
	var local_player := _get_local_player()
	_capture_prompt.visible = (
		local_player != null
		and not _briefing.visible
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	)
	_update_briefing_readiness(local_player)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if not _host_session_is_active():
		return
	for player in _get_players():
		player.set_authoritative_active(player.is_ready_for_mining())


func _on_attempt_started(attempt_id: int, _role: int) -> void:
	_network_attempt_id = attempt_id
	_entry_running = false
	_cleanup_gameplay(true)


func _on_attempt_cancelled() -> void:
	_entry_running = false
	_cleanup_gameplay(true)


func _on_multiplayer_peer_ready(_peer: WebRTCMultiplayerPeer) -> void:
	if _network_session.get_role() == NetworkSession.Role.HOST:
		_drill_world.activate_host()
		if not _entry_running:
			_entry_running = true
			_prepare_host_entry(_network_attempt_id)
	else:
		(
			_session_shell
			. set_stage(
				2,
				6,
				"CODE ACCEPTED",
				"Preparing this browser's direct WebRTC peer…",
			)
		)


func _on_direct_connection_opened() -> void:
	if _network_session.get_role() == NetworkSession.Role.CLIENT:
		_drill_world.activate_client()
		if not _entry_running:
			_entry_running = true
			_prepare_client_entry(_network_attempt_id)
	else:
		_world_status = "Miner 02 joined. The host keeps ownership of the ore."


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == CLIENT_PEER_ID:
		_drill_world.prepare_for_replica_peer()
		_spawn_player_if_missing(CLIENT_PEER_ID)


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_remote_player(peer_id)


func _on_peer_left(peer_id: int) -> void:
	_remove_remote_player(peer_id)


func _on_session_failed(_description: String) -> void:
	_entry_running = false
	_cleanup_gameplay(true)


func _on_session_closed(_close_code: int, _reason: String) -> void:
	_entry_running = false
	_cleanup_gameplay(true)


func _on_world_replica_ready() -> void:
	_world_status = "Ore snapshot applied. This field now matches peer 1."


func _on_world_replica_sync_failed(description: String) -> void:
	_world_status = description
	if _network_session.get_role() == NetworkSession.Role.CLIENT:
		_session_shell.abort_attempt(description)


func _on_world_status_changed(description: String) -> void:
	_world_status = description


func _on_crystal_collected(peer_id: int, _total: int) -> void:
	_world_status = "Miner %02d collected the shared crystal." % peer_id


func _on_enter_pressed() -> void:
	var local_player := _get_local_player()
	if local_player == null or not _local_world_is_ready():
		return
	_briefing.visible = false
	local_player.capture_local_control()


func _on_capture_pressed() -> void:
	var local_player := _get_local_player()
	if local_player != null:
		local_player.capture_local_control()


func _spawn_player(data: Variant) -> Node:
	if not data is Dictionary:
		push_error("Multiplayer drill spawn data must be a Dictionary.")
		return Node.new()
	var spawn_data: Dictionary = data
	var peer_id := int(spawn_data.get("peer_id", 0))
	var spawn_transform: Transform3D = (
		spawn_data
		. get(
			"spawn_transform",
			Transform3D.IDENTITY,
		)
	)
	var player := PLAYER_SCENE.instantiate() as MultiplayerDrillPlayer
	if player == null:
		return Node.new()
	player.configure(peer_id, spawn_transform)
	return player


func _spawn_player_if_missing(peer_id: int) -> void:
	if _players.get_node_or_null(str(peer_id)) != null:
		return
	(
		_player_spawner
		. spawn(
			{
				"peer_id": peer_id,
				"spawn_transform": _initial_spawn_transform(peer_id),
			}
		)
	)
	var player := _players.get_node_or_null(str(peer_id)) as MultiplayerDrillPlayer
	if player != null:
		player.set_authoritative_active(false)


func _prepare_host_entry(attempt_id: int) -> void:
	(
		_session_shell
		. set_stage(
			2,
			4,
			"SESSION %s IS LIVE" % _network_session.get_session_code(),
			"Miner 02 can join while the host begins drilling.",
		)
	)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return

	(
		_session_shell
		. set_stage(
			3,
			4,
			"STARTING AUTHORITATIVE MINE",
			"Peer 1 is taking ownership of movement, ore edits, and the crystal…",
		)
	)
	_spawn_player_if_missing(HOST_PEER_ID)
	var local_player := _get_local_player()
	if local_player == null:
		_session_shell.abort_attempt("The host session opened, but its miner did not spawn.")
		return
	local_player.activate_local_camera()
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return

	(
		_session_shell
		. set_stage(
			4,
			4,
			"MINE READY",
			"The host can play now; the join code remains active.",
			true,
		)
	)
	await get_tree().process_frame
	_finish_entry(attempt_id, "HOST")


func _prepare_client_entry(attempt_id: int) -> void:
	(
		_session_shell
		. set_stage(
			3,
			6,
			"PEER ROUTE ESTABLISHED",
			"Gameplay now travels directly between the two browsers.",
		)
	)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return

	(
		_session_shell
		. set_stage(
			4,
			6,
			"REQUESTING ORE SNAPSHOT",
			"The host may already have drilled while waiting for you…",
		)
	)
	_drill_world.request_replica_sync()
	var deadline := Time.get_ticks_msec() + CLIENT_WORLD_SYNC_TIMEOUT_MSEC
	while not _drill_world.is_replica_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _session_shell.is_attempt_current(attempt_id):
			return
	if not _drill_world.is_replica_ready():
		_session_shell.abort_attempt("Connected, but the authoritative ore snapshot timed out.")
		return

	(
		_session_shell
		. set_stage(
			5,
			6,
			"SPAWNING MINER",
			"Waiting for peer 1 to replicate your predicted suit…",
		)
	)
	# Field snapshot import and player spawning are independent network jobs. Give
	# the replicated player its own timeout after the bounded snapshot completes.
	deadline = Time.get_ticks_msec() + CLIENT_WORLD_SYNC_TIMEOUT_MSEC
	var local_player := _get_local_player()
	while local_player == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _session_shell.is_attempt_current(attempt_id):
			return
		local_player = _get_local_player()
	if local_player == null:
		_session_shell.abort_attempt("Connected, but the local miner did not finish spawning.")
		return

	local_player.activate_local_camera()
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	(
		_session_shell
		. set_stage(
			6,
			6,
			"MINER READY",
			"Movement is predicted locally; peer 1 orders every accepted carve.",
			true,
		)
	)
	await get_tree().process_frame
	_finish_entry(attempt_id, "JOINER")


func _finish_entry(attempt_id: int, role_name: String) -> void:
	if not _session_shell.is_attempt_current(attempt_id):
		return
	_session_shell.finish_loading(attempt_id)
	_entry_running = false
	_game_hud.visible = true
	_session_readout.text = "%s · SESSION %s" % [role_name, _network_session.get_session_code()]
	if not _briefing_seen:
		_briefing_seen = true
		_show_briefing(role_name)


func _begin_startup_preparation() -> void:
	var attempt_id := (
		_session_shell
		. begin_loading(
			1,
			3,
			"PREPARING MINING DEMO",
			"Loading the shared chamber after this screen has painted…",
			false,
		)
	)
	_prepare_startup(attempt_id)


func _prepare_startup(attempt_id: int) -> void:
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	(
		_session_shell
		. set_stage(
			2,
			3,
			"GENERATING SHARED ORE",
			"Building one deterministic SDF field and its initial collision mesh…",
		)
	)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	_drill_world.build_world()
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	await _prewarm_world(attempt_id)
	if not _session_shell.is_attempt_current(attempt_id):
		return
	_session_shell.set_stage(3, 3, "DEMO READY", "Choose Host or Join.", true)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	_session_shell.finish_loading(attempt_id)
	_session_shell.show_lobby("Choose Host or enter a six-character session code.")


func _prewarm_world(attempt_id: int) -> void:
	if not OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	(
		_session_shell
		. set_stage(
			3,
			3,
			"WARMING MINING VISUALS",
			"Preparing ore, beam, and helmet-lamp materials off-screen…",
		)
	)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	var viewport := _create_prewarm_viewport()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(viewport):
		viewport.queue_free()


func _create_prewarm_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "MiningPrewarmViewport"
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	camera.far = 16.0
	viewport.add_child(camera)
	camera.current = true
	var lamp := SpotLight3D.new()
	lamp.light_energy = DrillKnobs.HELMET_LAMP_ENERGY
	lamp.shadow_enabled = false
	lamp.spot_range = 16.0
	camera.add_child(lamp)
	return viewport


func _show_briefing(role_name: String) -> void:
	_briefing_session.text = "%s · SESSION %s" % [role_name, _network_session.get_session_code()]
	_briefing.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var local_player := _get_local_player()
	if local_player != null:
		local_player.release_local_control()


func _update_briefing_readiness(local_player: MultiplayerDrillPlayer) -> void:
	var ready := local_player != null and _local_world_is_ready()
	_briefing_ready.text = (
		"Miner and shared ore ready. Enter when you are."
		if ready
		else "Synchronizing miner and shared ore…"
	)
	_enter_button.disabled = not ready


func _update_hud() -> void:
	var rock_percent := _drill_world.get_rock_fraction() * 100.0
	_ore_readout.text = (
		"ROCK %3.0f%%  ·  OPENING %.2f / %.2f m  ·  CARVE #%d"
		% [
			rock_percent,
			_drill_world.get_widest_opening(),
			settings.escape_clearance,
			_drill_world.operation_sequence,
		]
	)
	var crystal_label := "EMBEDDED"
	if _drill_world.crystal_state == OreNode.CrystalState.FREE:
		crystal_label = "LOOSE · FLY INTO IT"
	elif _drill_world.crystal_state == OreNode.CrystalState.COLLECTED:
		crystal_label = "COLLECTED"
	_crystal_readout.text = "CRYSTAL · %s" % crystal_label
	_score_readout.text = (
		"HOST %d  ·  MINER-02 %d" % [_drill_world.host_collected, _drill_world.client_collected]
	)
	_notice_readout.text = _world_status
	if _drill_world.crystal_state != _last_crystal_state:
		_last_crystal_state = _drill_world.crystal_state
		(
			_notice_readout
			. add_theme_color_override(
				"font_color",
				(
					STATUS_WARNING
					if _last_crystal_state == OreNode.CrystalState.EMBEDDED
					else STATUS_ACTIVE
				),
			)
		)


func _cleanup_gameplay(clear_players: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_briefing_seen = false
	_last_crystal_state = -1
	if clear_players:
		for child in _players.get_children():
			_players.remove_child(child)
			child.queue_free()
		_drill_world.reset_for_lobby()


func _remove_remote_player(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id != CLIENT_PEER_ID:
		return
	var player := _players.get_node_or_null(str(peer_id))
	if player != null:
		_players.remove_child(player)
		player.queue_free()
	_world_status = "Miner 02 left. The host keeps the mined field and continues solo."


func _get_players() -> Array[MultiplayerDrillPlayer]:
	var result: Array[MultiplayerDrillPlayer] = []
	for child in _players.get_children():
		var player := child as MultiplayerDrillPlayer
		if player != null:
			result.append(player)
	return result


func _get_local_player() -> MultiplayerDrillPlayer:
	return _players.get_node_or_null(str(multiplayer.get_unique_id())) as MultiplayerDrillPlayer


func _initial_spawn_transform(peer_id: int) -> Transform3D:
	if peer_id == HOST_PEER_ID:
		return Transform3D(Basis.IDENTITY, HOST_SPAWN)
	var host := _players.get_node_or_null(str(HOST_PEER_ID)) as MultiplayerDrillPlayer
	if host == null:
		return Transform3D(Basis.IDENTITY, CLIENT_SPAWN)
	var basis := host.global_transform.basis.orthonormalized()
	var position := host.global_position + basis.x * 1.8
	var half_size := DrillKnobs.CHAMBER_SIZE * 0.5 - Vector3.ONE
	position.x = clampf(position.x, -half_size.x, half_size.x)
	position.y = clampf(position.y, -half_size.y, half_size.y)
	position.z = clampf(position.z, -half_size.z, half_size.z)
	return Transform3D(basis, position)


func _local_world_is_ready() -> bool:
	return (
		_network_session.get_role() == NetworkSession.Role.HOST or _drill_world.is_replica_ready()
	)


func _host_session_is_active() -> bool:
	return (
		multiplayer.is_server()
		and _network_session.get_role() == NetworkSession.Role.HOST
		and (
			_network_session.get_state()
			in [
				NetworkSession.State.WAITING_FOR_PEER,
				NetworkSession.State.NEGOTIATING_WEBRTC,
				NetworkSession.State.CONNECTED,
			]
		)
	)


func _apply_web_render_profile() -> void:
	if not OS.has_feature("web"):
		return
	if _world_environment.environment != null:
		_world_environment.environment.glow_enabled = false
