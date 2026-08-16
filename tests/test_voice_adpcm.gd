extends McpTestSuite

## VoiceAdpcm: that a frame really does decode without the frames before it.
##
## This is the property the whole packet format exists to protect. ADPCM is
## predictive, the transport drops packets on purpose, and a decoder whose state
## has drifted from the encoder's produces garbage from that point on - silently,
## and only over an unreliable link, which is exactly where it is hardest to see.
## So the suite decodes frames in isolation and asserts the result is still good,
## rather than trusting that the re-seed was wired up.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")

const SAMPLE_RATE := 8000
const SAMPLES_PER_FRAME := 320
## IMA ADPCM on smooth speech-band content comfortably clears this.
const MIN_SNR_DB := 15.0


func suite_name() -> String:
	return "voice_adpcm"


func test_round_trip_keeps_the_signal_well_above_the_noise() -> void:
	var original := Fixtures.tone(SAMPLES_PER_FRAME, 440.0, SAMPLE_RATE, 0.5)
	var decoded := _round_trip(original)
	var snr: float = Fixtures.snr_db(original, decoded)
	assert_gt(snr, MIN_SNR_DB, "round trip SNR was %.1f dB" % snr)


## Compared as int16 rather than as floats: the decoder writes into a
## PackedFloat32Array, so an exact float64 comparison could never pass however
## right the codec was. Quantised, the round trip is genuinely lossless here.
func test_the_first_sample_survives_exactly() -> void:
	var original := Fixtures.tone(SAMPLES_PER_FRAME, 440.0, SAMPLE_RATE, 0.5, 0.7)
	var decoded := _round_trip(original)
	assert_eq(
		VoiceAdpcm.to_pcm16(decoded)[0],
		VoiceAdpcm.to_pcm16(original)[0],
		"the header predictor must reproduce sample zero, not approximate it"
	)


func test_payload_is_one_byte_for_every_two_coded_samples() -> void:
	var encoded := VoiceAdpcm.encode(Fixtures.tone(SAMPLES_PER_FRAME, 440.0, SAMPLE_RATE))
	var payload: PackedByteArray = encoded["data"]
	assert_eq(payload.size(), 160, "320 samples is 319 codes, which packs into 160 bytes")


func test_a_middle_frame_decodes_without_the_frames_before_it() -> void:
	# One continuous tone cut into three frames. Frame 1 starts mid-cycle, so if the
	# decoder needed its predecessors this is where it would show.
	var whole := Fixtures.tone(SAMPLES_PER_FRAME * 3, 700.0, SAMPLE_RATE, 0.6)
	var middle := whole.slice(SAMPLES_PER_FRAME, SAMPLES_PER_FRAME * 2)
	var decoded := _round_trip(middle)
	var snr: float = Fixtures.snr_db(middle, decoded)
	assert_gt(snr, MIN_SNR_DB, "frame decoded alone scored only %.1f dB" % snr)


func test_a_loud_frame_starts_from_a_larger_step() -> void:
	var quiet := VoiceAdpcm.to_pcm16(Fixtures.tone(SAMPLES_PER_FRAME, 440.0, SAMPLE_RATE, 0.01))
	var loud := VoiceAdpcm.to_pcm16(Fixtures.tone(SAMPLES_PER_FRAME, 440.0, SAMPLE_RATE, 0.9))
	assert_gt(
		VoiceAdpcm.initial_step_index(loud),
		VoiceAdpcm.initial_step_index(quiet),
		"the step index is seeded from the frame's own opening amplitude"
	)


func test_silence_round_trips_to_silence() -> void:
	var decoded := _round_trip(Fixtures.constant(SAMPLES_PER_FRAME, 0.0))
	assert_true(Fixtures.peak(decoded) < 0.01, "a silent frame must not decode into noise")


func test_out_of_range_input_clamps_instead_of_wrapping() -> void:
	# Web capture is not guaranteed to stay inside plus or minus one (godot#118599).
	var hot := Fixtures.constant(SAMPLES_PER_FRAME, 4.0)
	var pcm := VoiceAdpcm.to_pcm16(hot)
	assert_eq(pcm[0], 32767, "an over-range sample must saturate, not wrap to a negative")
	assert_true(Fixtures.peak(_round_trip(hot)) <= 1.0, "decoded audio must stay in range")


func test_a_short_payload_decodes_to_nothing_rather_than_reading_past_the_end() -> void:
	var truncated := PackedByteArray()
	truncated.resize(4)
	var decoded := VoiceAdpcm.decode(truncated, 0, 0, SAMPLES_PER_FRAME)
	assert_true(decoded.is_empty(), "a truncated payload must be refused, not partly decoded")


func _round_trip(samples: PackedFloat32Array) -> PackedFloat32Array:
	var encoded := VoiceAdpcm.encode(samples)
	return VoiceAdpcm.decode(
		encoded["data"], encoded["predictor"], encoded["step_index"], samples.size()
	)
