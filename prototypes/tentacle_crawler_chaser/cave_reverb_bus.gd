class_name CaveReverbBus
extends RefCounted

## The audio bus that makes the corridors sound like the cave they look like.
##
## The network is 350 m of sealed 10 m stone tube and the only diegetic sound in
## it is the tentacle thud, played dry. A creature crawling a vast underground
## space therefore sounded like a creature in an anechoic chamber: the scale the
## whole level is built around was the one thing you could not hear.
##
## A BUS OF ITS OWN, NOT EFFECTS ON `SFX`. The SFX bus carries SoundManager's
## sixteen UI voices and every menu click in the project; reverb belongs on a bus
## only the creature feeds. This one SENDS to SFX rather than to Master, so
## GameSettings and the options-menu slider go on governing its volume without
## either of them knowing it exists.
##
## REGISTERED AT RUNTIME, not added to default_bus_layout.tres. Same rule the rest
## of this prototype follows: nothing here may require editing a file the host
## project shares. The cost is that the bus is not in the editor's Audio dock to
## drag sliders on - the numbers live in ChaseKnobs instead.

## Two, and the verifier asserts it. See install().
const EFFECT_COUNT := 2


## Create or reconfigure the cave bus. Safe to call repeatedly.
##
## IDEMPOTENT ON PURPOSE. AudioServer outlives the SceneTree, so a bus added on
## one run of this scene is still there on the next - and the verifier instances
## the prototype into an already-running tree. A blind add_bus() would stack a
## second bus per reload, and a blind add_bus_effect() would stack a second reverb
## on the same one, which is inaudible in the run that does it and doubles the
## tail in the run after. Look the bus up by name, and rebuild the chain from
## scratch every time rather than appending to whatever is already on it. That
## also means retuning a constant below and re-running is enough to hear it.
static func install(bus: StringName, send_to: StringName, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus)

	# Backwards, because removing an effect shifts everything after it down.
	for slot: int in range(AudioServer.get_bus_effect_count(index) - 1, -1, -1):
		AudioServer.remove_bus_effect(index, slot)

	var target := send_to
	if AudioServer.get_bus_index(send_to) < 0:
		push_warning('CaveReverbBus: no audio bus named "%s"; sending to Master.' % send_to)
		target = &"Master"
	AudioServer.set_bus_send(index, target)
	AudioServer.set_bus_volume_db(index, volume_db)

	# DELAY FIRST. The slaps are meant to be reverberated, which is what a real
	# echo down a tube is; running the reverb first instead echoes the tail and
	# comes out as a stutter laid over a wash rather than as a space.
	AudioServer.add_bus_effect(index, _build_delay())
	AudioServer.add_bus_effect(index, _build_reverb())


## The discrete returns - the part you can count, and the part that reads as
## distance rather than as "a big room".
static func _build_delay() -> AudioEffectDelay:
	var delay := AudioEffectDelay.new()
	# Full dry. The thud itself is the sound; the taps are what the corridor does
	# to it afterwards. Anything under 1.0 here quietly turns the impact down.
	delay.dry = 1.0

	delay.tap1_active = true
	delay.tap1_delay_ms = ChaseKnobs.CAVE_DELAY_TAP1_MS
	delay.tap1_level_db = ChaseKnobs.CAVE_DELAY_TAP1_DB
	delay.tap1_pan = ChaseKnobs.CAVE_DELAY_TAP1_PAN

	delay.tap2_active = true
	delay.tap2_delay_ms = ChaseKnobs.CAVE_DELAY_TAP2_MS
	delay.tap2_level_db = ChaseKnobs.CAVE_DELAY_TAP2_DB
	delay.tap2_pan = ChaseKnobs.CAVE_DELAY_TAP2_PAN

	delay.feedback_active = true
	delay.feedback_delay_ms = ChaseKnobs.CAVE_DELAY_FEEDBACK_MS
	delay.feedback_level_db = ChaseKnobs.CAVE_DELAY_FEEDBACK_DB
	# Each return darker than the last, because stone absorbs the top end first.
	# A feedback loop with no lowpass keeps returning the same bright transient
	# and sounds like a broken buffer.
	delay.feedback_lowpass = ChaseKnobs.CAVE_DELAY_FEEDBACK_LOWPASS_HZ
	return delay


## The tail the returns decay into.
static func _build_reverb() -> AudioEffectReverb:
	var reverb := AudioEffectReverb.new()
	reverb.predelay_msec = ChaseKnobs.CAVE_REVERB_PREDELAY_MS
	reverb.predelay_feedback = ChaseKnobs.CAVE_REVERB_PREDELAY_FEEDBACK
	reverb.room_size = ChaseKnobs.CAVE_REVERB_ROOM_SIZE
	reverb.damping = ChaseKnobs.CAVE_REVERB_DAMPING
	reverb.spread = ChaseKnobs.CAVE_REVERB_SPREAD
	reverb.hipass = ChaseKnobs.CAVE_REVERB_HIPASS
	reverb.dry = ChaseKnobs.CAVE_REVERB_DRY
	reverb.wet = ChaseKnobs.CAVE_REVERB_WET
	return reverb
