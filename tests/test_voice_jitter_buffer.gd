extends McpTestSuite

## VoiceJitterBuffer: the four things an unreliable channel does, and the wrap.
##
## Late, duplicated, reordered and missing are all normal here rather than
## exceptional, so each has its own test. The wrap tests matter most: 65535 to 0
## is a step forward of one, and a buffer that reads it as a jump backwards of
## 65535 would treat every wrap as a reconnect and reset itself mid-sentence,
## roughly once every 44 minutes of continuous speech.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")

const SAMPLES_PER_FRAME := 320
const TARGET := 3
const MAX_DEPTH := 6


func suite_name() -> String:
	return "voice_jitter_buffer"


func test_a_playout_frame_clears_the_engine_resampler_floor() -> void:
	# Godot pulls 128 source frames per block and zero-fills below that.
	var config: VoiceConfig = Fixtures.config()
	assert_true(
		config.samples_per_frame() >= VoiceConfig.JITTER_MIN_SAMPLES,
		"a frame shorter than 128 samples would stutter however well buffered"
	)


func test_nothing_plays_until_the_target_depth_is_reached() -> void:
	var buffer := _buffer()
	buffer.push(10, _frame(0.5))
	buffer.push(11, _frame(0.5))
	assert_true(buffer.pop().is_empty(), "two frames is not enough of a cushion")
	buffer.push(12, _frame(0.5))
	assert_eq(buffer.pop().size(), SAMPLES_PER_FRAME, "the third frame starts playout")


func test_frames_are_replayed_in_sequence_order_not_arrival_order() -> void:
	var buffer := _buffer()
	buffer.push(10, _frame(0.1))
	buffer.push(12, _frame(0.3))
	buffer.push(11, _frame(0.2))
	assert_true(absf(buffer.pop()[0] - 0.1) < 1e-6, "first")
	assert_true(absf(buffer.pop()[0] - 0.2) < 1e-6, "the reordered one lands in the middle")
	assert_true(absf(buffer.pop()[0] - 0.3) < 1e-6, "last")


func test_a_duplicate_is_counted_and_discarded() -> void:
	var buffer := _buffer()
	buffer.push(10, _frame(0.1))
	buffer.push(10, _frame(0.9))
	assert_eq(buffer.depth(), 1, "the second copy must not queue behind the first")
	assert_eq(buffer.dropped_duplicate(), 1, "and it should be visible as a statistic")


func test_a_frame_that_arrives_after_its_slot_is_discarded() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	buffer.pop()
	buffer.push(10, _frame(0.9))
	assert_eq(buffer.dropped_late(), 1, "retransmitted voice always arrives too late to use")


func test_the_sequence_wrap_is_not_mistaken_for_a_reconnect() -> void:
	var buffer := _buffer()
	buffer.push(65534, _frame(0.1))
	buffer.push(65535, _frame(0.2))
	buffer.push(0, _frame(0.3))
	assert_true(absf(buffer.pop()[0] - 0.1) < 1e-6, "65534")
	assert_true(absf(buffer.pop()[0] - 0.2) < 1e-6, "65535")
	assert_true(absf(buffer.pop()[0] - 0.3) < 1e-6, "0 follows 65535, it does not precede it")
	assert_eq(buffer.resets(), 0, "and no reset should have fired")


func test_a_large_sequence_jump_resets_instead_of_stalling() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	buffer.pop()
	buffer.push(500, _frame(0.4))
	assert_eq(buffer.resets(), 1, "a jump that big is a reconnect, not loss")
	assert_false(buffer.is_active(), "playout re-primes rather than skipping 489 frames")
	assert_eq(buffer.depth(), 1, "and the new frame is kept")


func test_an_underrun_fades_the_last_frame_rather_than_cutting_to_silence() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	for i in TARGET:
		buffer.pop()
	var concealed := buffer.pop()
	assert_eq(concealed.size(), SAMPLES_PER_FRAME, "a hole is filled, not left open")
	assert_gt(concealed[0], concealed[concealed.size() - 1], "and it fades across the frame")
	assert_eq(buffer.underruns(), 1, "counted")


func test_the_speaker_goes_inactive_after_three_concealed_frames() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	for i in TARGET:
		buffer.pop()
	for i in VoiceJitterBuffer.MAX_CONCEALED_FRAMES:
		assert_false(buffer.pop().is_empty(), "concealment %d should still produce audio" % i)
	assert_true(buffer.pop().is_empty(), "then it gives up")
	assert_false(buffer.is_active(), "and reports the speaker as gone")


func test_persistent_underrun_grows_the_target_depth_within_its_cap() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	for i in TARGET:
		buffer.pop()
	for i in 12:
		buffer.pop()
	assert_gt(buffer.target_frames(), TARGET, "a bad link should buy itself more cushion")
	assert_true(buffer.target_frames() <= 6, "but not without limit")


## A sender whose clock runs fast used to grow this queue without limit, adding
## mouth-to-ear latency for as long as the call lasted.
func test_a_sender_running_fast_is_capped_rather_than_queued_forever() -> void:
	var buffer := _buffer()
	for i in 20:
		buffer.push(100 + i, _frame(0.5))
	assert_eq(buffer.depth(), MAX_DEPTH, "the queue stops at its configured ceiling")
	assert_eq(buffer.dropped_overflow(), 20 - MAX_DEPTH, "and the overflow is visible")


func test_the_oldest_frame_is_the_one_evicted() -> void:
	var buffer := _buffer()
	for i in MAX_DEPTH:
		buffer.push(100 + i, _frame(float(i) / 10.0))
	buffer.push(100 + MAX_DEPTH, _frame(0.9))
	assert_true(absf(buffer.pop()[0] - 0.1) < 1e-6, "sequence 100 went, so 101 plays first")
	assert_true(absf(buffer.pop()[0] - 0.2) < 1e-6, "and the rest still play in order")


func test_evicting_the_awaited_frame_does_not_count_as_an_underrun() -> void:
	var buffer := _buffer()
	_prime(buffer, 10)
	buffer.pop()
	# Contiguous, as a fast sender really arrives: no frame is lost, they simply
	# turn up faster than playout consumes them.
	for i in MAX_DEPTH + 1:
		buffer.push(13 + i, _frame(0.5))
	assert_eq(buffer.depth(), MAX_DEPTH, "capped")
	assert_eq(buffer.pop().size(), SAMPLES_PER_FRAME, "playout skips to what is really there")
	assert_eq(buffer.underruns(), 0, "a frame this end threw away is not a lost frame")


func _buffer() -> VoiceJitterBuffer:
	return VoiceJitterBuffer.new(Fixtures.config())


func _frame(value: float) -> PackedFloat32Array:
	return Fixtures.constant(SAMPLES_PER_FRAME, value)


func _prime(buffer: VoiceJitterBuffer, first_sequence: int) -> void:
	for i in TARGET:
		buffer.push(first_sequence + i, _frame(0.5))
