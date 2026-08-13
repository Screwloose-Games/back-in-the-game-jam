class_name TentacleCrawlerMultiplayerDemo
extends Node3D

## Two-player, host-authoritative chase proof.
##
## MultiplayerSpawner creates deterministic survivor nodes on both peers.
## ClientPredictor3D carries sequenced movement toward peer 1 and reconciles the
## local presentation; host-owned synchronizers publish survivor snapshots plus
## crawler and round state back.

const PLAYER_SCENE := preload(
	"res://prototypes/tentacle_crawler_chaser/multiplayer_chase_player.tscn"
)
const CRAWLER_SCENE_PATH := "res://prototypes/tentacle_crawler_chaser/multiplayer_chase_crawler.tscn"
const HOST_PEER_ID := WebRTCSession.HOST_PEER_ID
const CLIENT_PEER_ID := WebRTCSession.CLIENT_PEER_ID
const PHASE_INACTIVE := 0
const PHASE_RUNNING := 1
const PHASE_CAUGHT := 2
const PHASE_ESCAPED := 3
const STATUS_ACTIVE := Color(0.42, 1.0, 0.7)
const STATUS_WARNING := Color(0.95, 0.76, 0.38)
const STATUS_DANGER := Color(1.0, 0.4, 0.48)

@export var round_phase := PHASE_INACTIVE
@export var round_message := "Waiting for the host to start the chase."
@export var target_peer_id := 0
@export var round_serial := 0

var _network_attempt_id := 0
var _entry_running := false
var _briefing_seen := false
var _crawler: MultiplayerChaseCrawler
var _last_replica_phase := -1
var _ready_player_count := 0

@onready var _session_shell: MultiplayerSessionShell = $MultiplayerSessionShell
@onready var _network_session: NetworkSession = $MultiplayerSessionShell/NetworkSession
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _players: Node3D = $Players
@onready var _chase_intent: Marker3D = $ChaseIntent
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _game_hud: CanvasLayer = $GameHud
@onready var _session_readout: Label = %SessionReadout
@onready var _round_readout: Label = %RoundReadout
@onready var _target_readout: Label = %TargetReadout
@onready var _distance_readout: Label = %DistanceReadout
@onready var _briefing: CanvasLayer = $Briefing
@onready var _briefing_session: Label = %BriefingSession
@onready var _briefing_ready: Label = %BriefingReady
@onready var _enter_button: Button = %EnterButton
@onready var _capture_prompt: PanelContainer = %CapturePrompt
@onready var _capture_button: Button = %CaptureButton


func _ready() -> void:
	_player_spawner.spawn_function = _spawn_player
	(
		_session_shell
		. configure(
			"TENTACLE CRAWLER · MULTIPLAYER",
			"Two survivors · one host-authoritative hunter",
			"Reach the green extraction line. The crawler hunts whoever falls behind.",
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

	_enter_button.pressed.connect(_on_enter_pressed)
	_capture_button.pressed.connect(_on_capture_pressed)

	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_apply_web_render_profile()
	_begin_startup_preparation()


func _process(_delta: float) -> void:
	_update_replica_crawler_presentation()
	if not _game_hud.visible:
		_capture_prompt.visible = false
		return

	var local_player := _get_local_player()
	_capture_prompt.visible = (
		local_player != null
		and not _briefing.visible
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	)
	_briefing_ready.text = (
		"Survivor ready. Enter when you are."
		if local_player != null
		else "Synchronizing your survivor…"
	)
	_enter_button.disabled = local_player == null
	_round_readout.text = round_message
	_update_target_hud(local_player)
	_update_distance_hud(local_player)


func _physics_process(_delta: float) -> void:
	if not _host_session_is_active():
		return
	var ready_players := _get_ready_players()
	var ready_player_count := ready_players.size()
	var survivor_became_ready := ready_player_count > _ready_player_count
	_ready_player_count = ready_player_count
	if survivor_became_ready:
		# Starting or restarting here gives every newly ready survivor the same
		# safe start, including a guest who joined a chase already in progress.
		_reset_host_round()
		return
	if round_phase == PHASE_INACTIVE:
		if not ready_players.is_empty():
			_reset_host_round()
		return
	if round_phase != PHASE_RUNNING:
		return
	for player in _get_players():
		player.set_authoritative_active(player.is_ready_for_chase())

	var target := _choose_lagging_player()
	if target == null:
		target_peer_id = 0
		return
	target_peer_id = target.controlled_peer_id
	_chase_intent.global_position = target.global_position
	if _all_players_reached_extraction():
		_resolve_round(PHASE_ESCAPED, "The survivors reached extraction.")


func _on_attempt_started(attempt_id: int, _role: int) -> void:
	_network_attempt_id = attempt_id
	_entry_running = false
	_cleanup_gameplay(false)


func _on_attempt_cancelled() -> void:
	_entry_running = false
	_cleanup_gameplay(false)


func _on_multiplayer_peer_ready(_peer: WebRTCMultiplayerPeer) -> void:
	if _network_session.get_role() == NetworkSession.Role.HOST:
		if not _entry_running:
			_entry_running = true
			_prepare_host_entry(_network_attempt_id)
	else:
		(
			_session_shell
			. set_stage(
				2,
				5,
				"CODE ACCEPTED",
				"Preparing this browser's direct WebRTC peer…",
			)
		)


func _on_direct_connection_opened() -> void:
	if _network_session.get_role() == NetworkSession.Role.CLIENT:
		if not _entry_running:
			_entry_running = true
			_prepare_client_entry(_network_attempt_id)
	else:
		round_message = "Survivor 02 joined. The crawler hunts the lagging survivor."


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == CLIENT_PEER_ID:
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


func _on_player_caught(body: Node3D) -> void:
	if not _host_round_is_running():
		return
	var player := body as MultiplayerChasePlayer
	if player == null or player.get_parent() != _players or not player.is_ready_for_chase():
		_crawler.set_contact_armed(true)
		return
	_resolve_round(
		PHASE_CAUGHT,
		"Survivor %02d was caught. Resetting the chase…" % player.controlled_peer_id,
	)


func _on_enter_pressed() -> void:
	var local_player := _get_local_player()
	if local_player == null:
		return
	_briefing.visible = false
	local_player.capture_local_control()


func _on_capture_pressed() -> void:
	var local_player := _get_local_player()
	if local_player != null:
		local_player.capture_local_control()


func _spawn_player(data: Variant) -> Node:
	if not data is Dictionary:
		push_error("Multiplayer chase spawn data must be a Dictionary.")
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
	var player := PLAYER_SCENE.instantiate() as MultiplayerChasePlayer
	if player == null:
		return Node.new()
	player.configure(peer_id, spawn_transform)
	return player


func _spawn_player_if_missing(peer_id: int) -> void:
	if _players.get_node_or_null(str(peer_id)) != null:
		return
	var spawn_transform := _initial_spawn_transform(peer_id)
	(
		_player_spawner
		. spawn(
			{
				"peer_id": peer_id,
				"spawn_transform": spawn_transform,
			}
		)
	)
	var player := _players.get_node_or_null(str(peer_id)) as MultiplayerChasePlayer
	if player != null:
		player.set_authoritative_active(round_phase == PHASE_RUNNING)


func _prepare_host_entry(attempt_id: int) -> void:
	(
		_session_shell
		. set_stage(
			2,
			4,
			"SESSION %s IS LIVE" % _network_session.get_session_code(),
			"Survivor 02 can join while the host begins the chase.",
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
			"STARTING AUTHORITATIVE WORLD",
			"Peer 1 is taking ownership of both survivors and the crawler…",
		)
	)
	_prepare_host_world()
	_spawn_player_if_missing(HOST_PEER_ID)
	var local_player := _get_local_player()
	if local_player == null:
		_session_shell.abort_attempt("The host session opened, but its survivor did not spawn.")
		return

	local_player.activate_local_camera()
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return

	(
		_session_shell
		. set_stage(
			4,
			4,
			"CHASE READY",
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
			5,
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
			5,
			"SPAWNING SURVIVOR",
			"Waiting for the host to replicate your body and chase state…",
		)
	)
	var deadline := Time.get_ticks_msec() + 10_000
	var local_player := _get_local_player()
	while local_player == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _session_shell.is_attempt_current(attempt_id):
			return
		local_player = _get_local_player()

	if local_player == null:
		_session_shell.abort_attempt(
			"Connected to the host, but the local survivor did not finish spawning."
		)
		return

	local_player.activate_local_camera()
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	(
		_session_shell
		. set_stage(
			5,
			5,
			"SURVIVOR READY",
			"The host owns the chase; this browser owns only survivor input.",
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
			"PREPARING CHASE DEMO",
			"Building a small static corridor with no runtime navmesh or CSG bake…",
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
			"LOADING PROCEDURAL CRAWLER",
			"Constructing the creature after this loading screen has painted…",
		)
	)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	if not _instantiate_crawler():
		(
			_session_shell
			. set_stage(
				1,
				1,
				"DEMO COULD NOT LOAD",
				"The procedural crawler scene could not be instantiated.",
				true,
			)
		)
		return
	if not await _prewarm_crawler(attempt_id):
		return

	_session_shell.set_stage(3, 3, "DEMO READY", "Choose Host or Join.", true)
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return
	_session_shell.finish_loading(attempt_id)
	_session_shell.show_lobby("Choose Host or enter a six-character session code.")


func _prewarm_crawler(attempt_id: int) -> bool:
	await get_tree().process_frame
	if not _session_shell.is_attempt_current(attempt_id):
		return false
	if OS.has_feature("web") and DisplayServer.get_name() != "headless":
		(
			_session_shell
			. set_stage(
				3,
				3,
				"WARMING CRAWLER VISUALS",
				"Preparing the procedural creature in a tiny off-screen viewport…",
			)
		)
		await get_tree().process_frame
		if not _session_shell.is_attempt_current(attempt_id):
			return false
		var prewarm_viewport := _create_prewarm_viewport()
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(prewarm_viewport):
			prewarm_viewport.queue_free()
	return _session_shell.is_attempt_current(attempt_id)


func _create_prewarm_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "CrawlerPrewarmViewport"
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 20.0)
	camera.rotation.y = PI
	camera.near = 0.05
	camera.far = 24.0
	viewport.add_child(camera)
	camera.current = true

	var lamp := SpotLight3D.new()
	lamp.light_energy = 3.5
	lamp.shadow_enabled = false
	lamp.spot_range = 24.0
	camera.add_child(lamp)
	return viewport


func _instantiate_crawler() -> bool:
	if _crawler != null:
		return true
	var crawler_scene := load(CRAWLER_SCENE_PATH) as PackedScene
	if crawler_scene == null:
		return false
	_crawler = crawler_scene.instantiate() as MultiplayerChaseCrawler
	if _crawler == null:
		return false
	_crawler.name = "Crawler"
	_crawler.position = MultiplayerChaseKnobs.CRAWLER_SPAWN
	_crawler.target_marker = _chase_intent
	_crawler.set_multiplayer_authority(HOST_PEER_ID, true)
	add_child(_crawler)
	_crawler.get_node("CreatureContact").caught.connect(_on_player_caught)
	_crawler.set_session_active(false)
	return true


func _reset_host_round() -> void:
	if not multiplayer.is_server():
		return
	var ready_players := _get_ready_players()
	if ready_players.is_empty():
		_prepare_host_world()
		return
	round_serial += 1
	round_phase = PHASE_RUNNING
	round_message = "Reach the green extraction line. The crawler hunts whoever lags behind."
	target_peer_id = ready_players[0].controlled_peer_id
	_chase_intent.global_position = ready_players[0].global_position
	_crawler.reset_authoritative_state()
	_crawler.set_session_active(true)
	for player in _get_players():
		var spawn_position := (
			MultiplayerChaseKnobs.HOST_SPAWN
			if player.controlled_peer_id == HOST_PEER_ID
			else MultiplayerChaseKnobs.CLIENT_SPAWN
		)
		(
			player
			. reset_authoritative_state(
				Transform3D(Basis.IDENTITY, spawn_position),
				player.is_ready_for_chase(),
			)
		)
	_ready_player_count = ready_players.size()


func _prepare_host_world() -> void:
	if not multiplayer.is_server():
		return
	round_serial += 1
	round_phase = PHASE_INACTIVE
	round_message = "Press Enter when ready. The crawler is waiting at the far end."
	target_peer_id = 0
	_chase_intent.global_position = MultiplayerChaseKnobs.HOST_SPAWN
	_crawler.reset_authoritative_state()
	_crawler.set_session_active(false)
	for player in _get_players():
		player.set_authoritative_active(false)
	_ready_player_count = _get_ready_players().size()


func _resolve_round(phase: int, message: String) -> void:
	if not _host_round_is_running():
		return
	round_phase = phase
	round_message = message
	round_serial += 1
	var outcome_serial := round_serial
	_crawler.set_contact_armed(false)
	_crawler.set_session_active(false)
	for player in _get_players():
		player.set_authoritative_active(false)

	await get_tree().create_timer(ChaseKnobs.CATCH_RESPAWN_DELAY).timeout
	if not is_inside_tree() or outcome_serial != round_serial or not _host_session_is_active():
		return
	_reset_host_round()


func _choose_lagging_player() -> MultiplayerChasePlayer:
	var candidate: MultiplayerChasePlayer
	for player in _get_ready_players():
		if candidate == null or player.global_position.z > candidate.global_position.z:
			candidate = player
	var current := _players.get_node_or_null(str(target_peer_id)) as MultiplayerChasePlayer
	if (
		current != null
		and candidate != null
		and candidate != current
		and (
			candidate.global_position.z
			< current.global_position.z + MultiplayerChaseKnobs.TARGET_SWITCH_MARGIN
		)
	):
		return current
	return candidate


func _all_players_reached_extraction() -> bool:
	var active_players := _get_ready_players()
	if active_players.is_empty():
		return false
	for player in active_players:
		if player.global_position.z > MultiplayerChaseKnobs.EXTRACTION_Z:
			return false
	return true


func _remove_remote_player(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id != CLIENT_PEER_ID:
		return
	var player := _players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()
	target_peer_id = HOST_PEER_ID
	round_message = "Survivor 02 left. The host continues the chase solo."


func _cleanup_gameplay(clear_players: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_briefing_seen = false
	_last_replica_phase = -1
	_ready_player_count = 0
	if _crawler != null:
		_crawler.set_session_active(false)
	if clear_players:
		for child in _players.get_children():
			child.queue_free()
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		round_phase = PHASE_INACTIVE
		round_message = "Waiting for the host to start the chase."
		target_peer_id = 0


func _show_briefing(role_name: String) -> void:
	_briefing_session.text = (
		"%s · SESSION %s"
		% [
			role_name,
			_network_session.get_session_code(),
		]
	)
	_briefing.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var local_player := _get_local_player()
	if local_player != null:
		local_player.release_local_control()


func _update_target_hud(local_player: MultiplayerChasePlayer) -> void:
	if local_player == null or target_peer_id == 0:
		_target_readout.text = "CRAWLER TARGET · ACQUIRING"
		_target_readout.add_theme_color_override("font_color", STATUS_WARNING)
	elif target_peer_id == local_player.controlled_peer_id:
		_target_readout.text = "CRAWLER TARGET · YOU"
		_target_readout.add_theme_color_override("font_color", STATUS_DANGER)
	else:
		_target_readout.text = "CRAWLER TARGET · SURVIVOR %02d" % target_peer_id
		_target_readout.add_theme_color_override("font_color", STATUS_ACTIVE)


func _update_distance_hud(local_player: MultiplayerChasePlayer) -> void:
	if local_player == null:
		_distance_readout.text = "EXTRACTION · SYNCING"
		return
	var distance := maxf(
		local_player.global_position.z - MultiplayerChaseKnobs.EXTRACTION_Z,
		0.0,
	)
	_distance_readout.text = "EXTRACTION · %.0f m" % distance


func _get_players() -> Array[MultiplayerChasePlayer]:
	var result: Array[MultiplayerChasePlayer] = []
	for child in _players.get_children():
		var player := child as MultiplayerChasePlayer
		if player != null:
			result.append(player)
	return result


func _get_ready_players() -> Array[MultiplayerChasePlayer]:
	var result: Array[MultiplayerChasePlayer] = []
	for player in _get_players():
		if player.is_ready_for_chase():
			result.append(player)
	return result


func _get_local_player() -> MultiplayerChasePlayer:
	return _players.get_node_or_null(str(multiplayer.get_unique_id())) as MultiplayerChasePlayer


func _initial_spawn_transform(peer_id: int) -> Transform3D:
	if peer_id == HOST_PEER_ID:
		return Transform3D(Basis.IDENTITY, MultiplayerChaseKnobs.HOST_SPAWN)

	# A late guest stages beside the host instead of appearing in the crawler's
	# current path. When the guest presses Enter, the host resets the full chase
	# and moves both ready survivors to their authored starting positions.
	var host := _players.get_node_or_null(str(HOST_PEER_ID)) as MultiplayerChasePlayer
	if host == null:
		return Transform3D(Basis.IDENTITY, MultiplayerChaseKnobs.CLIENT_SPAWN)
	var basis := host.global_transform.basis.orthonormalized()
	var position := host.global_position + basis.x * 1.5
	var half_width := MultiplayerChaseKnobs.ARENA_WIDTH * 0.5 - 0.75
	var half_length := MultiplayerChaseKnobs.ARENA_LENGTH * 0.5 - 1.0
	position.x = clampf(position.x, -half_width, half_width)
	position.y = clampf(position.y, -half_width, half_width)
	position.z = clampf(position.z, -half_length, half_length)
	return Transform3D(basis, position)


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


func _host_round_is_running() -> bool:
	return _host_session_is_active() and round_phase == PHASE_RUNNING


func _update_replica_crawler_presentation() -> void:
	if multiplayer.is_server() or _crawler == null or round_phase == _last_replica_phase:
		return
	_last_replica_phase = round_phase
	_crawler.set_session_active(round_phase == PHASE_RUNNING)


func _apply_web_render_profile() -> void:
	if not OS.has_feature("web"):
		return
	if _world_environment.environment != null:
		_world_environment.environment.glow_enabled = false
