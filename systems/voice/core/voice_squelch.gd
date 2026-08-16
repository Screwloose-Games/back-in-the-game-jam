class_name VoiceSquelch
extends RefCounted

## The static bursts a radio makes when someone keys on and off.
##
## Synthesised rather than shipped as assets: they are a few milliseconds of
## shaped noise, and generating them keeps the sound in the same file as the
## numbers that shape it. Seeded, so every player hears the same two clicks.

const MIX_RATE := 16000
## Keying on is a shorter, harder click than releasing, which trails off.
const KEY_ON_MS := 45
const KEY_OFF_MS := 80
const KEY_ON_DECAY := 55.0
const KEY_OFF_DECAY := 28.0
const KEY_ON_SEED := 20260816
const KEY_OFF_SEED := 20260817
const PEAK := 0.35


static func key_on() -> AudioStreamWAV:
	return _burst(KEY_ON_MS, KEY_ON_DECAY, KEY_ON_SEED)


static func key_off() -> AudioStreamWAV:
	return _burst(KEY_OFF_MS, KEY_OFF_DECAY, KEY_OFF_SEED)


## Exponentially decayed white noise. The bus's own band-pass does the rest of
## the shaping, so this deliberately stays broadband here.
static func _burst(duration_ms: int, decay: float, seed_value: int) -> AudioStreamWAV:
	var count := int((MIX_RATE * duration_ms) / 1000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var seconds := float(i) / float(MIX_RATE)
		# A short fade in as well, or the first sample is a step that clicks twice.
		var attack := minf(seconds * 400.0, 1.0)
		var envelope := attack * exp(-decay * seconds)
		var sample := rng.randf_range(-1.0, 1.0) * envelope * PEAK
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
