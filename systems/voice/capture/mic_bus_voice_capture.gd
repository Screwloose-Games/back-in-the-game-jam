class_name MicBusVoiceCapture
extends VoiceCapture

## Reads the microphone off a muted bus carrying an AudioEffectCapture.
##
## The fallback path (spec 4.2). The bus is muted rather than quiet so nobody hears
## themselves; volume and mute are applied after effects run, so the capture still
## sees full amplitude. That is also this path's limitation: the effect reads what
## the AudioStreamPlayer mixed, so the monitor cannot be silenced at the source
## without starving the encoder. GodotVoiceCapture reads upstream of all of it and
## is preferred wherever the driver supports it.
##
## The caller owns the AudioStreamPlayer that opens the microphone, because opening
## it is a consent decision rather than a plumbing one.

const ENABLE_INPUT_SETTING := "audio/driver/enable_input"

var _bus_name := &"VoiceCapture"
var _effect: AudioEffectCapture
var _resampler: VoiceResampler
var _assembler: VoiceFrameAssembler
var _reason := ""
var _active := false
var _source_rate := 0


func _init(config: VoiceConfig, bus_name := &"VoiceCapture") -> void:
	super(config)
	_bus_name = bus_name


func start() -> Error:
	_reason = ""
	if not bool(ProjectSettings.get_setting(ENABLE_INPUT_SETTING, false)):
		return _fail("Microphone input is disabled in the project settings.")

	var bus_index := AudioServer.get_bus_index(_bus_name)
	if bus_index < 0:
		return _fail("The %s audio bus is missing." % _bus_name)

	_effect = _find_capture_effect(bus_index)
	if _effect == null:
		return _fail("The %s bus has no AudioEffectCapture on it." % _bus_name)

	# Asserted here, not just in the layout resource: the editor's Audio panel
	# rewrites default_bus_layout.tres wholesale, so one accidental save would
	# otherwise put the microphone back on the speakers.
	AudioServer.set_bus_mute(bus_index, true)

	_source_rate = int(AudioServer.get_mix_rate())
	_resampler = VoiceResampler.new(_source_rate, _config.sample_rate)
	_assembler = VoiceFrameAssembler.new(_config.samples_per_frame())
	_effect.clear_buffer()
	_active = true
	return OK


func stop() -> void:
	_active = false
	_effect = null
	_resampler = null
	_assembler = null


func is_active() -> bool:
	return _active


func unavailable_reason() -> String:
	return _reason


func source_rate() -> int:
	return _source_rate


## True when the driver's input and output clocks disagree, which makes
## AudioStreamPlaybackMicrophone pitch-shift everything it captures.
func has_rate_mismatch() -> bool:
	if not AudioServer.has_method("get_input_mix_rate"):
		return false
	var input_rate := int(AudioServer.call("get_input_mix_rate"))
	return input_rate > 0 and input_rate != _source_rate


func poll() -> Array[PackedFloat32Array]:
	if not _active or _effect == null:
		return []
	var available := _effect.get_frames_available()
	if available <= 0:
		return []
	var mono := VoiceFrameAssembler.fold_to_mono(_effect.get_buffer(available))
	return _assembler.push(_resampler.process(mono))


func _find_capture_effect(bus_index: int) -> AudioEffectCapture:
	for i in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, i) as AudioEffectCapture
		if effect != null:
			return effect
	return null


func _fail(reason: String) -> Error:
	_reason = reason
	_active = false
	return ERR_UNAVAILABLE
