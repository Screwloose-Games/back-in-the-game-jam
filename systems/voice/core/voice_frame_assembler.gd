class_name VoiceFrameAssembler
extends RefCounted

## Turns the ragged sample stream coming off the capture bus into fixed frames.
##
## Web microphone samples are not guaranteed to sit inside plus or minus one
## (godot#118599), and an out-of-range sample makes the ADPCM encoder emit
## garbage rather than merely clipping, so folding clamps as it goes.

var _samples_per_frame := 0
var _pending := PackedFloat32Array()


func _init(samples_per_frame: int) -> void:
	_samples_per_frame = maxi(samples_per_frame, 1)


## Left channel only, deliberately, not the average of the two. A mono
## getUserMedia source whose right channel arrives silent would average to half
## amplitude, which reads as a quiet microphone rather than as a bug.
static func fold_to_mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = clampf(frames[i].x, -1.0, 1.0)
	return mono


func samples_per_frame() -> int:
	return _samples_per_frame


func pending_count() -> int:
	return _pending.size()


func reset() -> void:
	_pending = PackedFloat32Array()


func push(samples: PackedFloat32Array) -> Array[PackedFloat32Array]:
	_pending.append_array(samples)
	var complete: Array[PackedFloat32Array] = []
	var consumed := 0
	while _pending.size() - consumed >= _samples_per_frame:
		complete.append(_pending.slice(consumed, consumed + _samples_per_frame))
		consumed += _samples_per_frame
	if consumed > 0:
		_pending = _pending.slice(consumed)
	return complete
