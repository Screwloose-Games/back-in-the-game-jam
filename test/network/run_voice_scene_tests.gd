extends Node

## Headless scene checks for proximity voice: which half of the node is live on
## which copy of the player, and whether the capture bus really behaves.
##
## The capture check is the one that cannot be done with pure data. Bus volume
## and mute are applied after the effect chain runs in AudioServer::_mix_step, so
## an AudioEffectCapture on a silenced bus should still see full amplitude - but
## "should" is doing a lot of work there, and getting it wrong means a
## microphone that captures nothing or one you can hear yourself through. It is
## reported as a skip rather than a failure when the headless dummy driver never
## mixes; run this scene windowed to force the question.

const NetworkPlayerScene := preload("res://prefabs/character/player/prefab_network_player.tscn")
const OptionsMenuScene := preload("res://common/ui/options_menu/options_menu.tscn")
const PauseMenuScene := preload("res://common/ui/pause_menu/pause_menu.tscn")
const HudScene := preload("res://prefabs/ui/hud/prefab_hud_04.tscn")
const HOST_PEER_ID := 1
const CLIENT_PEER_ID := 2
## Not 1 or 2, so registering it cannot collide with a spawned fixture.
const FIXTURE_PEER_ID := 7
const MIX_FRAMES := 60

var _checks := 0
var _failures := 0
var _skips := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# The suite inherits whatever the player last saved, and a machine that had
	# voice switched on would open a real microphone here and fail the check that
	# it stays shut. Consent state is an input to these tests, not an ambient fact.
	var restore_voice_enabled: bool = VoiceService.voice_enabled
	VoiceService.voice_enabled = false

	await _test_remote_copy()
	await _test_local_copy()
	await _test_options_menu()
	await _test_peer_list()
	await _test_hud_indicator()
	await _test_capture_bus()
	_test_driver_capture()

	VoiceService.voice_enabled = restore_voice_enabled

	if _failures == 0:
		print("PASS [voice-scene] %d checks, %d skipped" % [_checks, _skips])
	else:
		print("FAIL [voice-scene] %d of %d checks failed" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_remote_copy() -> void:
	var player := await _spawn(CLIENT_PEER_ID, HOST_PEER_ID, "RemoteFixture")
	var voice := player.get_node("PlayerBody/ProximityVoiceChat") as PlayerProximityVoiceChat
	_expect(voice != null, "the network prefab carries a ProximityVoiceChat")

	_expect(
		voice.get_node_or_null("VoiceInput") == null,
		"a remote avatar must not keep a node that can open this machine's microphone",
	)
	var output := voice.get_node_or_null("VoiceOutput") as AudioStreamPlayer3D
	_expect(output != null and output.playing, "a remote speaker plays from the moment it spawns")
	if output == null:
		return

	_expect(
		output.playback_type == AudioServer.PLAYBACK_TYPE_STREAM,
		"stream playback is required per node or the bus effects are bypassed on web",
	)
	_expect(
		String(output.bus).begins_with("Voice_"),
		"a remote speaker takes a dedicated slot bus, got %s" % output.bus,
	)

	var generator := output.stream as AudioStreamGenerator
	_expect(generator != null, "the speaker plays an AudioStreamGenerator")
	if generator != null:
		_expect(
			generator.mix_rate_mode == AudioStreamGenerator.MIX_RATE_CUSTOM,
			"any other mix rate mode ignores mix_rate entirely",
		)
		_expect(
			int(generator.mix_rate) == VoiceService.config.sample_rate,
			"the generator runs at the codec rate, got %d" % int(generator.mix_rate),
		)

	_expect(
		CLIENT_PEER_ID in VoiceService.remote_peer_ids(),
		"a remote avatar registers itself as a speaker",
	)
	await _test_decoded_audio_reaches_the_generator(voice, output)

	player.queue_free()
	await get_tree().process_frame


## Three frames is the jitter target, so the buffer primes and drains on the tick
## after the third arrives.
func _test_decoded_audio_reaches_the_generator(
	voice: PlayerProximityVoiceChat, output: AudioStreamPlayer3D
) -> void:
	var playback := output.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		_expect(false, "the speaker exposes an AudioStreamGeneratorPlayback")
		return

	var before := playback.get_frames_available()
	var samples_per_frame := VoiceService.config.samples_per_frame()
	for sequence in 3:
		voice.receive_voice(VoicePacket.unpack(_voice_packet(sequence, samples_per_frame)))
	await get_tree().process_frame
	await get_tree().process_frame

	var pushed := before - playback.get_frames_available()
	_expect(pushed > 0, "decoded audio should reach the generator ring, %d free before" % before)
	# Filling the ring instead of pacing against it would pop six frames here:
	# three real and three fabricated by treating an empty buffer as an underrun,
	# which retires the speaker moments after it started talking.
	_expect(
		pushed <= samples_per_frame * 4,
		"playout must be paced by the drain rate, %d samples went in at once" % pushed,
	)


func _test_local_copy() -> void:
	var player := await _spawn(HOST_PEER_ID, HOST_PEER_ID, "LocalFixture")
	var voice := player.get_node("PlayerBody/ProximityVoiceChat") as PlayerProximityVoiceChat
	var input := voice.get_node_or_null("VoiceInput") as AudioStreamPlayer
	_expect(input != null, "the local avatar keeps its microphone node")
	_expect(
		input == null or not input.playing,
		"the microphone must stay shut until the player enables voice",
	)
	_expect(
		input == null or String(input.bus) == "VoiceCapture",
		"the microphone belongs on the silenced capture bus, not on an audible one",
	)
	_expect(
		voice.get_node_or_null("VoiceOutput") == null,
		"you do not hear your own avatar unless the loopback rig is on",
	)

	player.queue_free()
	await get_tree().process_frame


func _test_options_menu() -> void:
	var menu := OptionsMenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame

	for unique_name in [
		"VoiceChatSlider", "VoiceEnabledButton", "MicLevelBar", "MicThresholdSlider"
	]:
		_expect(
			menu.get_node_or_null("%" + unique_name) != null, "options menu has %s" % unique_name
		)

	var inputs := menu.get_node_or_null("%AudioInputOptionButton") as OptionButton
	_expect(
		inputs != null and inputs.item_count >= 1,
		"the input device dropdown is populated, even if only with the system default",
	)
	var talk_mode := menu.get_node_or_null("%TalkModeOptionButton") as OptionButton
	_expect(talk_mode != null and talk_mode.item_count == 2, "talk mode offers both modes")
	_expect(
		talk_mode == null or talk_mode.selected == OptionsMenu.TALK_MODE_VOICE_ACTIVATED,
		"voice activation is the default talk mode",
	)

	menu.queue_free()
	await get_tree().process_frame


## Registered without a node on purpose: the panel is a listening control and
## must not need a spawned avatar to exist before it can mute somebody.
func _test_peer_list() -> void:
	var menu := PauseMenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var panel := menu.get_node_or_null("%VoicePeerList") as VoicePeerList
	_expect(panel != null, "the pause menu carries a VoicePeerList")
	if panel == null:
		menu.queue_free()
		return

	VoiceService.register_speaker(FIXTURE_PEER_ID, null)
	panel.refresh()
	var row := panel.get_node_or_null("Peer%d" % FIXTURE_PEER_ID)
	_expect(row != null and panel.visible, "a connected survivor gets a row")

	if row != null:
		for control in row.get_children():
			if control is CheckButton:
				control.button_pressed = true
		_expect(VoiceService.is_peer_muted(FIXTURE_PEER_ID), "the mute toggle reaches VoiceService")

	VoiceService.set_peer_volume(FIXTURE_PEER_ID, 0.25)
	_expect(
		is_equal_approx(VoiceService.peer_volume(FIXTURE_PEER_ID), 0.25), "per-peer volume is kept"
	)

	VoiceService.set_peer_muted(FIXTURE_PEER_ID, false)
	VoiceService.unregister_speaker(FIXTURE_PEER_ID)
	panel.refresh()
	_expect(not panel.visible, "the panel hides itself once nobody is left to hear")

	menu.queue_free()
	await get_tree().process_frame


func _test_hud_indicator() -> void:
	var hud := HudScene.instantiate() as HudVariant
	add_child(hud)
	var state := HudState.new()
	add_child(state)
	hud.bind(state)
	await get_tree().process_frame

	var indicator := hud.find_children("*", "HudVoiceIndicator", true, false)
	_expect(indicator.size() == 1, "the default HUD carries exactly one voice indicator")
	if indicator.size() == 1:
		var widget := indicator[0] as HudVoiceIndicator
		_expect(not widget.live, "and it starts dark, because the microphone starts shut")
		state.voice_live = true
		state.voice_transmitting = true
		state.voice_loudness = 0.6
		_expect(
			widget.live and widget.transmitting and is_equal_approx(widget.loudness, 0.6),
			"a live microphone reaches the indicator through HudState",
		)

	state.queue_free()
	hud.queue_free()
	await get_tree().process_frame


func _test_capture_bus() -> void:
	var bus_index := AudioServer.get_bus_index("VoiceCapture")
	var capture := AudioServer.get_bus_effect(bus_index, 0) as AudioEffectCapture
	if capture == null:
		_expect(false, "the capture bus carries an AudioEffectCapture at effect 0")
		return

	var source := _tone_source()
	add_child(source)
	source.play()
	var playback := source.get_stream_playback() as AudioStreamGeneratorPlayback
	capture.clear_buffer()

	var phase := 0.0
	for i in MIX_FRAMES:
		phase = _push_tone(playback, phase)
		await get_tree().process_frame

	var available := capture.get_frames_available()
	source.queue_free()
	if available <= 0:
		_skips += 1
		print(
			(
				"SKIP [voice-scene] the audio driver never mixed, so the capture bus "
				+ "could not be exercised. Run this scene windowed to check it."
			)
		)
		return

	var peak := 0.0
	for frame in capture.get_buffer(available):
		peak = maxf(peak, absf(frame.x))
	_expect(
		peak > 0.1,
		"capture must read the bus at full amplitude despite it being silenced, peak %.3f" % peak,
	)
	_expect(
		AudioServer.get_bus_peak_volume_left_db(0, 0) < -40.0,
		"and none of it may reach Master, or the player hears themselves",
	)
	_expect(
		AudioServer.is_bus_mute(bus_index),
		"the capture bus stays muted; the amplifier alone did not hold on web",
	)


## The property that makes this path the preferred one: it reads the driver's input
## buffer, so silencing the monitor cannot starve it the way AudioEffectCapture is.
func _test_driver_capture() -> void:
	var capture := GodotVoiceCapture.new(VoiceService.config)
	var started := capture.start()
	_expect(
		started == OK or not capture.unavailable_reason().is_empty(),
		"capture that cannot start must say why rather than look healthy",
	)
	if started != OK:
		_skips += 1
		print("SKIP [voice-scene] driver capture unavailable: %s" % capture.unavailable_reason())
		return

	_expect(capture.is_active(), "a started capture reports itself active")
	_expect(capture.source_rate() > 0, "capture resamples from a real input rate")
	_expect(not capture.has_rate_mismatch(), "frames arrive on the input clock, so no pitch shift")
	var frames := capture.poll()
	_expect(frames is Array, "poll returns frames without a device rather than erroring")
	for frame in frames:
		_expect(
			frame.size() == VoiceService.config.samples_per_frame(),
			"poll emits fixed-size frames, got %d" % frame.size(),
		)
	capture.stop()
	_expect(not capture.is_active(), "a stopped capture reports itself inactive")


func _tone_source() -> AudioStreamPlayer:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = 0.5

	var source := AudioStreamPlayer.new()
	source.stream = generator
	source.bus = &"VoiceCapture"
	source.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	return source


func _push_tone(playback: AudioStreamGeneratorPlayback, phase: float) -> float:
	if playback == null:
		return phase
	var step := TAU * 440.0 / AudioServer.get_mix_rate()
	var buffer := PackedVector2Array()
	buffer.resize(playback.get_frames_available())
	for i in buffer.size():
		var value := sin(phase + step * float(i)) * 0.8
		buffer[i] = Vector2(value, value)
	playback.push_buffer(buffer)
	return phase + step * float(buffer.size())


func _voice_packet(sequence: int, samples_per_frame: int) -> PackedByteArray:
	var samples := PackedFloat32Array()
	samples.resize(samples_per_frame)
	for i in samples_per_frame:
		samples[i] = sin(TAU * 300.0 * float(i) / 8000.0) * 0.5
	return VoicePacket.pack(CLIENT_PEER_ID, sequence, VoiceAdpcm.encode(samples))


func _spawn(controlled_peer_id: int, local_peer_id: int, fixture_name: String) -> Node3D:
	var player := NetworkPlayerScene.instantiate() as Node3D
	var driver := player.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	driver.configure(controlled_peer_id, local_peer_id)
	driver.set_physics_process(false)
	player.name = fixture_name
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	return player


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [voice-scene] %s" % description)
