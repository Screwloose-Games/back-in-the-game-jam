class_name GodotVoiceCapture
extends VoiceCapture

## Reads the microphone straight off the audio driver's input buffer.
##
## AudioServer.get_input_frames() sits upstream of both the AudioStreamPlayer's
## volume and the bus effect chain, so the monitor path can be silenced outright
## without starving capture. An AudioEffectCapture on the same bus cannot do that:
## it reads the signal the player already mixed, so silencing what the player
## hears and feeding the encoder are the same knob.

const ENABLE_INPUT_SETTING := "audio/driver/enable_input"
const AVAILABLE_METHOD := "get_input_frames_available"
const FRAMES_METHOD := "get_input_frames"
const INPUT_RATE_METHOD := "get_input_mix_rate"

var _resampler: VoiceResampler
var _assembler: VoiceFrameAssembler
var _reason := ""
var _active := false
var _source_rate := 0
var _last_peak := 0.0


## The device is opened by something else playing an AudioStreamMicrophone; this
## only reads what that opened. Without it the input buffer stays empty forever.
func start() -> Error:
	_reason = ""
	if not bool(ProjectSettings.get_setting(ENABLE_INPUT_SETTING, false)):
		return _fail("Microphone input is disabled in the project settings.")
	if not AudioServer.has_method(AVAILABLE_METHOD) or not AudioServer.has_method(FRAMES_METHOD):
		return _fail("This engine build cannot read the microphone input buffer.")

	_source_rate = _resolve_source_rate()
	_resampler = VoiceResampler.new(_source_rate, _config.sample_rate)
	_assembler = VoiceFrameAssembler.new(_config.samples_per_frame())
	_last_peak = 0.0
	_discard_backlog()
	_active = true
	return OK


func stop() -> void:
	_active = false
	_resampler = null
	_assembler = null
	_last_peak = 0.0


func is_active() -> bool:
	return _active


func unavailable_reason() -> String:
	return _reason


func source_rate() -> int:
	return _source_rate


## Frames arrive at the input clock and are resampled from it, so unlike the bus
## path there is no rate to disagree with.
func has_rate_mismatch() -> bool:
	return false


func last_peak() -> float:
	return _last_peak


func poll() -> Array[PackedFloat32Array]:
	if not _active:
		return []
	var available := int(AudioServer.call(AVAILABLE_METHOD))
	if available <= 0:
		return []
	var frames: PackedVector2Array = AudioServer.call(FRAMES_METHOD, available)
	if frames.is_empty():
		return []
	var mono := VoiceFrameAssembler.fold_to_mono(frames)
	_last_peak = _peak_of(mono)
	return _assembler.push(_resampler.process(mono))


static func _peak_of(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	return peak


func _resolve_source_rate() -> int:
	if AudioServer.has_method(INPUT_RATE_METHOD):
		var rate := int(AudioServer.call(INPUT_RATE_METHOD))
		if rate > 0:
			return rate
	return int(AudioServer.get_mix_rate())


## The driver fills while the device is opening, so the first poll would otherwise
## hand the encoder a backlog that arrives as one late burst.
func _discard_backlog() -> void:
	var available := int(AudioServer.call(AVAILABLE_METHOD))
	if available > 0:
		AudioServer.call(FRAMES_METHOD, available)


func _fail(reason: String) -> Error:
	_reason = reason
	_active = false
	return ERR_UNAVAILABLE
