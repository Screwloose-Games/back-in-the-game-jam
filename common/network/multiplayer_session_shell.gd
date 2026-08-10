class_name MultiplayerSessionShell
extends CanvasLayer

## Reusable host/join and connection-progress shell for multiplayer demos.
##
## This node owns no gameplay. It keeps NetworkSession alive while a demo owns
## spawning, authority, cameras, loading its world, and deciding when play begins.

signal attempt_started(attempt_id: int, role: int)
signal attempt_cancelled

const STATUS_IDLE := Color(0.95, 0.76, 0.38)
const STATUS_ACTIVE := Color(0.42, 1.0, 0.7)
const STATUS_ERROR := Color(1.0, 0.4, 0.48)

var _attempt_id := 0
var _session_code_text := ""
var _cancel_requested := false
var _showing_error := false

@onready var _network_session: NetworkSession = %NetworkSession
@onready var _lobby: Control = %Lobby
@onready var _progress: Control = %Progress
@onready var _brand_title: Label = %BrandTitle
@onready var _brand_subtitle: Label = %BrandSubtitle
@onready var _objective: Label = %Objective
@onready var _endpoint_input: LineEdit = %SignalingEndpointInput
@onready var _session_code_input: LineEdit = %SessionCodeInput
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _lobby_status: Label = %LobbyStatus
@onready var _transport_detail: Label = %TransportDetail
@onready var _loading_phase: Label = %LoadingPhase
@onready var _loading_title: Label = %LoadingTitle
@onready var _loading_code: Label = %LoadingCode
@onready var _loading_detail: Label = %LoadingDetail
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)

	_network_session.host_started.connect(_on_host_started)
	_network_session.state_changed.connect(_on_session_state_changed)
	_network_session.session_failed.connect(_on_session_failed)
	_network_session.session_closed.connect(_on_session_closed)
	_network_session.transport_diagnostic.connect(_on_transport_diagnostic)

	show_lobby("Choose Host or enter a six-character session code.")


func session() -> NetworkSession:
	return _network_session


func configure(title: String, subtitle: String, objective: String) -> void:
	_brand_title.text = title
	_brand_subtitle.text = subtitle
	_objective.text = objective


func begin_loading(
	stage: int,
	total: int,
	title: String,
	detail: String,
	can_cancel := true,
) -> int:
	_attempt_id += 1
	_cancel_requested = false
	_showing_error = false
	_session_code_text = ""
	_transport_detail.text = ""
	visible = true
	_lobby.visible = false
	_progress.visible = true
	_cancel_button.visible = can_cancel
	_cancel_button.disabled = false
	set_stage(stage, total, title, detail)
	return _attempt_id


func set_stage(
	stage: int,
	total: int,
	title: String,
	detail: String,
	complete := false,
) -> void:
	var safe_total := maxi(total, 1)
	var safe_stage := clampi(stage, 1, safe_total)
	_loading_phase.text = "STAGE %d OF %d" % [safe_stage, safe_total]
	_loading_title.text = title
	_loading_detail.text = detail
	_loading_code.text = _session_code_text
	_loading_code.visible = not _session_code_text.is_empty()
	_loading_bar.value = (100.0 if complete else float(safe_stage - 1) / float(safe_total) * 100.0)


func set_session_code(description: String) -> void:
	_session_code_text = description
	_loading_code.text = description
	_loading_code.visible = not description.is_empty()


func finish_loading(attempt_id: int) -> void:
	if not is_attempt_current(attempt_id):
		return
	_attempt_id += 1
	visible = false


func show_lobby(description: String, is_error := false) -> void:
	_showing_error = is_error
	visible = true
	_progress.visible = false
	_lobby.visible = true
	_set_lobby_enabled(true)
	_lobby_status.text = description
	_lobby_status.add_theme_color_override("font_color", STATUS_ERROR if is_error else STATUS_IDLE)
	if not is_error:
		_transport_detail.text = ""


func abort_attempt(description: String) -> void:
	_attempt_id += 1
	if _network_session.get_state() == NetworkSession.State.IDLE:
		show_lobby(description, true)
		return
	_cancel_button.disabled = true
	set_stage(1, 1, "SESSION COULD NOT START", description)
	_network_session.close_session(description)


func is_attempt_current(attempt_id: int) -> bool:
	return is_inside_tree() and attempt_id == _attempt_id and visible and _progress.visible


func current_attempt_id() -> int:
	return _attempt_id


func _on_host_pressed() -> void:
	_release_ui_focus()
	_set_lobby_enabled(false)
	var attempt_id := begin_loading(
		1,
		4,
		"CREATING SESSION",
		"Contacting the signaling service…",
	)
	var result: Error = _network_session.host(_endpoint_input.text)
	if result != OK:
		_attempt_id += 1
		show_lobby("Could not host. Error: %d" % result, true)
		return
	attempt_started.emit(attempt_id, NetworkSession.Role.HOST)


func _on_join_pressed() -> void:
	_release_ui_focus()
	var code := _session_code_input.text.strip_edges().to_upper()
	_session_code_input.text = code
	_set_lobby_enabled(false)
	var attempt_id := begin_loading(
		1,
		5,
		"FINDING SESSION %s" % code,
		"Contacting the signaling service…",
	)
	set_session_code("SESSION CODE  %s" % code)
	var result: Error = _network_session.join(_endpoint_input.text, code)
	if result != OK:
		_attempt_id += 1
		show_lobby("Could not join. Check the six-character code.", true)
		return
	attempt_started.emit(attempt_id, NetworkSession.Role.CLIENT)


func _on_cancel_pressed() -> void:
	if _network_session.get_state() == NetworkSession.State.IDLE:
		_attempt_id += 1
		attempt_cancelled.emit()
		show_lobby("Cancelled. Choose Host or Join when ready.")
		return
	_attempt_id += 1
	_cancel_requested = true
	_cancel_button.disabled = true
	set_stage(1, 1, "CLOSING SESSION", "Returning to the multiplayer lobby…")
	attempt_cancelled.emit()
	_network_session.close_session("Connection cancelled.")


func _on_host_started(code: String) -> void:
	_session_code_input.text = code
	set_session_code("JOIN CODE  %s" % code)
	set_stage(
		1,
		4,
		"RESERVING PRIVATE SESSION",
		"Opening the private session on the signaling service…",
	)


func _on_session_state_changed(state: int, description: String) -> void:
	if state == NetworkSession.State.IDLE and _lobby.visible and _showing_error:
		return
	if _progress.visible:
		_loading_detail.text = description
	elif _lobby.visible:
		_lobby_status.text = description
		_lobby_status.add_theme_color_override("font_color", STATUS_ACTIVE)


func _on_session_failed(description: String) -> void:
	_attempt_id += 1
	if _cancel_requested:
		_cancel_requested = false
		show_lobby("Cancelled. Choose Host or Join when ready.")
		return
	show_lobby(description, true)


func _on_session_closed(_close_code: int, reason: String) -> void:
	_attempt_id += 1
	if _cancel_requested:
		_cancel_requested = false
		show_lobby("Cancelled. Choose Host or Join when ready.")
		return
	show_lobby(reason if not reason.is_empty() else "Session closed.", true)


func _on_transport_diagnostic(message: String) -> void:
	_transport_detail.text = message


func _set_lobby_enabled(enabled: bool) -> void:
	_endpoint_input.editable = enabled
	_session_code_input.editable = enabled
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled


func _release_ui_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
