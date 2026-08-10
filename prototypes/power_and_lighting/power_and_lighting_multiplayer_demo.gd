class_name PowerAndLightingMultiplayerDemo
extends Node3D

## Integrated two-player power-and-lighting multiplayer proof.
##
## The host starts playing immediately under peer-1 authority. MultiplayerSpawner
## adds the second survivor after WebRTC connects. Input synchronizers flow toward
## the host; state synchronizers flow accepted transforms and power back out.

const PLAYER_SCENE := preload("res://prototypes/power_and_lighting/multiplayer_power_player.tscn")
const HOST_PEER_ID := WebRTCSession.HOST_PEER_ID
const CLIENT_PEER_ID := WebRTCSession.CLIENT_PEER_ID
const HOST_SPAWN := Vector3(-3.0, 0.0, 6.0)
const CLIENT_SPAWN := Vector3(3.0, 0.0, 6.0)
const STATUS_IDLE := Color(0.95, 0.76, 0.38)
const STATUS_ACTIVE := Color(0.42, 1.0, 0.7)
const STATUS_ERROR := Color(1.0, 0.4, 0.48)
const WEB_PREWARM_CAMERA_HEIGHT := 0.25
const WEB_PREWARM_CAMERA_FOV := 75.0
const WEB_PREWARM_CAMERA_NEAR := 0.05
const WEB_PREWARM_CAMERA_FAR := 28.0

var _briefing_seen := false
var _loading_attempt_id := 0
var _loading_started_at_msec := 0
var _entry_preparation_running := false
var _loading_cancel_requested := false

@onready var _network_session: NetworkSession = $NetworkSession
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _players: Node3D = $Players
@onready var _cube: MultiplayerPowerCube = $PowerCube
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _lobby: CanvasLayer = $Lobby
@onready var _game_hud: CanvasLayer = $GameHud
@onready var _endpoint_input: LineEdit = %SignalingEndpointInput
@onready var _session_code_input: LineEdit = %SessionCodeInput
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _lobby_status: Label = %LobbyStatus
@onready var _connection_detail: Label = %ConnectionDetail
@onready var _session_status: Label = %SessionStatus
@onready var _session_code: Label = %SessionCode
@onready var _power_bar: ProgressBar = %SharedPowerBar
@onready var _power_readout: Label = %SharedPowerReadout
@onready var _action_prompt: Label = %ActionPrompt
@onready var _briefing: CanvasLayer = $Briefing
@onready var _briefing_session: Label = %BriefingSession
@onready var _briefing_ready_status: Label = %BriefingReadyStatus
@onready var _briefing_begin_button: Button = %BriefingBeginButton
@onready var _capture_prompt: PanelContainer = %CapturePrompt
@onready var _capture_button: Button = %CaptureButton
@onready var _connection_progress: CanvasLayer = $ConnectionProgress
@onready var _loading_phase: Label = %LoadingPhase
@onready var _loading_title: Label = %LoadingTitle
@onready var _loading_session_code: Label = %LoadingSessionCode
@onready var _loading_detail: Label = %LoadingDetail
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _loading_cancel_button: Button = %LoadingCancelButton


func _ready() -> void:
	_player_spawner.spawn_function = _spawn_player
	_cube.set_authoritative_simulation(false)
	_apply_web_demo_render_profile()

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_briefing_begin_button.pressed.connect(_on_briefing_begin_pressed)
	_capture_button.pressed.connect(_on_capture_pressed)
	_loading_cancel_button.pressed.connect(_on_loading_cancel_pressed)

	_network_session.state_changed.connect(_on_session_state_changed)
	_network_session.host_started.connect(_on_host_started)
	_network_session.multiplayer_peer_ready.connect(_on_multiplayer_peer_ready)
	_network_session.direct_connection_opened.connect(_on_direct_connection_opened)
	_network_session.peer_left.connect(_on_peer_left)
	_network_session.session_failed.connect(_on_session_failed)
	_network_session.session_closed.connect(_on_session_closed)
	_network_session.transport_diagnostic.connect(_on_transport_diagnostic)

	# These signals belong to the persistent SceneTree MultiplayerAPI. They stay
	# connected while NetworkSession swaps its Offline peer for WebRTC.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_multiplayer_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_lobby.visible = false
	_set_lobby_enabled(false)
	_begin_startup_preparation()


func _process(_delta: float) -> void:
	_power_bar.value = _cube.power_fraction * 100.0
	_power_readout.text = "SHARED CUBE POWER  %3.0f%%" % (_cube.power_fraction * 100.0)
	_update_interaction_hud()


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or _network_session.get_role() != NetworkSession.Role.HOST:
		return
	if (
		_network_session.get_state()
		not in [
			NetworkSession.State.WAITING_FOR_PEER,
			NetworkSession.State.NEGOTIATING_WEBRTC,
			NetworkSession.State.CONNECTED,
		]
	):
		return

	var active_players := 0
	var cranking_players := 0
	for child in _players.get_children():
		var player := child as MultiplayerPowerPlayer
		if player == null:
			continue
		active_players += 1
		if player.is_cranking_cube():
			cranking_players += 1
	_cube.set_power_activity(active_players, cranking_players)


func _on_host_pressed() -> void:
	_release_ui_focus()
	_connection_detail.text = ""
	_set_lobby_enabled(false)
	var attempt_id := _begin_loading(
		1,
		4,
		"CREATING SESSION",
		"Contacting the signaling service…",
	)
	var result: Error = _network_session.host(_endpoint_input.text)
	if result != OK:
		_cancel_loading(attempt_id)
		_show_lobby_error("Could not host. Error: %d" % result)


func _on_join_pressed() -> void:
	_release_ui_focus()
	_connection_detail.text = ""
	var code := _session_code_input.text.strip_edges().to_upper()
	_session_code_input.text = code
	_set_lobby_enabled(false)
	var attempt_id := _begin_loading(
		1,
		5,
		"FINDING SESSION %s" % code,
		"Contacting the signaling service…",
	)
	_show_loading_session_code("SESSION CODE  %s" % code)
	var result: Error = _network_session.join(_endpoint_input.text, code)
	if result != OK:
		_cancel_loading(attempt_id)
		_show_lobby_error("Could not join. Check the six-character code.")


func _on_host_started(code: String) -> void:
	_session_code_input.text = code
	_session_code.text = "SESSION  %s  ·  HOST" % code
	_show_loading_session_code("JOIN CODE  %s" % code)
	_set_loading_stage(
		1,
		4,
		"RESERVING PRIVATE SESSION",
		"Opening the private session on the signaling service…",
	)


func _on_multiplayer_peer_ready(_peer: WebRTCMultiplayerPeer) -> void:
	if _network_session.get_role() == NetworkSession.Role.HOST:
		if not _entry_preparation_running:
			_entry_preparation_running = true
			_prepare_host_entry(_loading_attempt_id)
	else:
		_cube.set_authoritative_simulation(false)
		_set_loading_stage(
			2,
			5,
			"CODE ACCEPTED",
			"Preparing the browser's direct peer connection…",
		)
		_present_client_peer_route_stage(_loading_attempt_id)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == CLIENT_PEER_ID:
		_spawn_player_if_missing(CLIENT_PEER_ID)
		_set_game_status("Survivor 02 joined · direct WebRTC route", STATUS_ACTIVE)


func _on_connected_to_server() -> void:
	if not _entry_preparation_running:
		_entry_preparation_running = true
		_prepare_client_entry(_loading_attempt_id)


func _on_direct_connection_opened() -> void:
	if _network_session.get_role() == NetworkSession.Role.CLIENT:
		_set_loading_stage(
			3,
			5,
			"PEER ROUTE ESTABLISHED",
			"The direct WebRTC connection to the host is ready.",
		)
	else:
		_set_game_status("Survivor 02 connected · host owns simulation", STATUS_ACTIVE)


func _on_briefing_begin_pressed() -> void:
	var local_player := _get_local_player()
	if local_player == null:
		return
	_briefing.visible = false
	local_player.capture_local_control()


func _on_capture_pressed() -> void:
	var local_player := _get_local_player()
	if local_player != null:
		local_player.capture_local_control()


func _on_loading_cancel_pressed() -> void:
	if _network_session.get_state() == NetworkSession.State.IDLE:
		return
	# Stop every in-flight loading coroutine before signaling shutdown begins.
	_loading_attempt_id += 1
	_entry_preparation_running = false
	_loading_cancel_requested = true
	_loading_cancel_button.disabled = true
	_set_loading_stage(
		1,
		1,
		"CLOSING SESSION",
		"Returning to the multiplayer lobby…",
	)
	_network_session.close_session("Connection cancelled.")


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_remote_player(peer_id)


func _on_peer_left(peer_id: int) -> void:
	_remove_remote_player(peer_id)


func _remove_remote_player(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == CLIENT_PEER_ID:
		var player := _players.get_node_or_null(str(peer_id))
		if player != null:
			player.queue_free()
		_set_game_status(
			"Survivor 02 left · continuing solo · code %s" % _network_session.get_session_code(),
			STATUS_IDLE,
		)


func _on_session_state_changed(state: int, description: String) -> void:
	if _connection_progress.visible:
		_update_loading_from_session_state(state, description)
	elif _lobby.visible:
		_set_lobby_status(description, STATUS_ACTIVE)
	else:
		_set_game_status(description, STATUS_ACTIVE)


func _on_session_failed(description: String) -> void:
	if _loading_cancel_requested:
		_loading_cancel_requested = false
		_show_lobby_error("Connection cancelled.")
		_set_lobby_status("Cancelled. Choose Host or Join when ready.", STATUS_IDLE)
		return
	_show_lobby_error(description)


func _on_session_closed(_close_code: int, reason: String) -> void:
	if _loading_cancel_requested:
		_loading_cancel_requested = false
		_show_lobby_error("Connection cancelled.")
		_set_lobby_status("Cancelled. Choose Host or Join when ready.", STATUS_IDLE)
		return
	_show_lobby_error(reason if not reason.is_empty() else "Session closed.")


func _on_transport_diagnostic(message: String) -> void:
	_connection_detail.text = message


func _on_multiplayer_connection_failed() -> void:
	_show_lobby_error("Could not establish the direct WebRTC route.")


func _on_server_disconnected() -> void:
	_show_lobby_error("The host ended the session.")


func _spawn_player(data: Variant) -> Node:
	var peer_id := int(data)
	var player := PLAYER_SCENE.instantiate() as MultiplayerPowerPlayer
	if player == null:
		return Node.new()

	var spawn_position := HOST_SPAWN if peer_id == HOST_PEER_ID else CLIENT_SPAWN
	player.configure(peer_id, Transform3D(Basis.IDENTITY, spawn_position))
	player.bind_cube(_cube)
	return player


func _spawn_player_if_missing(peer_id: int) -> void:
	if _players.get_node_or_null(str(peer_id)) != null:
		return
	_player_spawner.spawn(peer_id)


func _begin_startup_preparation() -> void:
	var attempt_id := _begin_loading(
		1,
		2,
		"PREPARING NETWORK DEMO",
		"Loading the shared power chamber…",
		false,
	)
	_prepare_startup(attempt_id)


func _prepare_startup(attempt_id: int) -> void:
	# The headless validation path has no rendered frames to await.
	if DisplayServer.get_name() == "headless":
		_finish_startup_preparation(attempt_id)
		return

	# First present the lightweight 2D loading layer by itself. Only then expose
	# the real room to a camera, so Firefox never attributes the expensive first
	# WebGL frame to a later signaling status.
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	if OS.has_feature("web"):
		_set_loading_stage(
			2,
			2,
			"WARMING BROWSER GRAPHICS",
			"Preparing room lighting and materials. First launch can take a moment…",
		)
		await _present_loading_frame()
		if not _loading_attempt_is_current(attempt_id):
			return

		var prewarm_viewport := _create_web_prewarm_viewport()
		await _present_loading_frame()
		if not _loading_attempt_is_current(attempt_id):
			if is_instance_valid(prewarm_viewport):
				prewarm_viewport.queue_free()
			return
		prewarm_viewport.queue_free()

	_set_loading_stage(2, 2, "DEMO READY", "Choose Host or join with a session code.", true)
	await _present_loading_frame()
	if _loading_attempt_is_current(attempt_id):
		_finish_startup_preparation(attempt_id)


func _finish_startup_preparation(attempt_id: int) -> void:
	if not _loading_attempt_is_current(attempt_id):
		return
	_connection_progress.visible = false
	_lobby.visible = true
	_set_lobby_enabled(true)
	_set_lobby_status("Choose Host or enter a six-character code.", STATUS_IDLE)


func _prepare_host_entry(attempt_id: int) -> void:
	_set_loading_stage(
		2,
		4,
		"SESSION %s IS LIVE" % _network_session.get_session_code(),
		"Survivor 02 can now join with this code.",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	_set_loading_stage(
		3,
		4,
		"PREPARING POWER CHAMBER",
		"Starting the host-authoritative cube and survivor…",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	_cube.reset_authoritative_state()
	_cube.set_authoritative_simulation(true)
	_spawn_player_if_missing(HOST_PEER_ID)
	var local_player := _get_local_player()
	if local_player == null:
		_abort_loading_session("The host session opened, but the local survivor did not spawn.")
		return

	_enter_gameplay("Waiting for survivor 02 · code %s" % _network_session.get_session_code())
	_set_loading_stage(
		4,
		4,
		"WARMING SURVIVOR VIEW",
		"Preparing the camera and suit lighting behind this screen…",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	local_player.activate_local_camera()
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	_set_loading_stage(
		4,
		4,
		"POWER CHAMBER READY",
		"Your survivor is ready to enter.",
		true,
	)
	await _present_loading_frame()
	_finish_gameplay_preparation(attempt_id)


func _present_client_peer_route_stage(attempt_id: int) -> void:
	# Let CODE ACCEPTED become a real presented frame while WebRTC negotiation
	# continues independently in the networking layer.
	await _present_loading_frame()
	if (
		_loading_attempt_is_current(attempt_id)
		and _network_session.get_state() == NetworkSession.State.NEGOTIATING_WEBRTC
	):
		_set_loading_stage(
			3,
			5,
			"ESTABLISHING DIRECT PEER ROUTE",
			"Exchanging WebRTC connection details with the host…",
		)


func _prepare_client_entry(attempt_id: int) -> void:
	_set_loading_stage(
		3,
		5,
		"PEER ROUTE ESTABLISHED",
		"The direct WebRTC connection to the host is ready.",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	_set_loading_stage(
		4,
		5,
		"SPAWNING SURVIVOR",
		"Waiting for the host to add your survivor to the shared room…",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	var spawn_deadline_msec := Time.get_ticks_msec() + 10_000
	var local_player := _get_local_player()
	while local_player == null and Time.get_ticks_msec() < spawn_deadline_msec:
		await get_tree().process_frame
		if not _loading_attempt_is_current(attempt_id):
			return
		local_player = _get_local_player()

	if local_player == null:
		_abort_loading_session(
			"Connected to the host, but the local survivor did not finish spawning."
		)
		return

	_enter_gameplay("Joined host · shared power room ready")
	_set_loading_stage(
		5,
		5,
		"WARMING SURVIVOR VIEW",
		"Preparing the camera and suit lighting behind this screen…",
	)
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	local_player.activate_local_camera()
	await _present_loading_frame()
	if not _loading_attempt_is_current(attempt_id):
		return

	_set_loading_stage(5, 5, "SURVIVOR READY", "Your survivor is ready to enter.", true)
	await _present_loading_frame()
	_finish_gameplay_preparation(attempt_id)


func _finish_gameplay_preparation(attempt_id: int) -> void:
	if not _loading_attempt_is_current(attempt_id):
		return
	_connection_progress.visible = false
	_entry_preparation_running = false


func _begin_loading(
	stage: int,
	total_stages: int,
	title: String,
	detail: String,
	cancellable := true,
) -> int:
	_loading_attempt_id += 1
	_loading_started_at_msec = Time.get_ticks_msec()
	_entry_preparation_running = false
	_loading_cancel_requested = false
	_lobby.visible = false
	_connection_progress.visible = true
	_loading_session_code.visible = false
	_loading_cancel_button.visible = cancellable
	_loading_cancel_button.disabled = false
	_set_loading_stage(stage, total_stages, title, detail)
	return _loading_attempt_id


func _cancel_loading(attempt_id: int) -> void:
	if attempt_id != _loading_attempt_id:
		return
	_loading_attempt_id += 1
	_entry_preparation_running = false
	_loading_cancel_requested = false
	_connection_progress.visible = false


func _loading_attempt_is_current(attempt_id: int) -> bool:
	return is_inside_tree() and attempt_id == _loading_attempt_id and _connection_progress.visible


func _set_loading_stage(
	stage: int,
	total_stages: int,
	title: String,
	detail: String,
	complete := false,
) -> void:
	if not _connection_progress.visible:
		return
	_loading_phase.text = "STAGE %d OF %d" % [stage, total_stages]
	_loading_title.text = title
	_loading_detail.text = detail
	_loading_bar.value = (100.0 if complete else float(stage - 1) / float(total_stages) * 100.0)

	var elapsed_seconds := float(Time.get_ticks_msec() - _loading_started_at_msec) / 1000.0
	print("[multiplayer load +%.3fs] %s — %s" % [elapsed_seconds, title, detail])


func _show_loading_session_code(text: String) -> void:
	_loading_session_code.text = text
	_loading_session_code.visible = true


func _abort_loading_session(description: String) -> void:
	# Keep the failure screen visible, but prevent the abandoned entry coroutine
	# from activating a camera while the socket close is still in flight.
	_loading_attempt_id += 1
	_entry_preparation_running = false
	_loading_cancel_button.disabled = true
	_set_loading_stage(1, 1, "SESSION COULD NOT START", description)
	_network_session.close_session(description)


func _present_loading_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


func _create_web_prewarm_viewport() -> SubViewport:
	# A tiny viewport shares the real World3D, compiling the same WebGL material
	# variants without paying for a full browser-sized cold frame.
	var prewarm_viewport := SubViewport.new()
	prewarm_viewport.name = "WebPrewarmViewport"
	prewarm_viewport.size = Vector2i(64, 64)
	prewarm_viewport.world_3d = get_viewport().world_3d
	prewarm_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(prewarm_viewport)

	var camera := Camera3D.new()
	camera.name = "WebPrewarmCamera"
	camera.position = HOST_SPAWN + Vector3.UP * WEB_PREWARM_CAMERA_HEIGHT
	camera.fov = WEB_PREWARM_CAMERA_FOV
	camera.near = WEB_PREWARM_CAMERA_NEAR
	camera.far = WEB_PREWARM_CAMERA_FAR
	prewarm_viewport.add_child(camera)
	camera.current = true

	# Match the browser player's light category without paying for a shadow map
	# in this networking proof. The real suit uses the same Web-only profile.
	var lamp := SpotLight3D.new()
	lamp.name = "WebPrewarmLamp"
	lamp.position = Vector3(0.14, -0.12, 0.0)
	lamp.light_color = Color(1.0, 0.96, 0.89)
	lamp.light_energy = PowerKnobs.HELMET_LAMP_ENERGY
	lamp.shadow_enabled = false
	lamp.spot_range = PowerKnobs.HELMET_LAMP_RANGE
	lamp.spot_angle = 45.0
	lamp.spot_attenuation = 1.0
	lamp.spot_angle_attenuation = 0.75
	camera.add_child(lamp)
	return prewarm_viewport


func _apply_web_demo_render_profile() -> void:
	if not OS.has_feature("web"):
		return

	# Compatibility/WebGL compiles visual variants on their first visible frame.
	# Keep the fog-and-power look, but drop the two most disposable cold-start
	# costs for this networking proof: glow post-processing and shadow maps.
	if _world_environment.environment != null:
		_world_environment.environment.glow_enabled = false
	_cube.use_web_demo_render_profile()


func _update_loading_from_session_state(state: int, description: String) -> void:
	if state != NetworkSession.State.CONNECTING_SIGNALING:
		return
	if not description.begins_with("Signaling connected"):
		return

	var total_stages := 4 if _network_session.get_role() == NetworkSession.Role.HOST else 5
	_set_loading_stage(
		1,
		total_stages,
		"SIGNALING SERVICE REACHED",
		"Waiting for the session service to accept this request…",
	)


func _enter_gameplay(status: String) -> void:
	_lobby.visible = false
	_game_hud.visible = true
	_session_code.text = (
		"SESSION  %s%s"
		% [
			_network_session.get_session_code(),
			"  ·  HOST" if _network_session.get_role() == NetworkSession.Role.HOST else "",
		]
	)
	_set_game_status(status, STATUS_ACTIVE)
	if not _briefing_seen:
		_briefing_seen = true
		_show_briefing()


func _show_lobby_error(description: String) -> void:
	# Invalidate every deferred loading continuation before it can spawn a player
	# or hide the error screen from an earlier connection attempt.
	_loading_attempt_id += 1
	_entry_preparation_running = false
	_loading_cancel_requested = false
	_connection_progress.visible = false
	for child in _players.get_children():
		var player := child as MultiplayerPowerPlayer
		if player != null:
			player.release_local_control()
		child.queue_free()
	_cube.set_authoritative_simulation(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_game_hud.visible = false
	_briefing.visible = false
	_capture_prompt.visible = false
	_briefing_seen = false
	_lobby.visible = true
	_set_lobby_enabled(true)
	_set_lobby_status(description, STATUS_ERROR)


func _set_lobby_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled
	_endpoint_input.editable = enabled
	_session_code_input.editable = enabled


func _set_lobby_status(text: String, color: Color) -> void:
	_lobby_status.text = text
	_lobby_status.add_theme_color_override("font_color", color)


func _set_game_status(text: String, color: Color) -> void:
	_session_status.text = text
	_session_status.add_theme_color_override("font_color", color)


func _release_ui_focus() -> void:
	get_viewport().gui_release_focus()


func _show_briefing() -> void:
	var role_name := "HOST" if _network_session.get_role() == NetworkSession.Role.HOST else "JOINER"
	_briefing_session.text = "%s · SESSION %s" % [role_name, _network_session.get_session_code()]
	_briefing.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var local_player := _get_local_player()
	if local_player != null:
		local_player.release_local_control()


func _update_interaction_hud() -> void:
	if not _game_hud.visible:
		_capture_prompt.visible = false
		return

	var local_player := _get_local_player()
	if _briefing.visible:
		_briefing_begin_button.disabled = local_player == null
		_briefing_ready_status.text = (
			"Survivor ready. Enter when you are."
			if local_player != null
			else "Synchronizing your suit…"
		)
		_capture_prompt.visible = false
	else:
		_capture_prompt.visible = (
			local_player != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		)

	if local_player == null:
		_action_prompt.text = "SYNCING YOUR SUIT…"
	elif local_player.is_near_cube():
		_action_prompt.text = (
			"CRANKING SHARED POWER…"
			if Input.is_action_pressed("grab")
			else "HOLD F  ·  CRANK THE SHARED POWER CUBE"
		)
	else:
		_action_prompt.text = "FOLLOW THE BLUE TETHER  ·  REACH THE POWER CUBE"


func _get_local_player() -> MultiplayerPowerPlayer:
	return _players.get_node_or_null(str(multiplayer.get_unique_id())) as MultiplayerPowerPlayer
