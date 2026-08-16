extends McpTestSuite

## VoiceActivityDetector: the asymmetry between opening and closing the gate.
##
## Both thresholds and the hangover exist for the same reason, which is that the
## two mistakes are not equally bad. Opening late clips the front of a word and is
## immediately obvious; closing late sends a few frames of room tone and costs
## nothing. So the gate opens on the first frame that crosses, and closes only
## after a lower threshold has been held for the whole hangover.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")

const SAMPLE_RATE := 8000
const SAMPLES_PER_FRAME := 320
## ceil(200 ms / 40 ms per frame).
const HANGOVER_FRAMES := 5


func suite_name() -> String:
	return "voice_activity_detector"


func test_silence_never_opens_the_gate() -> void:
	var detector := _detector()
	for i in 20:
		detector.process(Fixtures.constant(SAMPLES_PER_FRAME, 0.0))
	assert_false(detector.is_open(), "a silent room must not transmit")


func test_speech_opens_the_gate_on_its_very_first_frame() -> void:
	var detector := _detector()
	assert_true(detector.process(_at_dbfs(-20.0)), "onset must not wait for a second frame")


func test_a_level_between_the_thresholds_holds_the_gate_where_it_was() -> void:
	var quiet := _at_dbfs(-48.0)
	var closed := _detector()
	closed.process(quiet)
	assert_false(closed.is_open(), "below the open threshold, a closed gate stays closed")

	var opened := _detector()
	opened.process(_at_dbfs(-20.0))
	opened.process(quiet)
	assert_true(opened.is_open(), "above the close threshold, an open gate stays open")


func test_the_gate_closes_only_after_the_whole_hangover() -> void:
	var detector := _detector()
	detector.process(_at_dbfs(-20.0))
	var silence := Fixtures.constant(SAMPLES_PER_FRAME, 0.0)
	for i in HANGOVER_FRAMES - 1:
		detector.process(silence)
	assert_true(
		detector.is_open(), "still inside the hangover after %d frames" % (HANGOVER_FRAMES - 1)
	)
	detector.process(silence)
	assert_false(detector.is_open(), "and closed once it runs out")


func test_moving_the_threshold_moves_both_ends_together() -> void:
	var detector := _detector()
	detector.set_open_dbfs(-30.0)
	assert_eq(detector.open_dbfs(), -30.0, "the slider sets the open threshold")
	assert_eq(detector.close_dbfs(), -37.0, "and the close threshold follows it down")


func test_loudness_rises_with_level_and_decays_afterwards() -> void:
	var detector := _detector()
	detector.process(_at_dbfs(-12.0))
	var loud := detector.loudness()
	assert_gt(loud, 0.5, "a loud frame should read high on the meter, got %.2f" % loud)
	detector.process(Fixtures.constant(SAMPLES_PER_FRAME, 0.0))
	assert_true(detector.loudness() < loud, "the meter must fall back rather than stick")
	assert_gt(detector.loudness(), 0.0, "and it must fall smoothly, not snap to zero")


func test_an_empty_frame_reports_the_floor_rather_than_negative_infinity() -> void:
	assert_eq(
		VoiceActivityDetector.rms_dbfs(PackedFloat32Array()),
		VoiceActivityDetector.SILENCE_DBFS,
		"a floor keeps the meter arithmetic finite"
	)


func _detector() -> VoiceActivityDetector:
	return VoiceActivityDetector.new(Fixtures.config(SAMPLE_RATE, 40))


## A sine whose RMS lands on the requested dBFS.
func _at_dbfs(dbfs: float) -> PackedFloat32Array:
	return Fixtures.tone(SAMPLES_PER_FRAME, 400.0, SAMPLE_RATE, db_to_linear(dbfs) * sqrt(2.0))
