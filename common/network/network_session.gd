class_name NetworkSession
extends Node

## Reusable two-player host/join session coordinator.
##
## SignalingClient owns the WSS control plane. WebRTCSession converts the one
## direct peer connection into a WebRTCMultiplayerPeer, which this coordinator
## installs on SceneTree so normal Godot RPC and replication nodes can use it.

signal state_changed(new_state: int, description: String)
signal host_started(session_code: String)
signal peer_available
signal multiplayer_peer_ready(peer: WebRTCMultiplayerPeer)
signal signaling_message_received(message: Dictionary)
signal session_failed(description: String)
signal session_closed(close_code: int, reason: String)
signal direct_connection_opened
signal peer_left(peer_id: int)
signal transport_diagnostic(message: String)

enum Role {
	NONE,
	HOST,
	CLIENT,
}

enum State {
	IDLE,
	CONNECTING_SIGNALING,
	WAITING_FOR_PEER,
	NEGOTIATING_WEBRTC,
	CONNECTED,
	CLOSING,
	FAILED,
}

const SESSION_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SESSION_CODE_LENGTH := 6
const WEBRTC_SESSION_SCRIPT := preload("res://common/network/webrtc_session.gd")
const WEBRTC_NEGOTIATION_TIMEOUT := 20.0

## STUN discovers each player's public NAT mapping. It does not relay gameplay;
## restrictive NATs may still require the deliberately deferred TURN fallback.
const ICE_SERVERS: Array[Dictionary] = [
	{
		"urls":
		[
			"stun:stun.cloudflare.com:3478",
		],
	},
]

var _signaling_client: SignalingClient
var _webrtc_session: WebRTCSession
var _installed_multiplayer_peer: WebRTCMultiplayerPeer
var _random := RandomNumberGenerator.new()
var _state := State.IDLE
var _role := Role.NONE
var _session_code := ""
var _negotiation_elapsed := 0.0
var _last_transport_diagnostic := ""


func _ready() -> void:
	_signaling_client = SignalingClient.new()
	add_child(_signaling_client)

	_signaling_client.connection_opened.connect(_on_signaling_connection_opened)
	_signaling_client.message_received.connect(_on_signaling_message_received)
	_signaling_client.connection_closed.connect(_on_signaling_connection_closed)
	_signaling_client.connection_failed.connect(_on_signaling_connection_failed)
	_signaling_client.protocol_error.connect(_on_signaling_protocol_error)
	multiplayer.peer_connected.connect(_on_scene_peer_connected)
	multiplayer.connected_to_server.connect(_on_scene_connected_to_server)

	_random.randomize()


func _process(delta: float) -> void:
	if _state != State.NEGOTIATING_WEBRTC:
		return
	_negotiation_elapsed += delta
	if _negotiation_elapsed >= WEBRTC_NEGOTIATION_TIMEOUT:
		var description := "Timed out while establishing the direct WebRTC route."
		var transport_summary := _last_transport_diagnostic
		if _webrtc_session != null:
			transport_summary = _webrtc_session.get_diagnostic_summary()
		if not transport_summary.is_empty():
			description += " %s" % transport_summary
		if _role == Role.HOST:
			# A failed join must not kill the authoritative solo session or code.
			if _webrtc_session != null:
				_webrtc_session.disconnect_remote_peer()
			_return_host_to_waiting(
				"Join attempt timed out; continuing solo. %s" % transport_summary,
				WebRTCSession.CLIENT_PEER_ID,
			)
		else:
			_fail(description)


func _exit_tree() -> void:
	# A scene transition must not leave SceneTree polling a peer owned by this
	# node after the node itself is gone.
	_dispose_webrtc_session()
	if _signaling_client != null:
		_signaling_client.close_connection("Network session scene exited.")


func host(signaling_base_url: String) -> Error:
	_prepare_retry_after_failure()
	if _state != State.IDLE:
		return ERR_ALREADY_IN_USE

	_last_transport_diagnostic = ""
	_session_code = _generate_session_code()
	_role = Role.HOST
	host_started.emit(_session_code)
	return _connect_to_signaling(signaling_base_url)


func join(signaling_base_url: String, requested_session_code: String) -> Error:
	_prepare_retry_after_failure()
	if _state != State.IDLE:
		return ERR_ALREADY_IN_USE

	var normalized_code := requested_session_code.strip_edges().to_upper()
	if not _is_valid_session_code(normalized_code):
		return ERR_INVALID_PARAMETER

	_last_transport_diagnostic = ""
	_session_code = normalized_code
	_role = Role.CLIENT
	return _connect_to_signaling(signaling_base_url)


func send_signaling_message(message_type: StringName, payload: Dictionary) -> Error:
	# Only offer, answer, and ICE routing data use the Worker.
	return _signaling_client.send_relay_message(message_type, payload)


func close_session(reason := "Player left the session.") -> void:
	if _state == State.IDLE:
		return

	_set_state(State.CLOSING, "Closing session")
	_dispose_webrtc_session()
	if not _signaling_client.close_connection(reason):
		_reset_to_idle()
		session_closed.emit(1000, reason)


func get_state() -> int:
	return _state


func get_role() -> int:
	return _role


func get_session_code() -> String:
	return _session_code


func get_multiplayer_peer() -> WebRTCMultiplayerPeer:
	return _installed_multiplayer_peer


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
	_set_state(State.CONNECTING_SIGNALING, "Signaling connected; waiting for session response")


func _on_signaling_message_received(message: Dictionary) -> void:
	signaling_message_received.emit(message)
	var message_type := String(message.get("type", ""))

	match message_type:
		"host_connected":
			# The host becomes a real high-level server before anyone joins, so
			# solo play and network play share one authoritative scene model.
			if _initialize_host_multiplayer() == OK:
				_set_state(
					State.WAITING_FOR_PEER,
					"Session %s is live; waiting for a second player" % _session_code,
				)
		"client_connected":
			# Do not start the timeout until the client actually owns a raw peer.
			# That makes NEGOTIATING_WEBRTC mean transport setup really began.
			if _initialize_client_multiplayer() == OK:
				_set_state(
					State.NEGOTIATING_WEBRTC,
					"Joined session; establishing direct peer route",
				)
				peer_available.emit()
		"client_joined":
			# Attach peer 2 before claiming that negotiation is underway. If setup
			# fails synchronously, its specific error remains visible instead.
			if _connect_host_to_client() == OK:
				_set_state(
					State.NEGOTIATING_WEBRTC,
					"Second player joined; establishing direct peer route",
				)
				peer_available.emit()
		"client_left":
			_handle_signaled_client_left()
		"offer", "answer", "ice_candidate":
			_forward_relay_message_to_webrtc(message)
		"signal_rejected":
			_fail(str(message.get("reason", "The signaling service rejected a message.")))


func _initialize_host_multiplayer() -> Error:
	var result := _ensure_webrtc_session()
	if result != OK:
		return result

	result = _webrtc_session.initialize_as_host()
	if result != OK and _state != State.FAILED:
		_fail("Could not initialize host multiplayer. Error: %d" % result)
	return result


func _initialize_client_multiplayer() -> Error:
	var result := _ensure_webrtc_session()
	if result != OK:
		return result

	_on_webrtc_diagnostic("Signaling accepted the join; creating the client WebRTC peer.")
	result = _webrtc_session.initialize_as_client(ICE_SERVERS)
	if result != OK and _state != State.FAILED:
		_fail("Could not initialize client multiplayer. Error: %d" % result)
	return result


func _connect_host_to_client() -> Error:
	if _webrtc_session == null:
		_fail("The host multiplayer server was not initialized before the client joined.")
		return ERR_UNCONFIGURED

	_on_webrtc_diagnostic("Signaling reported a joiner; creating the host WebRTC offer.")
	var result: Error = _webrtc_session.connect_host_to_client(ICE_SERVERS)
	if result != OK and _state != State.FAILED:
		_fail("Could not attach the joining peer. Error: %d" % result)
	return result


func _handle_signaled_client_left() -> void:
	if _role != Role.HOST:
		return
	if _webrtc_session != null:
		_webrtc_session.disconnect_remote_peer()
	# disconnect_remote_peer emits the normal callback when a peer was attached.
	# Calling the idempotent helper explicitly also covers the setup window where
	# the signaling client existed but no remote WebRTC peer was stored yet.
	_return_host_to_waiting(
		"Survivor 02 left; session %s remains open" % _session_code,
		WebRTCSession.CLIENT_PEER_ID,
	)


func _ensure_webrtc_session() -> Error:
	if _webrtc_session != null:
		return OK

	_webrtc_session = WEBRTC_SESSION_SCRIPT.new() as WebRTCSession
	if _webrtc_session == null:
		_fail("Could not instantiate the WebRTC session implementation in this export.")
		return ERR_CANT_CREATE

	add_child(_webrtc_session)
	_webrtc_session.relay_message_ready.connect(_on_webrtc_relay_message_ready)
	_webrtc_session.multiplayer_peer_ready.connect(_on_multiplayer_peer_ready)
	_webrtc_session.remote_peer_disconnected.connect(_on_webrtc_peer_disconnected)
	_webrtc_session.connection_failed.connect(_on_webrtc_connection_failed)
	_webrtc_session.diagnostic.connect(_on_webrtc_diagnostic)
	return OK


func _forward_relay_message_to_webrtc(message: Dictionary) -> void:
	if _webrtc_session == null:
		_fail("Received WebRTC signaling before direct connection setup.")
		return
	_webrtc_session.handle_signaling_message(message)


func _on_webrtc_relay_message_ready(message_type: StringName, payload: Dictionary) -> void:
	var result: Error = send_signaling_message(message_type, payload)
	if result != OK:
		_fail("Could not relay WebRTC signaling. Error: %d" % result)


func _on_multiplayer_peer_ready(peer: WebRTCMultiplayerPeer) -> void:
	# Installing immediately gives SceneTree responsibility for polling the
	# high-level peer before SDP negotiation can advance.
	_installed_multiplayer_peer = peer
	multiplayer.multiplayer_peer = peer
	multiplayer_peer_ready.emit(peer)


func _on_scene_peer_connected(peer_id: int) -> void:
	if _role == Role.HOST and peer_id == WebRTCSession.CLIENT_PEER_ID:
		_mark_direct_connection_open()


func _on_scene_connected_to_server() -> void:
	if _role == Role.CLIENT:
		_mark_direct_connection_open()


func _mark_direct_connection_open() -> void:
	if _state == State.CONNECTED:
		return
	_set_state(State.CONNECTED, "Direct peer route established")
	direct_connection_opened.emit()


func _on_webrtc_peer_disconnected(peer_id: int) -> void:
	if _role != Role.HOST:
		_fail("The host's direct connection ended.")
		return
	_return_host_to_waiting(
		"Survivor 02 left; session %s remains open" % _session_code,
		peer_id,
	)


func _return_host_to_waiting(description: String, peer_id: int) -> void:
	var was_already_waiting := _state == State.WAITING_FOR_PEER
	_set_state(
		State.WAITING_FOR_PEER,
		description,
	)
	if not was_already_waiting:
		peer_left.emit(peer_id)


func _on_webrtc_connection_failed(description: String) -> void:
	if _state != State.FAILED:
		_fail(description)


func _on_webrtc_diagnostic(message: String) -> void:
	_last_transport_diagnostic = message
	transport_diagnostic.emit(message)


func _on_signaling_connection_closed(close_code: int, reason: String) -> void:
	var was_failed := _state == State.FAILED
	_reset_to_idle()
	# Preserve the specific session_failed message already shown to the player;
	# our cleanup close reason is less useful and should not overwrite it.
	if not was_failed:
		session_closed.emit(close_code, reason)


func _on_signaling_connection_failed(description: String) -> void:
	_fail(description)


func _on_signaling_protocol_error(description: String) -> void:
	_fail(description)


func _dispose_webrtc_session() -> void:
	# SceneTree must stop polling this object before it is closed and freed.
	if _installed_multiplayer_peer != null:
		if multiplayer.multiplayer_peer == _installed_multiplayer_peer:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_installed_multiplayer_peer = null

	if _webrtc_session == null:
		return
	_webrtc_session.close_connection()
	_webrtc_session.queue_free()
	_webrtc_session = null


func _set_state(new_state: State, description: String) -> void:
	_state = new_state
	_negotiation_elapsed = 0.0
	state_changed.emit(_state, description)


func _fail(description: String) -> void:
	_dispose_webrtc_session()
	_state = State.FAILED
	_negotiation_elapsed = 0.0
	state_changed.emit(_state, description)
	session_failed.emit(description)
	# A failed attempt must release its signaling role and session code.
	_signaling_client.close_connection("Network session failed.")


func _reset_to_idle() -> void:
	_dispose_webrtc_session()
	_state = State.IDLE
	_role = Role.NONE
	_session_code = ""
	_negotiation_elapsed = 0.0
	_last_transport_diagnostic = ""
	state_changed.emit(_state, "Idle: choose Host or Join")


func _prepare_retry_after_failure() -> void:
	if _state == State.FAILED and not _signaling_client.has_connection():
		_reset_to_idle()


func _generate_session_code() -> String:
	var generated_code := ""
	for _index in SESSION_CODE_LENGTH:
		var alphabet_index := _random.randi_range(0, SESSION_CODE_ALPHABET.length() - 1)
		generated_code += SESSION_CODE_ALPHABET.substr(alphabet_index, 1)
	return generated_code


func _is_valid_session_code(session_code: String) -> bool:
	if session_code.length() != SESSION_CODE_LENGTH:
		return false

	for index in session_code.length():
		if not SESSION_CODE_ALPHABET.contains(session_code.substr(index, 1)):
			return false
	return true
