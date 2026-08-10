extends Control

# The smoke scene explicitly loads the reusable session module. This avoids
# depending on Godot's global-class cache while these prototype files change
# frequently.
const NetworkSessionScript := preload("res://common/network/network_session.gd")

## Temporary UI controller for the network smoke-test scene.
##
## This script is intentionally disposable. It presents NetworkSession events
## in a small visual harness, but contains no reusable networking behavior.

# This test UI is intentionally text-heavy. Set only its running window to a
# readable size instead of changing the project's normal game-window settings.
const SMOKE_TEST_WINDOW_SIZE := Vector2i(2560, 1440)

const STATUS_IDLE := Color(0.95, 0.76, 0.38, 1.0)
const STATUS_ACTIVE := Color(0.36, 0.94, 0.68, 1.0)
const STATUS_ERROR := Color(1.0, 0.46, 0.5, 1.0)

# Everything below this line is intentionally disposable smoke-test behavior.
# These are logical cells, not world coordinates from the real game.
const GRID_COLUMNS := 8
const GRID_ROWS := 6
const GRID_MARGIN := 42.0

var _network_session
var _host_grid_position := Vector2i(1, 1)
var _client_grid_position := Vector2i(6, 4)

@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _signaling_endpoint_input: LineEdit = %SignalingEndpointInput
@onready var _session_code_input: LineEdit = %SessionCodeInput
@onready var _connection_state: Label = %ConnectionState
@onready var _protocol_log: TextEdit = %ProtocolLog
@onready var _host_dot: Panel = %HostDot
@onready var _client_dot: Panel = %ClientDot
@onready var _open_slot_dot: Panel = %OpenSlotDot
@onready var _map: Panel = %Map
@onready var _move_up_button: Button = %MoveUpButton
@onready var _move_left_button: Button = %MoveLeftButton
@onready var _move_down_button: Button = %MoveDownButton
@onready var _move_right_button: Button = %MoveRightButton


func _ready() -> void:
	# A browser owns its canvas size. Forcing a native window size there can
	# visually scale the UI away from its pointer hit-testing coordinates.
	if not OS.has_feature("web"):
		get_window().size = SMOKE_TEST_WINDOW_SIZE

	# The generic coordinator is a child so Godot calls its _process() and the
	# SignalingClient beneath it can continuously poll its WebSocketPeer.
	_network_session = NetworkSessionScript.new()
	add_child(_network_session)

	_network_session.state_changed.connect(_on_session_state_changed)
	_network_session.host_started.connect(_on_host_started)
	_network_session.peer_available.connect(_on_peer_available)
	_network_session.direct_connection_opened.connect(_on_direct_connection_opened)
	_network_session.transport_diagnostic.connect(_on_transport_diagnostic)
	_network_session.signaling_message_received.connect(_on_signaling_message_received)
	_network_session.session_failed.connect(_on_session_failed)
	_network_session.session_closed.connect(_on_session_closed)

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_move_up_button.pressed.connect(_on_move_button_pressed.bind(Vector2i.UP))
	_move_left_button.pressed.connect(_on_move_button_pressed.bind(Vector2i.LEFT))
	_move_down_button.pressed.connect(_on_move_button_pressed.bind(Vector2i.DOWN))
	_move_right_button.pressed.connect(_on_move_button_pressed.bind(Vector2i.RIGHT))
	_map.focus_mode = Control.FOCUS_ALL
	_map.gui_input.connect(_on_map_gui_input)
	_map.resized.connect(_render_grid)

	_show_idle_state()
	call_deferred("_render_grid")
	_append_log("Smoke test ready. No network connection has been attempted yet.")


func _on_host_pressed() -> void:
	# Prevent the endpoint field from continuing to consume movement keys after
	# the player has clicked Host.
	get_viewport().gui_release_focus()
	var result: Error = _network_session.host(_signaling_endpoint_input.text)

	if result != OK:
		_set_status("Could not start hosting. Error: %d" % result, STATUS_ERROR)
		_append_log("Host request was rejected before connecting.")


func _on_join_pressed() -> void:
	# Same for the join-code field after the player commits it.
	get_viewport().gui_release_focus()
	var session_code := _session_code_input.text.strip_edges().to_upper()
	_session_code_input.text = session_code

	var result: Error = (
		_network_session
		. join(
			_signaling_endpoint_input.text,
			session_code,
		)
	)

	if result != OK:
		_set_status("Could not join that session. Error: %d" % result, STATUS_ERROR)
		_append_log("Join request was rejected before connecting.")


func _on_host_started(session_code: String) -> void:
	# The generated code is ready before the host socket opens, which lets a
	# real future menu display/copy it immediately.
	_session_code_input.text = session_code
	_host_dot.visible = true
	_client_dot.visible = false
	_open_slot_dot.visible = true

	_append_log("Hosting requested. Session code: %s" % session_code)


func _on_session_state_changed(new_state: int, description: String) -> void:
	var state_color := STATUS_ACTIVE

	if new_state == NetworkSessionScript.State.IDLE:
		state_color = STATUS_IDLE
	elif new_state == NetworkSessionScript.State.FAILED:
		state_color = STATUS_ERROR

	_set_status(description, state_color)
	_append_log("Session state: %s" % description)


func _on_peer_available() -> void:
	# Both players are visible while the direct connection negotiates.
	_host_dot.visible = true
	_client_dot.visible = true
	_open_slot_dot.visible = false

	_append_log("Both session roles are present; WebRTC negotiation began.")


func _on_direct_connection_opened() -> void:
	_append_log("Godot high-level multiplayer route opened.")

	# Only the host owns the initial shared snapshot.
	if _network_session.get_role() == NetworkSessionScript.Role.HOST:
		_broadcast_authoritative_snapshot()


func _on_transport_diagnostic(message: String) -> void:
	_append_log("WebRTC: %s" % message)


func _input(event: InputEvent) -> void:
	# Do not steal typing keys while someone is entering an endpoint or code.
	if _signaling_endpoint_input.has_focus() or _session_code_input.has_focus():
		return

	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return

	if not _can_submit_move():
		return

	var key_event := event as InputEventKey
	var direction := _direction_for_key(key_event.keycode)

	if direction == Vector2i.ZERO:
		return

	get_viewport().set_input_as_handled()
	_submit_local_move(direction)


func _on_map_gui_input(event: InputEvent) -> void:
	# Make keyboard control explicit instead of relying on a hidden canvas focus.
	if event is InputEventMouseButton and event.is_pressed():
		get_viewport().gui_release_focus()
		_map.grab_focus()


func _on_move_button_pressed(direction: Vector2i) -> void:
	# Visible buttons make this transport test usable even without keyboard focus.
	if _can_submit_move():
		_submit_local_move(direction)


func _can_submit_move() -> bool:
	var session_state: int = _network_session.get_state()
	var host_waiting_for_peer: bool = (
		_network_session.get_role() == NetworkSessionScript.Role.HOST
		and session_state == NetworkSessionScript.State.WAITING_FOR_PEER
	)

	return session_state == NetworkSessionScript.State.CONNECTED or host_waiting_for_peer


func _submit_local_move(direction: Vector2i) -> void:
	if _network_session.get_role() == NetworkSessionScript.Role.HOST:
		# The host can immediately simulate its own input.
		_host_grid_position = _move_on_grid(_host_grid_position, direction)
		_broadcast_authoritative_snapshot()
		return

	# A client sends intent only. It never sends a claimed world position.
	_request_client_move.rpc_id(WebRTCSession.HOST_PEER_ID, direction)


@rpc("any_peer", "call_remote", "reliable")
func _request_client_move(direction: Vector2i) -> void:
	# Only the host is allowed to turn a client intent into state.
	if (
		_network_session.get_role() != NetworkSessionScript.Role.HOST
		or multiplayer.get_remote_sender_id() != WebRTCSession.CLIENT_PEER_ID
	):
		_append_log("Ignored move intent on non-host client.")
		return

	# Accept only one-cell cardinal movement from the client.
	if abs(direction.x) + abs(direction.y) != 1:
		_append_log("Ignored invalid client move intent.")
		return

	_client_grid_position = _move_on_grid(_client_grid_position, direction)
	_broadcast_authoritative_snapshot()


func _broadcast_authoritative_snapshot() -> void:
	# This function is host-only by design.
	if _network_session.get_role() != NetworkSessionScript.Role.HOST:
		return

	_render_grid()

	# The host plays normally while solo. There is nothing to send until a
	# direct peer connection exists, at which point the current state is shared.
	if _network_session.get_state() != NetworkSessionScript.State.CONNECTED:
		return

	(
		_receive_authoritative_snapshot
		. rpc(
			_host_grid_position,
			_client_grid_position,
		)
	)


@rpc("authority", "call_remote", "reliable")
func _receive_authoritative_snapshot(
	host_position: Vector2i,
	client_position: Vector2i,
) -> void:
	_host_grid_position = host_position
	_client_grid_position = client_position
	_render_grid()


func _direction_for_key(keycode: Key) -> Vector2i:
	match keycode:
		KEY_W, KEY_UP:
			return Vector2i.UP
		KEY_S, KEY_DOWN:
			return Vector2i.DOWN
		KEY_A, KEY_LEFT:
			return Vector2i.LEFT
		KEY_D, KEY_RIGHT:
			return Vector2i.RIGHT
		_:
			return Vector2i.ZERO


func _move_on_grid(pos: Vector2i, direction: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(pos.x + direction.x, 0, GRID_COLUMNS - 1),
		clampi(pos.y + direction.y, 0, GRID_ROWS - 1),
	)


func _render_grid() -> void:
	if _map.size.x <= GRID_MARGIN * 2.0 or _map.size.y <= GRID_MARGIN * 2.0:
		return

	_host_dot.position = _grid_position_to_map_position(_host_grid_position, _host_dot)
	_client_dot.position = _grid_position_to_map_position(_client_grid_position, _client_dot)


func _grid_position_to_map_position(grid_position: Vector2i, dot: Panel) -> Vector2:
	var usable_size := _map.size - Vector2(GRID_MARGIN * 2.0, GRID_MARGIN * 2.0)
	var cell_spacing := usable_size / Vector2(GRID_COLUMNS - 1, GRID_ROWS - 1)
	var cell_origin := Vector2(GRID_MARGIN, GRID_MARGIN)

	return cell_origin + Vector2(grid_position) * cell_spacing - dot.size * 0.5


func _on_signaling_message_received(message: Dictionary) -> void:
	# Keep raw protocol events visible. This is especially useful while testing
	# a browser export against the deployed Worker later.
	_append_log("Signaling message: %s" % str(message.get("type", "unknown")))


func _on_session_failed(description: String) -> void:
	_set_status(description, STATUS_ERROR)
	_append_log("Session failed: %s" % description)


func _on_session_closed(close_code: int, reason: String) -> void:
	_append_log("Session closed. Code: %d. Reason: %s" % [close_code, reason])


func _show_idle_state() -> void:
	_set_status("Idle — choose Host or Join", STATUS_IDLE)

	# An idle instance represents no player in any session yet.
	_host_dot.visible = false
	_client_dot.visible = false
	_open_slot_dot.visible = true


func _set_status(text: String, color: Color) -> void:
	_connection_state.text = text
	_connection_state.add_theme_color_override("font_color", color)


func _append_log(message: String) -> void:
	# TextEdit owns scrolling and selection. Keeping all formatting here makes
	# later protocol events easy to inspect without a separate logging system.
	if not _protocol_log.text.is_empty():
		_protocol_log.text += "\n"
	_protocol_log.text += message
	_protocol_log.scroll_vertical = _protocol_log.get_line_count()
