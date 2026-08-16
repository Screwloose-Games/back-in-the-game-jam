extends McpTestSuite

## VoiceResampler: frame arithmetic, and that the anti-alias filter is really there.
##
## Taking every sixth sample would pass the frame-count tests in this file and
## still sound wrong, because everything above 4 kHz would fold back down into the
## middle of the speech band. test_content_above_the_codec_band_is_removed is the
## one that can tell the two apart: a 10 kHz tone decimated without a filter comes
## out at 2 kHz and full strength.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")

const MIXER_RATE := 48000
const AWKWARD_RATE := 44100
const CODEC_RATE := 8000
const FRAME_INPUT := 1920
const FRAME_OUTPUT := 320


func suite_name() -> String:
	return "voice_resampler"


func test_a_whole_frame_of_input_makes_exactly_one_frame_of_output() -> void:
	var resampler := VoiceResampler.new(MIXER_RATE, CODEC_RATE)
	for pass_index in 3:
		var out := resampler.process(Fixtures.tone(FRAME_INPUT, 300.0, MIXER_RATE))
		assert_eq(
			out.size(), FRAME_OUTPUT, "pass %d produced %d samples" % [pass_index, out.size()]
		)


func test_the_six_to_one_ratio_takes_the_integer_path() -> void:
	assert_true(VoiceResampler.new(MIXER_RATE, CODEC_RATE).is_integer_ratio(), "48000 is 6 x 8000")
	assert_false(
		VoiceResampler.new(AWKWARD_RATE, CODEC_RATE).is_integer_ratio(), "44100 is not a multiple"
	)


## A browser or a driver may hand us 44100 whatever the project setting asks for.
func test_a_fractional_ratio_does_not_drift_over_a_second() -> void:
	var resampler := VoiceResampler.new(AWKWARD_RATE, CODEC_RATE)
	var produced := 0
	for chunk in 100:
		produced += resampler.process(Fixtures.tone(441, 300.0, AWKWARD_RATE)).size()
	assert_true(
		absi(produced - CODEC_RATE) <= 5,
		"a second of 44100 should make about 8000 samples, got %d" % produced
	)


func test_ragged_chunk_sizes_still_total_correctly() -> void:
	var resampler := VoiceResampler.new(MIXER_RATE, CODEC_RATE)
	var sizes := [17, 512, 3, 2048, 900, 1440]
	var pushed := 0
	var produced := 0
	for size in sizes:
		pushed += int(size)
		produced += resampler.process(Fixtures.tone(int(size), 300.0, MIXER_RATE)).size()
	assert_true(
		absi(produced - pushed / 6) <= 1, "%d input samples produced %d output" % [pushed, produced]
	)


func test_speech_band_content_passes_through() -> void:
	var resampler := VoiceResampler.new(MIXER_RATE, CODEC_RATE)
	var input := Fixtures.tone(FRAME_INPUT * 5, 1000.0, MIXER_RATE, 0.5)
	var out := resampler.process(input)
	var ratio: float = Fixtures.rms(out) / Fixtures.rms(input)
	assert_gt(ratio, 0.85, "a 1 kHz tone lost too much: ratio %.3f" % ratio)


func test_content_above_the_codec_band_is_removed() -> void:
	var resampler := VoiceResampler.new(MIXER_RATE, CODEC_RATE)
	var input := Fixtures.tone(FRAME_INPUT * 5, 10000.0, MIXER_RATE, 0.5)
	var out := resampler.process(input)
	var ratio: float = Fixtures.rms(out) / Fixtures.rms(input)
	assert_true(ratio < 0.05, "10 kHz should be gone, not folded down to 2 kHz: ratio %.3f" % ratio)


func test_the_filter_has_unity_gain() -> void:
	var resampler := VoiceResampler.new(MIXER_RATE, CODEC_RATE)
	resampler.process(Fixtures.constant(FRAME_INPUT, 0.5))
	var settled := resampler.process(Fixtures.constant(FRAME_INPUT, 0.5))
	assert_true(
		absf(Fixtures.rms(settled) - 0.5) < 0.01,
		"a steady 0.5 must come out at 0.5, got %.4f" % Fixtures.rms(settled)
	)
