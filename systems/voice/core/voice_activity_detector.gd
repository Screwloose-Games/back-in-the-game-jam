class_name VoiceActivityDetector
extends RefCounted

## Decides, one frame at a time, whether the microphone is carrying speech.
##
## Opening takes a single frame so a hard consonant is never clipped, while
## closing needs both a lower threshold and a hangover so ordinary pauses between
## words do not chop the transmission.

const SILENCE_DBFS := -100.0
const LOUDNESS_FLOOR_DBFS := -60.0
const LOUDNESS_CEILING_DBFS := -6.0
const LOUDNESS_RELEASE := 0.85

var _open_dbfs := -45.0
var _hysteresis_db := 7.0
var _hangover_frames := 5
var _open := false
var _hangover_left := 0
var _loudness := 0.0
var _last_dbfs := SILENCE_DBFS


func _init(config: VoiceConfig) -> void:
	_open_dbfs = config.vad_open_dbfs
	_hysteresis_db = config.vad_hysteresis_db
	_hangover_frames = maxi(config.vad_hangover_frames(), 1)


static func rms_dbfs(frame: PackedFloat32Array) -> float:
	if frame.is_empty():
		return SILENCE_DBFS
	var total := 0.0
	for sample in frame:
		total += sample * sample
	var rms := sqrt(total / float(frame.size()))
	if rms <= 0.0:
		return SILENCE_DBFS
	return maxf(linear_to_db(rms), SILENCE_DBFS)


func set_open_dbfs(value: float) -> void:
	_open_dbfs = value


func open_dbfs() -> float:
	return _open_dbfs


func close_dbfs() -> float:
	return _open_dbfs - _hysteresis_db


func is_open() -> bool:
	return _open


## Zero to one, smoothed for a level meter rather than for the gate decision.
func loudness() -> float:
	return _loudness


func last_dbfs() -> float:
	return _last_dbfs


func reset() -> void:
	_open = false
	_hangover_left = 0
	_loudness = 0.0
	_last_dbfs = SILENCE_DBFS


func process(frame: PackedFloat32Array) -> bool:
	var dbfs := rms_dbfs(frame)
	_last_dbfs = dbfs
	_loudness = maxf(_level_from(dbfs), _loudness * LOUDNESS_RELEASE)
	if _open:
		if dbfs < close_dbfs():
			_hangover_left -= 1
			if _hangover_left <= 0:
				_open = false
		else:
			_hangover_left = _hangover_frames
	elif dbfs >= _open_dbfs:
		_open = true
		_hangover_left = _hangover_frames
	return _open


func _level_from(dbfs: float) -> float:
	var span := LOUDNESS_CEILING_DBFS - LOUDNESS_FLOOR_DBFS
	return clampf((dbfs - LOUDNESS_FLOOR_DBFS) / span, 0.0, 1.0)
