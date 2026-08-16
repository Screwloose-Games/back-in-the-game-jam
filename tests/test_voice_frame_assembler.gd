extends McpTestSuite

## VoiceFrameAssembler: clamping at capture, and framing without losing a sample.
##
## The clamp matters more than it looks. Out-of-range web capture (godot#118599)
## reaching the ADPCM encoder does not clip, it wraps to the opposite sign, which
## sounds like a burst of noise rather than like a loud voice.
##
## The framing is asserted by reassembling the frames and comparing against the
## input, because an off-by-one in the drain would still produce correctly sized
## frames while quietly repeating or eating samples at every boundary.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")

const SAMPLES_PER_FRAME := 320


func suite_name() -> String:
	return "voice_frame_assembler"


## Pinned rather than assumed: averaging would halve a mono source whose right
## channel arrives silent, and that reads as a quiet microphone, not as a bug.
func test_folding_takes_the_left_channel_and_ignores_the_right() -> void:
	var frames := PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.25, 1.0)])
	var mono := VoiceFrameAssembler.fold_to_mono(frames)
	assert_true(absf(mono[0] - 0.5) < 1e-6, "a silent right channel must not halve the level")
	assert_true(absf(mono[1] - 0.25) < 1e-6, "and a loud one must not raise it")


func test_out_of_range_samples_are_clamped_not_wrapped() -> void:
	var frames := PackedVector2Array([Vector2(4.0, 0.0), Vector2(-4.0, 0.0)])
	var mono := VoiceFrameAssembler.fold_to_mono(frames)
	assert_true(absf(mono[0] - 1.0) < 1e-6, "a hot sample saturates at one")
	assert_true(absf(mono[1] + 1.0) < 1e-6, "and at minus one on the way down")


func test_nothing_comes_out_until_a_whole_frame_is_in() -> void:
	var assembler := VoiceFrameAssembler.new(SAMPLES_PER_FRAME)
	assert_eq(assembler.push(Fixtures.constant(319, 0.5)).size(), 0, "319 samples is not a frame")
	assert_eq(assembler.pending_count(), 319, "the partial frame is held, not dropped")
	assert_eq(assembler.push(Fixtures.constant(1, 0.5)).size(), 1, "the 320th completes it")


func test_a_large_push_yields_several_frames_at_once() -> void:
	var assembler := VoiceFrameAssembler.new(SAMPLES_PER_FRAME)
	var complete := assembler.push(Fixtures.constant(SAMPLES_PER_FRAME * 3 + 7, 0.5))
	assert_eq(complete.size(), 3, "three whole frames")
	assert_eq(assembler.pending_count(), 7, "and the remainder waits")


func test_ragged_pushes_lose_and_repeat_nothing() -> void:
	var assembler := VoiceFrameAssembler.new(SAMPLES_PER_FRAME)
	var source := Fixtures.tone(SAMPLES_PER_FRAME * 4, 300.0, 8000, 0.9)
	var reassembled := PackedFloat32Array()
	var offset := 0
	for size in [1, 17, 640, 3, 511, 200, 1000]:
		var chunk := source.slice(offset, mini(offset + int(size), source.size()))
		offset += chunk.size()
		for frame in assembler.push(chunk):
			reassembled.append_array(frame)

	assert_gt(reassembled.size(), 0, "some frames should have completed")
	var matched := true
	for i in reassembled.size():
		if absf(reassembled[i] - source[i]) > 1e-6:
			matched = false
			break
	assert_true(matched, "the frame stream must be the input stream, in order")


func test_reset_drops_the_partial_frame() -> void:
	var assembler := VoiceFrameAssembler.new(SAMPLES_PER_FRAME)
	assembler.push(Fixtures.constant(100, 0.5))
	assembler.reset()
	assert_eq(assembler.pending_count(), 0, "a restarted capture must not splice onto stale audio")
