class_name VoiceDataChannel
extends RefCounted

## Owns the one negotiated, genuinely unreliable channel that carries voice.
##
## Godot's own unreliable multiplayer channels are reliable on web: the engine
## writes the misspelled maxPacketLifetime key, which WebIDL silently drops, and
## never sets maxRetransmits at all. Retransmitted voice always arrives too late
## to use, so this configures a channel itself instead of asking for a mode.

signal opened(peer_id: int)
signal closed(peer_id: int)
signal packet_received(payload: PackedByteArray)

## WebRTCMultiplayerPeer reserves stream ids 1, 2 and 3, and would take 4 next for
## the first channels_config entry. Nothing in this repo passes channels_config;
## keep it that way or these collide silently.
const CHANNEL_ID := 4
const CHANNEL_LABEL := "voice"
const CHANNEL_CONFIG := {
	"negotiated": true,
	"id": CHANNEL_ID,
	"ordered": false,
	"maxRetransmits": 0,
}
## About half a second of voice. Beyond this the queue is not draining and the
## frames in it are already too old to be worth sending.
const MAX_BUFFERED_BYTES := 4096

var _channel: WebRTCDataChannel
var _peer_id := 0
var _is_open := false
var _dropped := 0


## Must be called while the connection is still STATE_NEW. Both peers create
## their own end of the same stream id, so there is nothing to negotiate in band.
func open(connection: WebRTCPeerConnection, remote_peer_id: int) -> Error:
	close()
	if connection == null:
		return ERR_UNCONFIGURED
	_channel = connection.create_data_channel(CHANNEL_LABEL, CHANNEL_CONFIG.duplicate())
	if _channel == null:
		return ERR_UNAVAILABLE
	# Text mode would run the payload through a UTF-8 decoder on the way out.
	_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	_peer_id = remote_peer_id
	return OK


func close() -> void:
	if _channel != null:
		_channel.close()
		_channel = null
	if _is_open:
		_is_open = false
		closed.emit(_peer_id)
	_peer_id = 0


func is_open() -> bool:
	return _is_open


func peer_id() -> int:
	return _peer_id


func dropped_count() -> int:
	return _dropped


func buffered_amount() -> int:
	return 0 if _channel == null else _channel.get_buffered_amount()


func poll() -> void:
	if _channel == null:
		return
	_channel.poll()
	_update_open_state()
	if not _is_open:
		return
	while _channel.get_available_packet_count() > 0:
		packet_received.emit(_channel.get_packet())


## Drops rather than queues: there is no send error and no backpressure signal on
## web, and an overflow surfaces as an uncaught JS exception inside the wasm frame.
func send(payload: PackedByteArray) -> Error:
	if _channel == null or not _is_open:
		return ERR_UNCONFIGURED
	if _channel.get_buffered_amount() > MAX_BUFFERED_BYTES:
		_dropped += 1
		return ERR_BUSY
	return _channel.put_packet(payload)


func _update_open_state() -> void:
	var now_open := _channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN
	if now_open == _is_open:
		return
	_is_open = now_open
	if now_open:
		opened.emit(_peer_id)
	else:
		closed.emit(_peer_id)
