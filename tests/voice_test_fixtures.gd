extends RefCounted

## Signal generators shared by the voice suites.
##
## Deliberately not named test_*, so the runner's scan skips it rather than trying
## to load it as a suite.


static func config(sample_rate := 8000, frame_ms := 40) -> VoiceConfig:
	var built := VoiceConfig.new()
	built.sample_rate = sample_rate
	built.frame_ms = frame_ms
	return built


static func tone(
	count: int, frequency: float, rate: int, amplitude := 0.5, phase := 0.0
) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = amplitude * sin(TAU * frequency * float(i) / float(rate) + phase)
	return samples


static func constant(count: int, value: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	samples.fill(value)
	return samples


static func stereo(samples: PackedFloat32Array) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		frames[i] = Vector2(samples[i], samples[i])
	return frames


static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += sample * sample
	return sqrt(total / float(samples.size()))


static func peak(samples: PackedFloat32Array) -> float:
	var highest := 0.0
	for sample in samples:
		highest = maxf(highest, absf(sample))
	return highest


## Signal-to-noise in dB, treating reference as the truth and actual as truth plus error.
static func snr_db(reference: PackedFloat32Array, actual: PackedFloat32Array) -> float:
	var count := mini(reference.size(), actual.size())
	if count == 0:
		return -INF
	var signal_power := 0.0
	var noise_power := 0.0
	for i in count:
		signal_power += reference[i] * reference[i]
		var error := actual[i] - reference[i]
		noise_power += error * error
	if noise_power <= 0.0:
		return INF
	return 10.0 * log(signal_power / noise_power) / log(10.0)
