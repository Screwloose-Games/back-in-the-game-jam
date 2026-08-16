extends McpTestSuite

## The synthesised radio keying clicks.
##
## Pure data, unlike the bus suite: these assert the samples themselves, because
## a burst that came out silent, clipped or endless would still be a valid
## AudioStreamWAV and would still play, just wrong.

const BYTES_PER_SAMPLE := 2


func suite_name() -> String:
	return "voice_squelch"


func test_both_bursts_are_mono_sixteen_bit() -> void:
	for stream in [VoiceSquelch.key_on(), VoiceSquelch.key_off()]:
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "16-bit is what _burst encodes")
		assert_false(stream.stereo, "a keying click has no stereo image of its own")
		assert_eq(stream.mix_rate, VoiceSquelch.MIX_RATE, "mix rate must match the written rate")


func test_each_burst_is_as_long_as_it_claims() -> void:
	var expected_on := int((VoiceSquelch.MIX_RATE * VoiceSquelch.KEY_ON_MS) / 1000.0)
	var expected_off := int((VoiceSquelch.MIX_RATE * VoiceSquelch.KEY_OFF_MS) / 1000.0)
	assert_eq(VoiceSquelch.key_on().data.size(), expected_on * BYTES_PER_SAMPLE, "key-on length")
	assert_eq(VoiceSquelch.key_off().data.size(), expected_off * BYTES_PER_SAMPLE, "key-off length")


func test_releasing_is_the_longer_of_the_two() -> void:
	assert_gt(
		VoiceSquelch.key_off().data.size(),
		VoiceSquelch.key_on().data.size(),
		"keying on is the harder, shorter click",
	)


func test_a_burst_is_audible_without_clipping() -> void:
	var peak := _peak(VoiceSquelch.key_on())
	assert_gt(peak, 0.05, "a click nobody can hear is not a click, peak %.3f" % peak)
	assert_true(peak <= 1.0, "samples must stay inside the format, peak %.3f" % peak)


## The envelope is the difference between a click and a burst of hiss.
func test_a_burst_decays_to_near_silence() -> void:
	var samples := _samples(VoiceSquelch.key_off())
	var head := _window_peak(samples, 0, samples.size() / 4)
	var tail := _window_peak(samples, (samples.size() * 3) / 4, samples.size())
	assert_gt(
		head, tail * 4.0, "the tail must fall well below the attack, %.4f vs %.4f" % [head, tail]
	)


## Seeded on purpose: an unseeded burst would differ per machine, so a report of
## "the click sounds wrong" could not be reproduced anywhere else.
func test_the_bursts_are_deterministic() -> void:
	assert_eq(VoiceSquelch.key_on().data, VoiceSquelch.key_on().data, "key-on must be repeatable")
	assert_ne(VoiceSquelch.key_on().data, VoiceSquelch.key_off().data, "the two clicks must differ")


func _samples(stream: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := stream.data.size() / BYTES_PER_SAMPLE
	out.resize(count)
	for i in count:
		out[i] = float(stream.data.decode_s16(i * BYTES_PER_SAMPLE)) / 32767.0
	return out


func _peak(stream: AudioStreamWAV) -> float:
	var samples := _samples(stream)
	return _window_peak(samples, 0, samples.size())


func _window_peak(samples: PackedFloat32Array, from: int, to: int) -> float:
	var peak := 0.0
	for i in range(from, mini(to, samples.size())):
		peak = maxf(peak, absf(samples[i]))
	return peak
