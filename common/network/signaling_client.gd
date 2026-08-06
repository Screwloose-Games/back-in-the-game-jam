class_name SignalingClient
extends Node
## Reusable WebSocket client for our Cloudflare signaling protocol.
##
## This node does not know about players, scenes, UI, or WebRTC internals.
## It only:
## - opens a WSS/WS socket for a host or joiner;
## - sends the three allowed WebRTC signaling message categories;
## - converts incoming JSON text into dictionaries and emits signals.

signal connection_opened(session_url: String)
signal message_received(message: Dictionary)
signal connection_closed(close_code: int, reason: String)
signal connection_failed(description: String)
signal protocol_error(description: String)

enum Role {
	HOST,
	CLIENT,
}

# The signaling Worker permits only these message categories to be relayed.
# Game inputs and state snapshots must never use this connection.
const RELAY_MESSAGE_TYPES := [&"offer", &"answer", &"ice_candidate"]

# WebSocketPeer is a low-level connection object, not a scene node.
var _socket: WebSocketPeer

# We need this flag because STATE_CLOSED can mean either:
# - connection failed before opening; or
# - a previously connected socket closed normally.
var _has_opened := false

# Retained for diagnostics and emitted when the connection opens.
var _session_url := ""


func _ready() -> void:
	# There is nothing to poll until connect_to_session() succeeds.
	set_process(false)


func connect_to_session(
	base_url: String,
	session_code: String,
	role: Role,
) -> Error:
	# Avoid silently abandoning a live or closing session.
	if _socket != null:
		return ERR_ALREADY_IN_USE

	var normalized_base_url := base_url.strip_edges().trim_suffix("/")
	var normalized_code := session_code.strip_edges().to_upper()

	# Local validation gives the UI a useful immediate error before a request
	# reaches the signaling server.
	if not (normalized_base_url.begins_with("ws://") or normalized_base_url.begins_with("wss://")):
		return ERR_INVALID_PARAMETER

	if normalized_code.length() != 6:
		return ERR_INVALID_PARAMETER

	# THe route matches the signaling server endpoints
	var role_path := "host" if role == Role.HOST else "join"
	_session_url = (
		"%s/sessions/%s/%s"
		% [
			normalized_base_url,
			normalized_code,
			role_path,
		]
	)
	_socket = WebSocketPeer.new()
	_has_opened = false

	# This starts a non-blocking connection at attempt. It returning OK means only
	# that Godot accepted the reqeust
	var result := _socket.connect_to_url(_session_url)
	if result != OK:
		_socket = null
		_session_url = ""
		return result

	set_process(true)
	return OK


func send_relay_message(message_type: StringName, payload: Dictionary) -> Error:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE

	# keep gameplay traffic out of the signaling server by accidental caller misuse
	if message_type not in RELAY_MESSAGE_TYPES:
		return ERR_INVALID_PARAMETER

	# This matches the signaling server shape
	var json_text := (
		JSON
		. stringify(
			{
				"type": message_type,
				"payload": payload,
			},
		)
	)

	# send_text() explicitly produces a WebSocket text frame, which is what our
	# JSON signaling protocol expects.
	return _socket.send_text(json_text)


func close_connection(reason := "Client requested disconnect.") -> void:
	if _socket == null:
		return

	# Closing is asynchronous. Keep _process() active until the socket reaches
	# STATE_CLOSED so the WebSocket close handshake can complete cleanly.
	_socket.close(1000, reason)


func is_open() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(_delta: float) -> void:
	if _socket == null:
		set_process(false)
		return

	# WebSocketPeer performs all netowrk I/O only when polled regularly
	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _has_opened:
				_has_opened = true
				connection_opened.emit(_session_url)
			_read_incoming_messages()
		WebSocketPeer.STATE_CLOSING:
			# Keep polling. Closing needs no extra action from us yet.
			pass
		WebSocketPeer.STATE_CLOSED:
			_report_closed_socket()


func _read_incoming_messages() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet = _socket.get_packet()

		# The signaling server protocol is JSON text only. Do not attempt to
		# interpret a binary frame as a gameplay packet or arbitrary serialize data
		if not _socket.was_string_packet():
			protocol_error.emit("Recieved an unexpected binary signaling packet.")
			continue

		var json := JSON.new()
		var parse_result := json.parse(packet.get_string_from_utf8())

		if parse_result != OK:
			protocol_error.emit("Recieved malformed JSON from the signaling service.")
			continue
		if typeof(json.data) != TYPE_DICTIONARY:
			protocol_error.emit("Recieved a JSON signaling message that was not an object.")
			continue

		var message: Dictionary = json.data
		message_received.emit(message)


func _report_closed_socket() -> void:
	var close_code := _socket.get_close_code()
	var close_reason := _socket.get_close_reason()

	_socket = null
	set_process(false)

	if _has_opened:
		connection_closed.emit(close_code, close_reason)
	else:
		(
			connection_failed
			. emit(
				"WebSocket did not open. Code: %d. Reason: %s" % [close_code, close_reason],
			)
		)

	_has_opened = false
	_session_url = ""
