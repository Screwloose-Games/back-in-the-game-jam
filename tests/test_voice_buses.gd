extends McpTestSuite

## The voice bus layout, asserted against the live AudioServer.
##
## This is the one voice suite that is not pure data, and it earns the exception:
## a mis-shaped bus layout is the single failure in this feature that can silence
## the entire game rather than just the voice (spec section 14.1), and it is
## invisible until someone notices the music stopped.
##
## Three specific traps are pinned here. Sends must point at a lower bus index,
## because AudioServer mixes from the highest index down and a send to a higher
## one is silently rerouted to Master. The low-pass filters must be distinct
## objects, or both speakers share one cutoff and occlusion appears to work for
## exactly one player. And AudioEffectCapture must sit ahead of the amplifier
## that silences the bus, or capture reads the attenuated signal instead.

const VOICE_SLOT_BUSES := ["Voice_0", "Voice_1"]


func suite_name() -> String:
	return "voice_buses"


func test_every_bus_the_voice_code_names_exists() -> void:
	for bus_name in ["Master", "SFX", "Music", "Ambient", "Dialogue", "VoiceChat", "VoiceCapture"]:
		assert_gt(AudioServer.get_bus_index(bus_name) + 1, 0, "missing bus: %s" % bus_name)
	for bus_name in VOICE_SLOT_BUSES:
		assert_gt(AudioServer.get_bus_index(bus_name) + 1, 0, "missing speaker slot: %s" % bus_name)


func test_master_is_still_the_first_bus() -> void:
	assert_eq(AudioServer.get_bus_index("Master"), 0, "Master must stay at index 0")


func test_speaker_slots_send_into_the_shared_voice_bus() -> void:
	var parent := AudioServer.get_bus_index("VoiceChat")
	for bus_name in VOICE_SLOT_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		assert_eq(String(AudioServer.get_bus_send(index)), "VoiceChat", "%s send" % bus_name)
		assert_gt(index, parent, "%s must sit after VoiceChat or its send is dropped" % bus_name)


func test_the_shared_voice_bus_reaches_master() -> void:
	var index := AudioServer.get_bus_index("VoiceChat")
	assert_eq(String(AudioServer.get_bus_send(index)), "Master", "VoiceChat send")
	assert_gt(index, 0, "VoiceChat must sit after Master")


func test_each_speaker_slot_owns_its_own_low_pass_filter() -> void:
	var filters: Array[AudioEffectLowPassFilter] = []
	for bus_name in VOICE_SLOT_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		var filter := _find_effect(index, "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
		assert_true(filter != null, "%s needs a low-pass somewhere for occlusion" % bus_name)
		if filter != null:
			assert_gt(filter.cutoff_hz, 15000.0, "%s must start open, not muffled" % bus_name)
			filters.append(filter)
	if filters.size() == 2:
		assert_ne(
			filters[0].get_instance_id(),
			filters[1].get_instance_id(),
			"a shared filter would give both speakers one cutoff"
		)


## Order is the whole point: the radio chain shapes the voice, then occlusion
## takes the high end away last. Distortion after the low-pass would generate
## harmonics above its cutoff and undo the muffling a wall is meant to cause.
func test_the_radio_chain_runs_before_occlusion() -> void:
	for bus_name in VOICE_SLOT_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		var high_pass := _effect_slot(index, "AudioEffectHighPassFilter")
		var distortion := _effect_slot(index, "AudioEffectDistortion")
		var low_pass := _effect_slot(index, "AudioEffectLowPassFilter")
		assert_gt(high_pass + 1, 0, "%s needs a high-pass for the radio band" % bus_name)
		assert_gt(distortion + 1, 0, "%s needs a distortion for the radio grit" % bus_name)
		assert_gt(low_pass, distortion, "%s occlusion must run after distortion" % bus_name)
		assert_gt(low_pass, high_pass, "%s occlusion must run last" % bus_name)


func test_the_radio_band_leaves_speech_intact() -> void:
	for bus_name in VOICE_SLOT_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		var high_pass := (
			_find_effect(index, "AudioEffectHighPassFilter") as AudioEffectHighPassFilter
		)
		if high_pass != null:
			# Above this the radio starts eating vowels rather than colouring them.
			assert_true(high_pass.cutoff_hz <= 400.0, "%s high-pass is too aggressive" % bus_name)


func test_capture_reads_the_bus_before_it_is_silenced() -> void:
	var index := AudioServer.get_bus_index("VoiceCapture")
	assert_true(
		AudioServer.get_bus_effect(index, 0) is AudioEffectCapture,
		"the capture effect must be first in the chain"
	)
	var silencer := AudioServer.get_bus_effect(index, 1) as AudioEffectAmplify
	assert_true(silencer != null, "an amplifier after it is what stops you hearing yourself")
	if silencer != null:
		assert_true(silencer.volume_db <= -60.0, "the microphone must not reach the speakers")


## The redundancy here is deliberate, and was bought the hard way: on the web export
## the amplifier alone did not stop players hearing themselves. Mute is applied after
## the effect chain, so it silences the monitor without costing the capture a sample -
## measured, not assumed.
func test_the_capture_bus_is_muted_but_not_bypassed() -> void:
	var index := AudioServer.get_bus_index("VoiceCapture")
	assert_false(AudioServer.is_bus_bypassing_effects(index), "bypassing would stop capture dead")
	assert_true(
		AudioServer.is_bus_mute(index),
		"a second, non-effect guarantee that the microphone never reaches the speakers"
	)


func _find_effect(bus_index: int, class_name_wanted: String) -> AudioEffect:
	var slot := _effect_slot(bus_index, class_name_wanted)
	return null if slot < 0 else AudioServer.get_bus_effect(bus_index, slot)


func _effect_slot(bus_index: int, class_name_wanted: String) -> int:
	for i in AudioServer.get_bus_effect_count(bus_index):
		if AudioServer.get_bus_effect(bus_index, i).is_class(class_name_wanted):
			return i
	return -1
