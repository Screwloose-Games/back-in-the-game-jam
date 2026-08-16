extends Node

## Game-level entry state around the reusable NetworkSession transport.
##
## Menus queue an intent, but no socket opens until the gameplay scene calls
## begin_queued_entry(). This guarantees both peers have matching multiplayer
## node paths before Godot begins spawn replication.

signal entry_status_changed(description: String, progress: float)
signal entry_ready
signal entry_failed(description: String)
signal host_code_ready(code: String)
signal multiplayer_peer_ready(peer: WebRTCMultiplayerPeer)
signal peer_left(peer_id: int)
signal session_ended(description: String)
signal voice_channel_opened(peer_id: int)
signal voice_channel_closed(peer_id: int)
signal voice_packet_received(payload: PackedByteArray)

enum EntryMode {
	SOLO,
	HOST,
	CLIENT,
}

const DEFAULT_SIGNALING_URL := "wss://signaling.screwloose.workers.dev"
const SESSION_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SESSION_CODE_LENGTH := 6

var _entry_mode := EntryMode.SOLO
var _requested_code := ""
var _last_error := ""
var _entry_started := false
var _deliberate_leave := false
var _start_after_cleanup := false
var _entry_ready_emitted := false
var _network_session: NetworkSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_network_session = NetworkSession.new()
	_network_session.name = "NetworkSession"
	_network_session.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_network_session)

	_network_session.state_changed.connect(_on_network_state_changed)
	_network_session.multiplayer_peer_ready.connect(multiplayer_peer_ready.emit)
	_network_session.session_failed.connect(_on_session_failed)
	_network_session.session_closed.connect(_on_session_closed)
	_network_session.peer_left.connect(peer_left.emit)
	_network_session.voice_channel_opened.connect(voice_channel_opened.emit)
	_network_session.voice_channel_closed.connect(voice_channel_closed.emit)
	_network_session.voice_packet_received.connect(voice_packet_received.emit)


func queue_solo() -> void:
	_entry_mode = EntryMode.SOLO
	_requested_code = ""
	_last_error = ""
	_entry_started = false
	_start_after_cleanup = false
	_entry_ready_emitted = false


func queue_host() -> void:
	_entry_mode = EntryMode.HOST
	_requested_code = ""
	_last_error = ""
	_entry_started = false
	_start_after_cleanup = false
	_entry_ready_emitted = false


func queue_join(code: String) -> Error:
	var normalized_code := code.strip_edges().to_upper()
	if not _is_valid_session_code(normalized_code):
		return ERR_INVALID_PARAMETER

	_entry_mode = EntryMode.CLIENT
	_requested_code = normalized_code
	_last_error = ""
	_entry_started = false
	_start_after_cleanup = false
	_entry_ready_emitted = false
	return OK


## Starts the queued mode after the gameplay scene and spawner are ready.
func begin_queued_entry() -> Error:
	if _entry_started:
		return ERR_ALREADY_IN_USE
	_entry_started = true

	match _entry_mode:
		EntryMode.SOLO:
			entry_status_changed.emit("Starting solo descent", 1.0)
			_emit_entry_ready_once()
			return OK
		EntryMode.HOST:
			entry_status_changed.emit("Creating private session", 0.15)
			return _begin_online_entry()
		EntryMode.CLIENT:
			entry_status_changed.emit("Finding session %s" % _requested_code, 0.15)
			return _begin_online_entry()
	return ERR_BUG


func leave(reason := "Player left the session.") -> void:
	_deliberate_leave = true
	_entry_started = false
	_start_after_cleanup = false
	if _network_session.get_state() != NetworkSession.State.IDLE:
		_network_session.close_session(reason)
	else:
		_deliberate_leave = false
	_entry_mode = EntryMode.SOLO
	_requested_code = ""


func mode() -> EntryMode:
	return _entry_mode


func is_online() -> bool:
	return _entry_mode != EntryMode.SOLO


func is_host() -> bool:
	return _entry_mode == EntryMode.HOST


func session_code() -> String:
	if _network_session.get_session_code().is_empty():
		return _requested_code
	return _network_session.get_session_code()


func consume_last_error() -> String:
	var result := _last_error
	_last_error = ""
	return result


func network_session() -> NetworkSession:
	return _network_session


func send_voice_packet(payload: PackedByteArray) -> Error:
	if _network_session == null:
		return ERR_UNCONFIGURED
	return _network_session.send_voice_packet(payload)


func _start_network_request(result: Error) -> Error:
	if result == OK:
		return OK
	_entry_started = false
	var description := "Could not start the online session. Error: %d" % result
	_last_error = description
	entry_failed.emit(description)
	return result


func _begin_online_entry() -> Error:
	if _network_session.get_state() == NetworkSession.State.IDLE:
		_deliberate_leave = false
		return _start_queued_network_request()

	# WebSocket close is asynchronous. A fast menu retry waits on the existing
	# transport instead of failing ERR_ALREADY_IN_USE or mistaking its eventual
	# close callback for the newly queued game.
	_start_after_cleanup = true
	_deliberate_leave = true
	entry_status_changed.emit("Finishing previous online session", 0.05)
	if _network_session.get_state() != NetworkSession.State.CLOSING:
		_network_session.close_session("Starting a new online session.")
	return OK


func _start_queued_network_request() -> Error:
	if _entry_mode == EntryMode.HOST:
		return _start_network_request(_network_session.host(DEFAULT_SIGNALING_URL))
	if _entry_mode == EntryMode.CLIENT:
		return _start_network_request(_network_session.join(DEFAULT_SIGNALING_URL, _requested_code))
	return ERR_INVALID_DATA


func _resume_entry_after_cleanup() -> void:
	if not _start_after_cleanup or not _entry_started or not is_online():
		return
	_start_after_cleanup = false
	_deliberate_leave = false
	_start_queued_network_request()


func _emit_entry_ready_once() -> void:
	if _entry_ready_emitted:
		return
	_entry_ready_emitted = true
	entry_ready.emit()


func _on_network_state_changed(new_state: int, description: String) -> void:
	var progress := _progress_for_state(new_state)
	entry_status_changed.emit(description, progress)
	if new_state == NetworkSession.State.IDLE and _start_after_cleanup:
		call_deferred("_resume_entry_after_cleanup")

	if _entry_mode == EntryMode.HOST and new_state == NetworkSession.State.WAITING_FOR_PEER:
		host_code_ready.emit(_network_session.get_session_code())
		_emit_entry_ready_once()
	elif _entry_mode == EntryMode.CLIENT and new_state == NetworkSession.State.CONNECTED:
		_emit_entry_ready_once()


func _on_session_failed(description: String) -> void:
	_entry_started = false
	_last_error = description
	entry_failed.emit(description)


func _on_session_closed(_close_code: int, reason: String) -> void:
	_entry_started = false
	if _start_after_cleanup:
		# IDLE state schedules the replacement entry. Do not let this old close
		# callback alter the new attempt's mode or error UI in the meantime.
		_entry_started = true
		return
	if _deliberate_leave:
		_deliberate_leave = false
		return
	_last_error = reason
	session_ended.emit(reason)


func _progress_for_state(network_state: int) -> float:
	var progress := 0.0
	match network_state:
		NetworkSession.State.IDLE:
			progress = 0.0
		NetworkSession.State.CONNECTING_SIGNALING:
			progress = 0.35
		NetworkSession.State.WAITING_FOR_PEER:
			progress = 1.0
		NetworkSession.State.NEGOTIATING_WEBRTC:
			progress = 0.7
		NetworkSession.State.CONNECTED:
			progress = 1.0
		NetworkSession.State.CLOSING:
			progress = 0.9
		NetworkSession.State.FAILED:
			progress = 1.0
	return progress


func _is_valid_session_code(code: String) -> bool:
	if code.length() != SESSION_CODE_LENGTH:
		return false
	for index in code.length():
		if not SESSION_CODE_ALPHABET.contains(code.substr(index, 1)):
			return false
	return true
