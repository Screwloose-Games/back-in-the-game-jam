class_name WebRTCSession
extends Node
## Direct peer-to-peer WebRTC transport.
##
## This class does not know about menus, session codes, or game state.
## Its caller gives it signaling messages and forwards the emitted messages
## through the existing signaling service.

signal relay_message_ready(message_type: StringName, payload: Dictionary)
signal connection_opened()
signal connection_failed(description: String)
# Raw application bytes received over the direct WebRTC data channel.
signal packet_received(packet: PackedByteArray)
# Small lifecycle facts for diagnostics; never sent to the remote peer.
signal diagnostic(message: String)

# The host creates this channel. The client receives it through the
# data_channel_received signal.
const GAMEPLAY_CHANNEL_LABEL := "gameplay"

var _peer: WebRTCPeerConnection
var _data_channel: WebRTCDataChannel
var _connection_reported_open := false


func _ready() -> void:
	# WebRTCPeerConnection needs regular polling to emit its callbacks.
	set_process(false)


func start_as_host(ice_servers: Array[Dictionary]) -> Error:
	# The host is the offerer: it creates the channel, then creates an offer.
	var result: Error = _create_peer(ice_servers)
	if result != OK:
		return result

	_data_channel = _peer.create_data_channel(GAMEPLAY_CHANNEL_LABEL)
	if _data_channel == null:
		_fail("Could not create the gameplay data channel.")
		return ERR_CANT_CREATE

	diagnostic.emit("Host created the gameplay data channel; requesting an SDP offer.")
	result = _peer.create_offer()
	if result != OK:
		_fail("Could not create a WebRTC offer. Error: %d" % result)

	return result


func start_as_client(ice_servers: Array[Dictionary]) -> Error:
	# The client waits for the host's offer and for its data channel.
	var result: Error = _create_peer(ice_servers)
	if result == OK:
		diagnostic.emit("Client WebRTC peer is ready; waiting for the host offer.")
	return result


func handle_signaling_message(message: Dictionary) -> void:
	# NetworkSession passes only validated relay messages to this method.
	if _peer == null:
		_fail("Received WebRTC signaling before the peer connection was created.")
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


func close_connection() -> void:
	# This object is single-use per host/join attempt.
	set_process(false)

	if _data_channel != null:
		_data_channel.close()
		_data_channel = null

	if _peer != null:
		_peer.close()
		_peer = null

	_connection_reported_open = false


func send_packet(packet: PackedByteArray) -> Error:
	# Transport deliberately accepts bytes only. Packet meaning belongs to the
	# game or prototype layer above WebRTCSession.
	if _data_channel == null \
			or _data_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_UNAVAILABLE

	return _data_channel.put_packet(packet)


func _process(_delta: float) -> void:
	if _peer == null:
		return

	_peer.poll()

	# A usable gameplay channel (not merely ICE connection) is our definition
	# of “connected” for the game layer.
	if _data_channel != null \
			and _data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
			and not _connection_reported_open:
		_connection_reported_open = true
		connection_opened.emit()

	if _peer.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
		_fail("The direct WebRTC connection failed.")
		return

	_read_available_packets()


func _read_available_packets() -> void:
	if _data_channel == null \
			or _data_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return

	while _data_channel.get_available_packet_count() > 0:
		var packet: PackedByteArray = _data_channel.get_packet()
		packet_received.emit(packet)


func _create_peer(ice_servers: Array[Dictionary]) -> Error:
	if _peer != null:
		return ERR_ALREADY_IN_USE

	diagnostic.emit("Requesting the engine WebRTC implementation.")
	_peer = WebRTCPeerConnection.new()

	if _peer == null:
		_fail("This export has no WebRTC peer implementation available.")
		return ERR_UNAVAILABLE

	# STUN/TURN configuration belongs to the caller, not this reusable class.
	var result: Error = _peer.initialize({ "iceServers": ice_servers })
	if result != OK:
		_peer = null
		_fail("Could not initialize WebRTC. Error: %d" % result)
		return result

	# These events produce the messages that travel through the Worker.
	_peer.session_description_created.connect(_on_session_description_created)
	_peer.ice_candidate_created.connect(_on_ice_candidate_created)

	# The client receives the host-created, in-band gameplay channel here.
	_peer.data_channel_received.connect(_on_data_channel_received)

	set_process(true)
	diagnostic.emit("WebRTC peer initialized.")
	return OK


func _apply_remote_description(description_type: String, payload: Dictionary) -> void:
	var sdp := String(payload.get("sdp", ""))

	if sdp.is_empty():
		_fail("Received a WebRTC %s without SDP." % description_type)
		return

	var result: Error = _peer.set_remote_description(description_type, sdp)
	if result != OK:
		_fail(
			"Could not apply the remote %s. Error: %d" % [
				description_type,
				result,
			],
		)
		return

	diagnostic.emit("Applied remote %s." % description_type)


func _add_remote_ice_candidate(payload: Dictionary) -> void:
	var media := String(payload.get("media", ""))
	var index := int(payload.get("index", -1))
	var candidate := String(payload.get("candidate", ""))

	if index < 0 or candidate.is_empty():
		_fail("Received an invalid ICE candidate.")
		return

	var result: Error = _peer.add_ice_candidate(media, index, candidate)
	if result != OK:
		_fail("Could not add a remote ICE candidate. Error: %d" % result)


func _on_session_description_created(description_type: String, sdp: String) -> void:
	diagnostic.emit("Generated local %s." % description_type)
	# Apply our own description locally before giving the SDP to the othe peer.
	var result: Error = _peer.set_local_description(description_type, sdp)
	if result != OK:
		_fail(
			"Could not set the local %s. Error: %d" % [
				description_type,
				result,
			],
		)
		return

	relay_message_ready.emit(
		StringName(description_type),
		{ "sdp": sdp },
	)


func _on_ice_candidate_created(
		media: String,
		index: int,
		candidate: String,
) -> void:
	# Candidates are connection-routing information, never gameplay state.
	diagnostic.emit("Generated an ICE candidate.")
	relay_message_ready.emit(
		&"ice_candidate",
		{
			"media": media,
			"index": index,
			"candidate": candidate,
		},
	)


func _on_data_channel_received(channel: WebRTCDataChannel) -> void:
	if channel.get_label() != GAMEPLAY_CHANNEL_LABEL:
		channel.close()
		return

	_data_channel = channel
	diagnostic.emit("Received the host gameplay data channel.")


func _fail(description: String) -> void:
	close_connection()
	connection_failed.emit(description)
