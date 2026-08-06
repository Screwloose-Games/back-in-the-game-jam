class_name NetworkSession
extends Node
## Reusable host/join session coordinator.
##
## This layer owns session lifecycle. It delegates raw WebSocket work to
## SignalingClient, and will later delegate WebRTC negotiation to WebRTCSession.

signal state_changed(new_state: int, description: String)
signal host_started(session_code: String)
signal peer_available
signal signaling_message_received(message: Dictionary)
signal session_failed(description: String)
signal session_closed(close_code: int, reason: String)
# The game layer will eventually begin state/input exchange after this.
signal direct_connection_opened
# Application bytes received from the one remote peer. Their schema belongs to
# the game layer, never the Worker or this session lifecycle coordinator.
signal game_packet_received(packet: PackedByteArray)
# Read-only WebRTC lifecycle detail for development UI and diagnostics.
signal transport_diagnostic(message: String)

# The MVP currently supports one host and one client.
enum Role {
	NONE,
	HOST,
	CLIENT,
}

# These state names map directly to useful player-facing UI stages.
enum State {
	IDLE,
	CONNECTING_SIGNALING,
	WAITING_FOR_PEER,
	NEGOTIATING_WEBRTC,
	CONNECTED,
	CLOSING,
	FAILED,
}

# Same unambiguous alphabet enforced by the signaling server.
const SESSION_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SESSION_CODE_LENGTH := 6
const WEBRTC_SESSION_SCRIPT := preload("res://common/network/webrtc_session.gd")
var _signaling_client: SignalingClient
# One direct connection exists for a two-player session.
var _webrtc_session
var _random := RandomNumberGenerator.new()

var _state := State.IDLE
var _role := Role.NONE
var _session_code := ""


func _ready() -> void:
	# Each NetworkSession owns one signaling connection at a time.
	_signaling_client = SignalingClient.new()
	add_child(_signaling_client)

	# Translate lower-level socket events into session-level events.
	_signaling_client.connection_opened.connect(_on_signaling_connection_opened)
	_signaling_client.message_received.connect(_on_signaling_message_received)
	_signaling_client.connection_closed.connect(_on_signaling_connection_closed)
	_signaling_client.connection_failed.connect(_on_signaling_connection_failed)
	_signaling_client.protocol_error.connect(_on_signaling_protocol_error)

	# Host codes should not be predictable across runs.
	_random.randomize()


func host(signaling_base_url: String) -> Error:
	if _state != State.IDLE:
		return ERR_ALREADY_IN_USE

	_session_code = _generate_session_code()
	_role = Role.HOST

	# The UI can display the code immediately, while the socket connects
	host_started.emit(_session_code)

	return _connect_to_signaling(signaling_base_url)


func join(signaling_base_url: String, requested_session_code: String) -> Error:
	if _state != State.IDLE:
		return ERR_ALREADY_IN_USE

	var normalized_code := requested_session_code.strip_edges().to_upper()

	if not _is_valid_session_code(normalized_code):
		return ERR_INVALID_PARAMETER

	_session_code = normalized_code
	_role = Role.CLIENT

	return _connect_to_signaling(signaling_base_url)


func send_signaling_message(message_type: StringName, payload: Dictionary) -> Error:
	# Used only for WebRTC offer/answer/ICE messages.
	return _signaling_client.send_relay_message(message_type, payload)


func send_game_packet(packet: PackedByteArray) -> Error:
	# Gameplay traffic has no route through the signaling Worker.
	if _webrtc_session == null or _state != State.CONNECTED:
		return ERR_UNAVAILABLE

	return _webrtc_session.send_packet(packet)


func close_session(reason := "Player left the session.") -> void:
	if _state == State.IDLE:
		return

	_set_state(State.CLOSING, "Closing session")
	_dispose_webrtc_session()
	_signaling_client.close_connection(reason)


func get_state() -> int:
	return _state


func get_role() -> int:
	return _role


func get_session_code() -> String:
	return _session_code


func _connect_to_signaling(signaling_base_url: String) -> Error:
	_set_state(State.CONNECTING_SIGNALING, "Connecting to signaling service")

	var signaling_role := (
		SignalingClient.Role.HOST if _role == Role.HOST else SignalingClient.Role.CLIENT
	)

	var result := (
		_signaling_client
		. connect_to_session(
			signaling_base_url,
			_session_code,
			signaling_role,
		)
	)

	if result != OK:
		_fail("Could not begin the signaling connection. Error: %d" % result)

	return result


func _on_signaling_connection_opened(_session_url: String) -> void:
	# The signaling server will next send host_connected or client_connected
	_set_state(State.CONNECTING_SIGNALING, "Signaling connected; waiting for session response")


func _on_signaling_message_received(message: Dictionary) -> void:
	# Keep this public signal for UI logging and future diagnostics.
	signaling_message_received.emit(message)

	var message_type := String(message.get("type", ""))

	match message_type:
		"host_connected":
			_set_state(
				State.WAITING_FOR_PEER,
				"Session %s is live; waiting for a second player" % _session_code,
			)
		"client_connected":
			_set_state(
				State.NEGOTIATING_WEBRTC,
				"Joined session; establishing direct peer route",
			)
			peer_available.emit()
			_start_webrtc()
		"client_joined":
			_set_state(
				State.NEGOTIATING_WEBRTC,
				"Second player joined; establishing direct peer route",
			)
			peer_available.emit()
			_start_webrtc()
		"offer", "answer", "ice_candidate":
			_forward_relay_message_to_webrtc(message)
		"signal_rejected":
			_fail(str(message.get("reason", "The signaling service rejected a message.")))


func _forward_relay_message_to_webrtc(message: Dictionary) -> void:
	if _webrtc_session == null:
		_fail("Received WebRTC signaling before direct connection setup.")
		return

	_webrtc_session.handle_signaling_message(message)


func _on_webrtc_relay_message_ready(message_type: StringName, payload: Dictionary) -> void:
	# This is SDP or ICE routing data—not gameplay state.
	var result: Error = send_signaling_message(message_type, payload)

	if result != OK:
		_fail("Could not relay WebRTC signaling. Error: %d" % result)


func _on_webrtc_connection_opened() -> void:
	_set_state(State.CONNECTED, "Direct peer route established")
	direct_connection_opened.emit()


func _on_webrtc_connection_failed(description: String) -> void:
	if _state != State.FAILED:
		_fail(description)


func _on_webrtc_packet_received(packet: PackedByteArray) -> void:
	# Forward opaque game traffic without inspecting or modifying it.
	game_packet_received.emit(packet)


func _on_webrtc_diagnostic(message: String) -> void:
	transport_diagnostic.emit(message)


func _dispose_webrtc_session() -> void:
	if _webrtc_session == null:
		return

	_webrtc_session.close_connection()
	_webrtc_session.queue_free()
	_webrtc_session = null


func _start_webrtc() -> void:
	# Both peers receive a lifecycle message before any offer is relayed.
	if _webrtc_session != null:
		transport_diagnostic.emit("WebRTC start was skipped because a peer already exists.")
		return

	transport_diagnostic.emit("Creating the local WebRTC peer.")
	_webrtc_session = WEBRTC_SESSION_SCRIPT.new()
	if _webrtc_session == null:
		_fail("Could not instantiate the WebRTC session implementation in this export.")
		return

	add_child(_webrtc_session)

	# WebRTC emits data that must travel through the existing Worker relay.
	_webrtc_session.relay_message_ready.connect(_on_webrtc_relay_message_ready)
	_webrtc_session.connection_opened.connect(_on_webrtc_connection_opened)
	_webrtc_session.connection_failed.connect(_on_webrtc_connection_failed)
	_webrtc_session.packet_received.connect(_on_webrtc_packet_received)
	_webrtc_session.diagnostic.connect(_on_webrtc_diagnostic)

	# Empty ICE servers are enough for our initial same-machine browser test.
	# STUN configuration comes in the following batch.
	var ice_servers: Array[Dictionary] = []
	var result: Error = OK

	if _role == Role.HOST:
		result = _webrtc_session.start_as_host(ice_servers)
	else:
		result = _webrtc_session.start_as_client(ice_servers)

	if result != OK and _state != State.FAILED:
		_fail("Could not start WebRTC. Error: %d" % result)
	elif result == OK:
		transport_diagnostic.emit("WebRTC start call returned OK.")


func _on_signaling_connection_closed(close_code: int, reason: String) -> void:
	_reset_to_idle()
	session_closed.emit(close_code, reason)


func _on_signaling_connection_failed(description: String) -> void:
	_fail(description)


func _on_signaling_protocol_error(description: String) -> void:
	_fail(description)


func _set_state(new_state: State, description: String) -> void:
	_state = new_state
	state_changed.emit(_state, description)


func _fail(description: String) -> void:
	_dispose_webrtc_session()
	_state = State.FAILED
	state_changed.emit(_state, description)
	session_failed.emit(description)


func _reset_to_idle() -> void:
	_dispose_webrtc_session()
	_state = State.IDLE
	_role = Role.NONE
	_session_code = ""

	state_changed.emit(_state, "Idle: choose Host or Join")


func _generate_session_code() -> String:
	var generated_code := ""

	for index in SESSION_CODE_LENGTH:
		var alphabet_index := (
			_random
			. randi_range(
				0,
				SESSION_CODE_ALPHABET.length() - 1,
			)
		)
		generated_code += SESSION_CODE_ALPHABET.substr(alphabet_index, 1)

	return generated_code


func _is_valid_session_code(session_code: String) -> bool:
	if session_code.length() != SESSION_CODE_LENGTH:
		return false

	for index in session_code.length():
		var character := session_code.substr(index, 1)

		if not SESSION_CODE_ALPHABET.contains(character):
			return false

	return true
