extends McpTestSuite

## VoiceRateEstimator: catching a driver that lies about its capture rate.
##
## The bug this exists for is a browser reporting 48000 while delivering 44100.
## Resampling by the reported ratio then plays every frame 8.8% short, which is
## heard on the far side as the speaker sounding sped up.

const REPORTED := 48000
const DELIVERED := 44100
const POLL_SECONDS := 1.0 / 60.0


func suite_name() -> String:
	return "voice_rate_estimator"


func test_a_driver_that_lies_by_a_ninth_is_measured_and_corrected() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	var corrected := _run(estimator, DELIVERED, 12.0)
	assert_eq(corrected, DELIVERED, "the measured rate should snap to 44100 exactly")
	assert_eq(estimator.applied_rate(), DELIVERED, "and be the rate it reports as applied")


func test_an_honest_driver_is_left_alone() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	assert_eq(_run(estimator, REPORTED, 20.0), 0, "no correction when nothing is wrong")
	assert_eq(estimator.corrections(), 0, "and none counted")


## Two crystals drifting apart, not a wrong rate: snapping resolves it back.
func test_a_measurement_near_the_reported_rate_resolves_back_to_it() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	assert_eq(_run(estimator, 48100, 20.0), 0, "48100 against 48000 is noise, not a lie")


func test_the_warmup_window_is_not_evidence() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	# A device still opening delivers nothing, which would measure as 0 Hz.
	var corrected := 0
	var elapsed := 0.0
	while elapsed < VoiceRateEstimator.WARMUP_SECONDS:
		corrected = maxi(corrected, estimator.observe(0, POLL_SECONDS))
		elapsed += POLL_SECONDS
	assert_eq(corrected, 0, "the opening second must not retune anything")
	assert_eq(estimator.observed_rate(), 0.0, "and no window should have closed")


func test_one_stalled_poll_discards_its_window_rather_than_skewing_it() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	_run(estimator, REPORTED, VoiceRateEstimator.WARMUP_SECONDS + 1.0)
	# A backgrounded tab: time passed, but the samples were dropped by a ring
	# buffer that overflowed, so the pair is not a measurement of anything.
	assert_eq(estimator.observe(1024, 5.0), 0, "a five second gap proves nothing")
	assert_eq(_run(estimator, REPORTED, 12.0), 0, "and must not have poisoned what follows")


func test_two_windows_must_agree_before_the_stream_is_retuned() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	var window := VoiceRateEstimator.WARMUP_SECONDS + VoiceRateEstimator.WINDOW_SECONDS
	assert_eq(_run(estimator, DELIVERED, window + 0.5), 0, "one window is not enough")
	assert_eq(estimator.corrections(), 0, "so nothing is applied yet")
	assert_eq(_run(estimator, DELIVERED, VoiceRateEstimator.WINDOW_SECONDS + 0.5), DELIVERED)


func test_a_rate_nowhere_near_a_standard_one_still_converges() -> void:
	var estimator := VoiceRateEstimator.new(REPORTED)
	assert_eq(_run(estimator, 37000, 20.0), 37000, "quantised onto the grid, not discarded")


## Feeds the estimator a steady stream at delivered_rate, in frame-sized polls,
## and returns the last correction it asked for.
func _run(estimator: VoiceRateEstimator, delivered_rate: int, seconds: float) -> int:
	var corrected := 0
	var elapsed := 0.0
	var owed := 0.0
	while elapsed < seconds:
		owed += float(delivered_rate) * POLL_SECONDS
		var count := int(owed)
		owed -= float(count)
		corrected = maxi(corrected, estimator.observe(count, POLL_SECONDS))
		elapsed += POLL_SECONDS
	return corrected
