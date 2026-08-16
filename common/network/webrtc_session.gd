class_name WebRTCSession
extends Node

## Bridges one signaled WebRTC connection into Godot's high-level multiplayer API.
##
## The Cloudflare Worker still carries SDP and ICE messages, but gameplay no
## longer uses a custom data channel. WebRTCMultiplayerPeer creates and owns the
## channels consumed by RPC, MultiplayerSynchronizer, and MultiplayerSpawner.

signal relay_message_ready(message_type: StringName, payload: Dictionary)
signal multiplayer_peer_ready(peer: WebRTCMultiplayerPeer)
signal remote_peer_disconnected(peer_id: int)
signal connection_failed(description: String)
signal diagnostic(message: String)
signal voice_channel_opened(peer_id: int)
signal voice_channel_closed(peer_id: int)
signal voice_packet_received(payload: PackedByteArray)

const HOST_PEER_ID := 1
const CLIENT_PEER_ID := 2
const DISCONNECTED_GRACE_SECONDS := 5.0
const CONNECTION_STATE_NAMES := {
	WebRTCPeerConnection.STATE_NEW: "new",
	WebRTCPeerConnection.STATE_CONNECTING: "connecting",
	WebRTCPeerConnection.STATE_CONNECTED: "connected",
	WebRTCPeerConnection.STATE_DISCONNECTED: "disconnected",
	WebRTCPeerConnection.STATE_FAILED: "failed",
	WebRTCPeerConnection.STATE_CLOSED: "closed",
}

var _multiplayer_peer: WebRTCMultiplayerPeer
var _connection: WebRTCPeerConnection
var _remote_peer_id := 0
var _disconnected_elapsed := 0.0
var _last_connection_state := -1
var _local_description_type := "none"
var _remote_description_type := "none"
var _local_candidate_count := 0
var _remote_candidate_count := 0
var _high_level_channels_open := false
var _is_host := false
var _voice_channel := VoiceDataChannel.new()


## Creates the host's high-level server immediately, before a joiner exists.
## This lets the host run the same authoritative scene while playing solo.
func initialize_as_host() -> Error:
	if _multiplayer_peer != null:
		return ERR_ALREADY_IN_USE

	_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var result: Error = _multiplayer_peer.create_server()
	if result != OK:
		_multiplayer_peer = null
		_fail("Could not create the WebRTC multiplayer server. Error: %d" % result)
		return result

	_is_host = true
	_wire_multiplayer_peer()
	diagnostic.emit("High-level multiplayer server created as peer 1.")
	multiplayer_peer_ready.emit(_multiplayer_peer)
	return OK


## Creates peer 2 and its connection to the host, then waits for the offer.
func initialize_as_client(ice_servers: Array) -> Error:
	if _multiplayer_peer != null:
		return ERR_ALREADY_IN_USE

	_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var result: Error = _multiplayer_peer.create_client(CLIENT_PEER_ID)
	if result != OK:
		_multiplayer_peer = null
		_fail("Could not create the WebRTC multiplayer client. Error: %d" % result)
		return result

	_is_host = false
	_wire_multiplayer_peer()
	# The caller installs this peer on SceneTree synchronously from the signal.
	# It must own polling before an incoming offer advances negotiation.
	multiplayer_peer_ready.emit(_multiplayer_peer)

	result = _attach_remote_connection(HOST_PEER_ID, ice_servers)
	if result == OK:
		diagnostic.emit("Client peer 2 is ready and waiting for the host offer.")
	return result


## Adds peer 2 to the already-running host and begins the one allowed offer.
func connect_host_to_client(ice_servers: Array) -> Error:
	if _multiplayer_peer == null or not _is_host:
		return ERR_UNCONFIGURED
	if _connection != null:
		return ERR_ALREADY_IN_USE

	var result: Error = _attach_remote_connection(CLIENT_PEER_ID, ice_servers)
	if result != OK:
		return result

	diagnostic.emit("Host added peer 2; requesting an SDP offer.")
	result = _connection.create_offer()
	if result != OK:
		_fail("Could not create a WebRTC offer. Error: %d" % result)
	return result


## Applies an offer, answer, or ICE candidate received through signaling.
func handle_signaling_message(message: Dictionary) -> void:
	if _connection == null:
		_fail("Received WebRTC signaling before the remote peer was attached.")
		return

	var message_type := String(message.get("type", ""))
	var raw_payload: Variant = message.get("payload", {})
	if typeof(raw_payload) != TYPE_DICTIONARY:
		_fail("Received a WebRTC signaling message without an object payload.")
		return

	var payload: Dictionary = raw_payload
	match message_type:
		"offer", "answer":
			_apply_remote_description(message_type, payload)
		"ice_candidate":
			_add_remote_ice_candidate(payload)


func get_multiplayer_peer() -> WebRTCMultiplayerPeer:
	return _multiplayer_peer


func send_voice_packet(payload: PackedByteArray) -> Error:
	return _voice_channel.send(payload)


func voice_buffered_amount() -> int:
	return _voice_channel.buffered_amount()


func get_diagnostic_summary() -> String:
	var ice_state := "not initialized"
	if _connection != null:
		ice_state = _connection_state_name(_connection.get_connection_state())
	elif _last_connection_state >= 0:
		ice_state = "%s (last observed)" % _connection_state_name(_last_connection_state)
	return (
		"ICE %s; channels %s; local/remote SDP %s/%s; candidates sent/received %d/%d."
		% [
			ice_state,
			"open" if _high_level_channels_open else "waiting",
			_local_description_type,
			_remote_description_type,
			_local_candidate_count,
			_remote_candidate_count,
		]
	)


## Removes only the remote connection while retaining the host's peer-1 server.
## The same join code can therefore return to a solo waiting state.
func disconnect_remote_peer() -> void:
	_drop_remote_connection(true)


func close_connection() -> void:
	set_process(false)
	_drop_remote_connection(false)

	if _multiplayer_peer != null:
		_multiplayer_peer.close()
		_multiplayer_peer = null
	_is_host = false


func _ready() -> void:
	_voice_channel.opened.connect(voice_channel_opened.emit)
	_voice_channel.closed.connect(voice_channel_closed.emit)
	_voice_channel.packet_received.connect(voice_packet_received.emit)


## SceneTree polls WebRTCMultiplayerPeer. This process hook only observes the
## underlying ICE state so a failed route gets a useful player-facing error, and
## drives the voice channel, which the high-level peer knows nothing about.
func _process(delta: float) -> void:
	if _connection == null:
		return
	_voice_channel.poll()
	var connection_state := _connection.get_connection_state()
	if connection_state != _last_connection_state:
		_last_connection_state = connection_state
		diagnostic.emit("ICE connection state: %s." % _connection_state_name(connection_state))
	_update_high_level_channel_state()
	match connection_state:
		WebRTCPeerConnection.STATE_DISCONNECTED:
			# ICE can report a short disconnection while a route changes. Give it a
			# chance to recover before ending an otherwise healthy session.
			_disconnected_elapsed += delta
			if _disconnected_elapsed >= DISCONNECTED_GRACE_SECONDS:
				_handle_terminal_remote_state("The direct WebRTC route stayed disconnected.")
		WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED:
			_handle_terminal_remote_state(
				"The direct WebRTC connection closed before it was usable."
			)
		_:
			_disconnected_elapsed = 0.0


func _wire_multiplayer_peer() -> void:
	_multiplayer_peer.peer_disconnected.connect(_on_peer_disconnected)


func _connection_state_name(connection_state: int) -> String:
	return str(CONNECTION_STATE_NAMES.get(connection_state, "unknown (%d)" % connection_state))


func _update_high_level_channel_state() -> void:
	if (
		_multiplayer_peer == null
		or _remote_peer_id == 0
		or not _multiplayer_peer.has_peer(_remote_peer_id)
	):
		_high_level_channels_open = false
		return

	var peer_details: Dictionary = _multiplayer_peer.get_peer(_remote_peer_id)
	var channels_open := bool(peer_details.get("connected", false))
	if channels_open and not _high_level_channels_open:
		diagnostic.emit("Godot's high-level multiplayer channels are open.")
	_high_level_channels_open = channels_open


func _attach_remote_connection(remote_peer_id: int, ice_servers: Array) -> Error:
	if _connection != null:
		return ERR_ALREADY_IN_USE

	diagnostic.emit("Requesting the engine WebRTC implementation.")
	_connection = WebRTCPeerConnection.new()
	if _connection == null:
		_fail("This export has no WebRTC peer implementation available.")
		return ERR_UNAVAILABLE

	var result: Error = _connection.initialize({"iceServers": ice_servers})
	if result != OK:
		_connection = null
		_fail("Could not initialize WebRTC. Error: %d" % result)
		return result

	_connection.session_description_created.connect(_on_session_description_created)
	_connection.ice_candidate_created.connect(_on_ice_candidate_created)

	# add_peer must happen while WebRTCPeerConnection is still STATE_NEW. It
	# creates Godot's reliable, unreliable, and ordered multiplayer channels.
	result = _multiplayer_peer.add_peer(_connection, remote_peer_id)
	if result != OK:
		_connection.close()
		_connection = null
		_fail("Could not add remote peer %d. Error: %d" % [remote_peer_id, result])
		return result

	# create_data_channel only works while the connection is STATE_NEW, which
	# ends at the first create_offer() or set_remote_description(). Both peers
	# reach this line before that, so neither needs to be told about the other's.
	if _voice_channel.open(_connection, remote_peer_id) != OK:
		diagnostic.emit("Voice channel unavailable; the session continues without voice.")

	_remote_peer_id = remote_peer_id
	_disconnected_elapsed = 0.0
	_last_connection_state = -1
	_local_description_type = "none"
	_remote_description_type = "none"
	_local_candidate_count = 0
	_remote_candidate_count = 0
	_high_level_channels_open = false
	set_process(true)
	diagnostic.emit("WebRTC peer connection initialized for peer %d." % remote_peer_id)
	return OK


func _apply_remote_description(description_type: String, payload: Dictionary) -> void:
	var sdp := String(payload.get("sdp", ""))
	if sdp.is_empty():
		_fail("Received a WebRTC %s without SDP." % description_type)
		return

	var result: Error = _connection.set_remote_description(description_type, sdp)
	if result != OK:
		_fail("Could not apply the remote %s. Error: %d" % [description_type, result])
		return

	# Applying an offer causes Godot to generate the answer asynchronously.
	_remote_description_type = description_type
	diagnostic.emit("Applied remote %s." % description_type)


func _add_remote_ice_candidate(payload: Dictionary) -> void:
	var media := String(payload.get("media", ""))
	var index := int(payload.get("index", -1))
	var candidate := String(payload.get("candidate", ""))
	if index < 0 or candidate.is_empty():
		_fail("Received an invalid ICE candidate.")
		return

	var result: Error = _connection.add_ice_candidate(media, index, candidate)
	if result != OK:
		_fail("Could not add a remote ICE candidate. Error: %d" % result)
		return
	_remote_candidate_count += 1
	diagnostic.emit("Applied remote ICE candidate %d." % _remote_candidate_count)


func _on_session_description_created(description_type: String, sdp: String) -> void:
	diagnostic.emit("Generated local %s." % description_type)
	var result: Error = _connection.set_local_description(description_type, sdp)
	if result != OK:
		_fail("Could not set the local %s. Error: %d" % [description_type, result])
		return

	_local_description_type = description_type
	relay_message_ready.emit(StringName(description_type), {"sdp": sdp})


func _on_ice_candidate_created(media: String, index: int, candidate: String) -> void:
	# Candidates describe routes only; gameplay never passes through signaling.
	_local_candidate_count += 1
	diagnostic.emit("Relaying local ICE candidate %d." % _local_candidate_count)
	(
		relay_message_ready
		. emit(
			&"ice_candidate",
			{
				"media": media,
				"index": index,
				"candidate": candidate,
			},
		)
	)


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id != _remote_peer_id:
		return
	if _multiplayer_peer != null and _is_host:
		_drop_remote_connection(true)
	else:
		_fail("Peer %d disconnected from the direct session." % peer_id)


func _handle_terminal_remote_state(description: String) -> void:
	if _multiplayer_peer != null and _is_host:
		diagnostic.emit(description + " Host remains available for another joiner.")
		_drop_remote_connection(true)
	else:
		_fail(description)


func _drop_remote_connection(emit_disconnected: bool) -> void:
	var disconnected_peer_id := _remote_peer_id
	_remote_peer_id = 0
	_disconnected_elapsed = 0.0
	set_process(false)

	# Clear our ID before remove_peer(), because that method may synchronously
	# emit peer_disconnected again.
	if (
		_multiplayer_peer != null
		and disconnected_peer_id != 0
		and _multiplayer_peer.has_peer(disconnected_peer_id)
	):
		_multiplayer_peer.remove_peer(disconnected_peer_id)

	# Released before the connection that owns it: a rejoin builds a new
	# WebRTCPeerConnection, and a stale channel reference would accept sends
	# into a dead stream without reporting anything.
	_voice_channel.close()

	if _connection != null:
		_connection.close()
		_connection = null

	if emit_disconnected and disconnected_peer_id != 0:
		remote_peer_disconnected.emit(disconnected_peer_id)


func _fail(description: String) -> void:
	# A bad guest route must not tear down the host's high-level server. Keeping
	# it installed lets peer 1 continue solo and accept another join attempt with
	# the same code. A client failure still ends its entire connection.
	if _is_host and _multiplayer_peer != null:
		_drop_remote_connection(false)
	else:
		close_connection()
	connection_failed.emit(description)
