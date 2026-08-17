class_name VoiceJitterBuffer
extends RefCounted

## One speaker's reorder queue: trades a little latency for smooth playout.
##
## An unreliable channel delivers frames late, twice, out of order, or not at
## all, so this is the only place downstream of the decoder that has to know the
## transport is lossy.

const MAX_CONCEALED_FRAMES := 3

var _samples_per_frame := 0
var _initial_target := 3
var _target_frames := 3
var _max_frames := 6
var _reset_gap := 32
var _frames := {}
var _next_sequence := 0
var _started := false
var _last_frame := PackedFloat32Array()
var _concealed := 0
var _underruns := 0
var _dropped_late := 0
var _dropped_duplicate := 0
var _dropped_overflow := 0
var _resets := 0


func _init(config: VoiceConfig) -> void:
	_samples_per_frame = config.samples_per_frame()
	_initial_target = maxi(config.jitter_target_frames, 1)
	_target_frames = _initial_target
	_max_frames = maxi(config.jitter_max_frames, _initial_target)
	_reset_gap = maxi(config.jitter_reset_gap, 1)


func depth() -> int:
	return _frames.size()


func is_active() -> bool:
	return _started


func target_frames() -> int:
	return _target_frames


func underruns() -> int:
	return _underruns


func dropped_late() -> int:
	return _dropped_late


func dropped_duplicate() -> int:
	return _dropped_duplicate


func dropped_overflow() -> int:
	return _dropped_overflow


func resets() -> int:
	return _resets


## Clears playout state but keeps the diagnostic counters.
func reset() -> void:
	_frames.clear()
	_next_sequence = 0
	_started = false
	_last_frame = PackedFloat32Array()
	_concealed = 0
	_target_frames = _initial_target


func push(sequence: int, samples: PackedFloat32Array) -> void:
	if samples.is_empty():
		return
	if _started:
		var delta := VoicePacket.sequence_delta(sequence, _next_sequence)
		if absi(delta) > _reset_gap:
			# A jump this large is a reconnect, not loss.
			reset()
			_resets += 1
		elif delta < 0:
			_dropped_late += 1
			return
	if _frames.has(sequence):
		_dropped_duplicate += 1
		return
	_frames[sequence] = samples
	_evict_overflow()


func pop() -> PackedFloat32Array:
	if not _started:
		if _frames.size() < _target_frames:
			return PackedFloat32Array()
		_started = true
		_next_sequence = _lowest_buffered_sequence()

	if _frames.has(_next_sequence):
		var frame: PackedFloat32Array = _frames[_next_sequence]
		_frames.erase(_next_sequence)
		_next_sequence = VoicePacket.next_sequence(_next_sequence)
		_last_frame = frame
		_concealed = 0
		return frame

	_underruns += 1
	_concealed += 1
	_target_frames = mini(_target_frames + 1, _max_frames)
	_next_sequence = VoicePacket.next_sequence(_next_sequence)
	if _concealed > MAX_CONCEALED_FRAMES or _last_frame.is_empty():
		_started = false
		_concealed = 0
		_last_frame = PackedFloat32Array()
		return PackedFloat32Array()
	return _conceal(_concealed)


## Nothing else bounds this queue, so a sender whose clock runs fast grows it
## forever and adds mouth-to-ear latency with it. Dropping the oldest is the usual
## answer to clock skew: one 40 ms skip now and then rather than a permanent lag.
func _evict_overflow() -> void:
	while _frames.size() > _max_frames:
		var oldest := _lowest_buffered_sequence()
		_frames.erase(oldest)
		_dropped_overflow += 1
		# Playout would otherwise wait for a frame that is gone, conceal it, and
		# grow its target for a loss that never happened.
		if _started and oldest == _next_sequence:
			_next_sequence = VoicePacket.next_sequence(_next_sequence)


## Replaying the last frame under a fade sounds markedly less harsh than a hole.
func _conceal(step: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_last_frame.size())
	var span := float(MAX_CONCEALED_FRAMES)
	var start_gain := (span - float(step - 1)) / span
	var end_gain := (span - float(step)) / span
	var last_index := maxi(_last_frame.size() - 1, 1)
	for i in _last_frame.size():
		out[i] = _last_frame[i] * lerpf(start_gain, end_gain, float(i) / float(last_index))
	return out


func _lowest_buffered_sequence() -> int:
	var lowest := 0
	var seen := false
	for sequence in _frames:
		if not seen or VoicePacket.sequence_delta(sequence, lowest) < 0:
			lowest = sequence
			seen = true
	return lowest
