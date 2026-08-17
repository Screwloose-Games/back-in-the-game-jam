extends Node

## The only voice type the rest of the game references.
##
## Owns the microphone, the encoder, the per-speaker bus slots and the routing
## between them. The governing rule is that voice is never load-bearing: every
## failure here degrades to a playable game with no voice, never to a broken
## session, which is why nothing in this file returns an error to a caller.

signal voice_unavailable(reason: String)
signal microphone_state_changed(live: bool, transmitting: bool)
signal local_level_changed(level: float)
signal peer_started_speaking(peer_id: int)
signal peer_stopped_speaking(peer_id: int)

## Declared statically in default_bus_layout.tres. Never call AudioServer.add_bus()
## for these: at runtime it corrupts the web bus mirror and can disconnect Master
## from the output, silencing every other sound in the game (godot#119026).
const SLOT_BUSES: Array[StringName] = [&"Voice_0", &"Voice_1"]
const SHARED_BUS := &"VoiceChat"
const CAPTURE_BUS := &"VoiceCapture"
const PUSH_TO_TALK_ACTION := &"voice_push_to_talk"
## A speaker whose packets stop for this long has stopped talking.
const SPEAKING_TIMEOUT := 0.25
## How often the pipeline reports itself while the microphone is open. On web the
## browser console is the only log a player can reach, so this is the readout.
const DEBUG_HEARTBEAT := 5.0
## How long a live microphone may deliver nothing before the player is told. Long
## because on web this clock starts before the browser's permission prompt is
## answered, and a player reading that dialog is not a fault.
const CAPTURE_SILENCE_TIMEOUT := 15.0

var config := VoiceConfig.new()
## Heartbeats the pipeline counters to the console while the microphone is open.
var debug_logging := true
## Debug: routes locally encoded packets back into the local avatar's own 3D
## player, so the whole pipeline can be heard with no second peer and no network.
var loopback_enabled := false
var voice_enabled := false:
	set = _set_voice_enabled
var push_to_talk := false:
	set = _set_push_to_talk
var open_dbfs := -45.0:
	set = _set_open_dbfs

var _capture: VoiceCapture
var _detector: VoiceActivityDetector
var _local_voice: PlayerProximityVoiceChat
var _speakers := {}
var _slots := {}
var _free_slots: Array[int] = []
var _muted := {}
var _volumes := {}
var _speaking_ages := {}
var _sequence := 0
var _transmitting := false
var _microphone_live := false
var _unavailable_reason := ""
var _capture_silence := 0.0
var _silence_reported := false
var _heartbeat := 0.0
var _channel_open := false
var _frames_captured := 0
var _packets_sent := 0
var _send_errors := 0
var _packets_received := 0
var _packets_unclaimed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detector = VoiceActivityDetector.new(config)
	_capture = VoiceCapture.new(config)
	for slot in SLOT_BUSES.size():
		_free_slots.append(slot)

	OnlineSession.voice_packet_received.connect(_on_voice_packet_received)
	OnlineSession.voice_channel_opened.connect(_on_voice_channel_opened)
	OnlineSession.voice_channel_closed.connect(_on_voice_channel_closed)
	OnlineSession.peer_left.connect(unregister_speaker)

	var saved := GameSettings.settings as Settings
	if saved != null:
		open_dbfs = saved.voice_open_dbfs
		push_to_talk = saved.voice_push_to_talk
		voice_enabled = saved.voice_enabled


func _process(delta: float) -> void:
	_age_speakers(delta)
	if _capture == null or not _capture.is_active():
		return
	var frames := _capture.poll()
	_frames_captured += frames.size()
	for frame in frames:
		_encode_and_send(frame)
	_watch_for_silent_capture(delta, frames.size())
	_beat_debug_heartbeat(delta)


func register_local_voice(node: PlayerProximityVoiceChat) -> void:
	_local_voice = node
	_apply_capture_state()


func unregister_local_voice(node: PlayerProximityVoiceChat) -> void:
	if _local_voice != node:
		return
	_local_voice = null
	_apply_capture_state()


## Returns the bus the caller should play on. Falls back to the shared voice bus
## when the slots are exhausted: audible, but without per-peer mute or occlusion.
func register_speaker(peer_id: int, node: PlayerProximityVoiceChat) -> StringName:
	_speakers[peer_id] = node
	if not _slots.has(peer_id):
		_slots[peer_id] = -1 if _free_slots.is_empty() else _free_slots.pop_front()
	var slot: int = _slots[peer_id]
	return SHARED_BUS if slot < 0 else SLOT_BUSES[slot]


func unregister_speaker(peer_id: int) -> void:
	_speakers.erase(peer_id)
	var slot: int = int(_slots.get(peer_id, -1))
	if slot >= 0 and not _free_slots.has(slot):
		_free_slots.append(slot)
	_slots.erase(peer_id)
	if _speaking_ages.erase(peer_id):
		peer_stopped_speaking.emit(peer_id)


func set_peer_muted(peer_id: int, muted: bool) -> void:
	_muted[peer_id] = muted
	_apply_peer_mix(peer_id)


func is_peer_muted(peer_id: int) -> bool:
	return bool(_muted.get(peer_id, false))


func set_peer_volume(peer_id: int, volume: float) -> void:
	_volumes[peer_id] = clampf(volume, 0.0, 1.0)
	_apply_peer_mix(peer_id)


func peer_volume(peer_id: int) -> float:
	return float(_volumes.get(peer_id, 1.0))


func is_peer_speaking(peer_id: int) -> bool:
	return _speaking_ages.has(peer_id)


func remote_peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for peer_id in _speakers:
		ids.append(peer_id)
	ids.sort()
	return ids


func local_loudness() -> float:
	return 0.0 if _detector == null else _detector.loudness()


func is_transmitting() -> bool:
	return _transmitting


func is_microphone_live() -> bool:
	return _microphone_live


func unavailable_reason() -> String:
	return _unavailable_reason


func is_voice_channel_open() -> bool:
	return _channel_open


## Every stage of this pipeline used to fail without a word, so each one is counted.
## Read it from the pause menu, or off the browser console on web.
func debug_summary() -> String:
	var capture_name := "none"
	if _capture != null:
		capture_name = str(_capture.get_script().resource_path.get_file())
	var peak := 0.0
	if _capture != null and _capture.has_method("last_peak"):
		peak = float(_capture.call("last_peak"))
	return (
		"capture=%s live=%s peak=%.4f frames=%d rate=%s | channel=%s sent=%d errors=%d | recv=%d unclaimed=%d speakers=%s"
		% [
			capture_name,
			_microphone_live,
			peak,
			_frames_captured,
			_rate_summary(),
			_channel_open,
			_packets_sent,
			_send_errors,
			_packets_received,
			_packets_unclaimed,
			str(remote_peer_ids()),
		]
	)


## Reported / measured / applied. The first two disagreeing is a browser lying
## about its capture rate, which pitch-shifts everything this player says.
func _rate_summary() -> String:
	if _capture == null:
		return "none"
	return (
		"%d/%.0f/%d" % [_capture.reported_rate(), _capture.observed_rate(), _capture.source_rate()]
	)


func _set_voice_enabled(value: bool) -> void:
	if value == voice_enabled:
		return
	voice_enabled = value
	_apply_capture_state()


func _set_push_to_talk(value: bool) -> void:
	push_to_talk = value
	if _detector != null:
		_detector.reset()
	_set_transmitting(false)


func _set_open_dbfs(value: float) -> void:
	open_dbfs = value
	config.vad_open_dbfs = value
	if _detector != null:
		_detector.set_open_dbfs(value)


## The sequence number advances every captured frame, gated or not, so it stays a
## clock: a gap then means lost packets or a deliberate silence, not a stall.
func _encode_and_send(frame: PackedFloat32Array) -> void:
	var gate_open := _detector.process(frame)
	local_level_changed.emit(_detector.loudness())
	if push_to_talk:
		gate_open = Input.is_action_pressed(PUSH_TO_TALK_ACTION)
	_set_transmitting(gate_open)

	var sequence := _sequence
	_sequence = VoicePacket.next_sequence(_sequence)
	if not gate_open:
		return

	var payload := VoicePacket.pack(_local_peer_id(), sequence, VoiceAdpcm.encode(frame))
	if loopback_enabled:
		_on_voice_packet_received(payload)
		return
	if OnlineSession.send_voice_packet(payload) == OK:
		_packets_sent += 1
	else:
		_send_errors += 1


func _apply_capture_state() -> void:
	var wanted := voice_enabled and _local_voice != null
	if wanted == _microphone_live:
		return
	if wanted:
		_start_capture()
	else:
		_stop_capture()


## The driver path is preferred: AudioServer.get_input_frames() reads upstream of
## the player's volume and the bus effects, so the microphone node can be silenced
## outright. The bus path is the documented fallback (spec 4.2) and cannot be, since
## its AudioEffectCapture reads the signal the player already mixed - silencing what
## the player hears and feeding the encoder are one knob there.
func _start_capture() -> void:
	var driver_capture := GodotVoiceCapture.new(config)
	if driver_capture.start() == OK:
		_begin_capture(driver_capture, true)
		return

	var bus_capture := MicBusVoiceCapture.new(config, CAPTURE_BUS)
	if bus_capture.start() != OK:
		_report_unavailable(bus_capture.unavailable_reason())
		return
	if bus_capture.has_rate_mismatch():
		push_warning("Voice: input and output mix rates differ; capture will be pitch-shifted.")
	_begin_capture(bus_capture, false)


## The microphone node is what opens the input device; both capture paths need it
## playing, and only the bus path needs it audible.
func _begin_capture(microphone: VoiceCapture, monitor_silent: bool) -> void:
	_capture = microphone
	_detector.reset()
	_sequence = 0
	_capture_silence = 0.0
	_silence_reported = false
	_unavailable_reason = ""
	_microphone_live = true
	_local_voice.set_microphone_active(true, monitor_silent)
	microphone_state_changed.emit(true, _transmitting)


func _stop_capture() -> void:
	if _capture != null:
		_capture.stop()
	_capture = VoiceCapture.new(config)
	if _local_voice != null:
		_local_voice.set_microphone_active(false)
	_microphone_live = false
	_capture_silence = 0.0
	_set_transmitting(false)
	microphone_state_changed.emit(false, false)


## An open device that never delivers a frame is the failure this whole bug hid
## behind, so it is said out loud. Deliberately not a teardown: permission may still
## be pending, and answering the prompt late must still get you a working microphone.
func _watch_for_silent_capture(delta: float, captured: int) -> void:
	if _frames_captured > 0:
		return
	if captured > 0:
		return
	_capture_silence += delta
	if _capture_silence < CAPTURE_SILENCE_TIMEOUT or _silence_reported:
		return
	_silence_reported = true
	_unavailable_reason = "The microphone is open but no audio is arriving."
	push_warning("Voice: %s" % _unavailable_reason)
	voice_unavailable.emit(_unavailable_reason)


func _beat_debug_heartbeat(delta: float) -> void:
	if not debug_logging:
		return
	_heartbeat += delta
	if _heartbeat < DEBUG_HEARTBEAT:
		return
	_heartbeat = 0.0
	print("[voice] %s" % debug_summary())


func _report_unavailable(reason: String) -> void:
	_unavailable_reason = reason
	_capture = VoiceCapture.new(config)
	if _local_voice != null:
		_local_voice.set_microphone_active(false)
	_microphone_live = false
	_capture_silence = 0.0
	_set_transmitting(false)
	voice_unavailable.emit(reason)
	microphone_state_changed.emit(false, false)


func _set_transmitting(value: bool) -> void:
	if value == _transmitting:
		return
	_transmitting = value
	microphone_state_changed.emit(_microphone_live, _transmitting)


func _on_voice_packet_received(payload: PackedByteArray) -> void:
	var packet := VoicePacket.unpack(payload)
	if packet.is_empty():
		return
	_packets_received += 1
	var speaker_id := int(packet["speaker_id"])
	var node: PlayerProximityVoiceChat = _speakers.get(speaker_id)
	if node == null:
		# Audio arriving for a peer whose avatar has not spawned yet, or at all.
		_packets_unclaimed += 1
		return
	node.receive_voice(packet)
	if not _speaking_ages.has(speaker_id):
		peer_started_speaking.emit(speaker_id)
	_speaking_ages[speaker_id] = 0.0


func _on_voice_channel_opened(peer_id: int) -> void:
	_channel_open = true
	print("[voice] channel open to peer %d" % peer_id)


## A rejoin builds a new connection and a new channel, so a stale sequence would
## read as a wild jump on the far side.
func _on_voice_channel_closed(_peer_id: int) -> void:
	_channel_open = false
	print("[voice] channel closed")
	_sequence = 0
	for node in _speakers.values():
		node.reset_playout()


func _apply_peer_mix(peer_id: int) -> void:
	var node: PlayerProximityVoiceChat = _speakers.get(peer_id)
	if node != null:
		node.set_listener_mix(peer_volume(peer_id), is_peer_muted(peer_id))


func _age_speakers(delta: float) -> void:
	for peer_id in _speaking_ages.keys():
		var age: float = float(_speaking_ages[peer_id]) + delta
		if age < SPEAKING_TIMEOUT:
			_speaking_ages[peer_id] = age
			continue
		_speaking_ages.erase(peer_id)
		peer_stopped_speaking.emit(peer_id)


func _local_peer_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return WebRTCSession.HOST_PEER_ID
