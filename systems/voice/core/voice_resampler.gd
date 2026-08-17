class_name VoiceResampler
extends RefCounted

## Anti-aliased rate conversion from the mixer's rate down to the codec's.
##
## Plain decimation aliases badly on speech, so a windowed-sinc low-pass runs
## first. State carries across calls, so a stream can be pushed in ragged chunks.

## A Hamming window's transition band is about 3.3 / TAP_COUNT wide, so a short
## filter would eat the top of the speech band to keep the stopband clean. At the
## codec's 8 kHz this costs roughly 390k multiply-accumulates a second.
const TAP_COUNT := 49
## Cutoff as a fraction of the target rate: below Nyquist, with room to roll off.
const CUTOFF_FRACTION := 0.42

var _taps := PackedFloat32Array()
var _pending := PackedFloat32Array()
var _source_rate := 0
var _target_rate := 0
var _ratio := 1.0
var _half := TAP_COUNT / 2
var _position := 0.0
var _integer_ratio := false


func _init(source_rate: int, target_rate: int) -> void:
	_target_rate = maxi(target_rate, 1)
	_configure_rate(source_rate)
	reset()


## Re-aims at a corrected source rate without dropping the stream. Deliberately
## does not reset: the filter history and the read position are both measured in
## source samples and the window length is unchanged, so the seam does not click.
func retune(source_rate: int) -> void:
	if maxi(source_rate, 1) == _source_rate:
		return
	_configure_rate(source_rate)


func source_rate() -> int:
	return _source_rate


func target_rate() -> int:
	return _target_rate


func is_integer_ratio() -> bool:
	return _integer_ratio


func reset() -> void:
	_pending = PackedFloat32Array()
	_pending.resize(TAP_COUNT - 1)
	_pending.fill(0.0)
	_position = float(_half)


func process(samples: PackedFloat32Array) -> PackedFloat32Array:
	var buffer := _pending + samples
	var out := PackedFloat32Array()
	# Interpolation reads one filter window past the centre, so it stops a sample early.
	var last_centre := buffer.size() - 1 - _half
	if not _integer_ratio:
		last_centre -= 1
	while _position <= float(last_centre):
		var centre := int(floor(_position))
		if _integer_ratio:
			out.append(_filter_at(buffer, centre))
		else:
			var here := _filter_at(buffer, centre)
			var next := _filter_at(buffer, centre + 1)
			out.append(lerpf(here, next, _position - float(centre)))
		_position += _ratio

	var keep_from := int(floor(_position)) - _half
	if keep_from > 0:
		_pending = buffer.slice(keep_from)
		_position -= float(keep_from)
	else:
		_pending = buffer
	return out


func _configure_rate(source_rate: int) -> void:
	_source_rate = maxi(source_rate, 1)
	_ratio = float(_source_rate) / float(_target_rate)
	_integer_ratio = is_equal_approx(_ratio, roundf(_ratio))
	_taps = _build_taps(minf(CUTOFF_FRACTION * _target_rate / _source_rate, CUTOFF_FRACTION))


func _filter_at(buffer: PackedFloat32Array, centre: int) -> float:
	var accumulated := 0.0
	var start := centre - _half
	for i in TAP_COUNT:
		accumulated += _taps[i] * buffer[start + i]
	return accumulated


## Hamming-windowed sinc, normalised to unity DC gain.
func _build_taps(normalised_cutoff: float) -> PackedFloat32Array:
	var taps := PackedFloat32Array()
	taps.resize(TAP_COUNT)
	var sum := 0.0
	for i in TAP_COUNT:
		var offset := float(i - _half)
		var value := 2.0 * normalised_cutoff * _sinc(2.0 * normalised_cutoff * offset)
		value *= 0.54 - 0.46 * cos(TAU * float(i) / float(TAP_COUNT - 1))
		taps[i] = value
		sum += value
	if absf(sum) > 0.0:
		for i in TAP_COUNT:
			taps[i] /= sum
	return taps


static func _sinc(x: float) -> float:
	if absf(x) < 1e-9:
		return 1.0
	return sin(PI * x) / (PI * x)
