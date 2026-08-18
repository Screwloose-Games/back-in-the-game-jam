extends GutTest

## The wire between what a player does and what the creature hears.
##
## Both rate limits are the point of this file. The relay throttles UP, because
## `receive_noise` has none of its own and a per-frame relay would evict a minute of real
## evidence with duplicates inside a second; and it throttles DOWN, because the emitter
## announces only on a level change and a held drill would otherwise go silent after one
## event.

const TICK: float = 1.0 / 60.0

var _relay: PlayerNoiseRelay = null
var _perception: CreaturePerception = null
var _emitter: _FakeEmitter = null
var _heard: Array = []


func before_each() -> void:
	_perception = autofree(CreaturePerception.new())
	_perception.config = PerceptionConfig.new()
	_heard = []
	_perception.noise_evaluated.connect(
		func(event: NoiseEvent, _e: Variant, _d: float, _o: float) -> void: _heard.append(event)
	)

	_emitter = autofree(_FakeEmitter.new())
	_relay = autofree(PlayerNoiseRelay.new())
	_relay.perception = _perception
	_relay.bind(_emitter)


func test_silence_is_never_announced() -> void:
	_advance(5.0)
	assert_eq(_heard.size(), 0, "a player doing nothing makes no events")


func test_a_noise_starting_is_heard_at_once() -> void:
	_emitter.emit(10.0, Vector3(3.0, 0.0, 0.0), 1)
	_advance(TICK)
	assert_eq(_heard.size(), 1, "not up to emit_interval_s later")


func test_mining_arrives_at_full_loudness_and_thrust_below_it() -> void:
	# PlayerSettings ships mining_noise_strength 10.0 and thrust_noise_strength 6.0, and
	# noise_scale is 10.0 so the pair lands on 1.0 and 0.6 -- straddling the hand-tuned
	# QUIET_LOUDNESS 0.25 / LOUD_LOUDNESS 1.0 both creature sandboxes already use.
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(TICK)
	assert_almost_eq(_heard[0].loudness, 1.0, 0.001, "mining")
	assert_eq(_heard[0].category, &"mining")

	_emitter.emit(6.0, Vector3.ZERO, 0)
	_advance(_relay.emit_interval_s + TICK)
	assert_almost_eq(_heard[-1].loudness, 0.6, 0.001, "thrust")
	assert_eq(_heard[-1].category, &"thrust")


func test_loudness_is_clamped_rather_than_running_past_the_cap() -> void:
	_emitter.emit(500.0, Vector3.ZERO, 1)
	_advance(TICK)
	assert_eq(_heard[0].loudness, 1.0, "a noise louder than anything the config was tuned for")


func test_a_held_noise_keeps_being_heard() -> void:
	# The emitter announces ONCE for a held drill, on its CHANGE_EPSILON level change. Without
	# the relay's interval the creature would hear the first instant of a thirty-second drill
	# and lose the trail while the player was still making it.
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(5.0)
	assert_eq(_emitter.announcements, 1, "the emitter said it once")
	assert_between(_heard.size(), 9, 12, "and the creature went on hearing it")


func test_a_held_noise_is_not_relayed_at_the_frame_rate() -> void:
	# SuspicionConfig.max_evidence_count is 64. At 60 Hz a relay with no interval would fill
	# and evict that ring in about a second, replacing real evidence with its own duplicates.
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(1.0)
	assert_lt(_heard.size(), 5, "twice a second, not sixty times")


func test_the_noise_follows_the_player() -> void:
	_emitter.emit(10.0, Vector3(1.0, 0.0, 0.0), 1)
	_advance(TICK)
	_emitter.emit(10.0, Vector3(9.0, 0.0, 2.0), 1)
	_advance(_relay.emit_interval_s + TICK)
	assert_eq(_heard[-1].position, Vector3(9.0, 0.0, 2.0), "the latest position, not the first")


func test_going_quiet_stops_the_relay() -> void:
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(2.0)
	var heard: int = _heard.size()
	_emitter.emit(0.0, Vector3.ZERO, 1)
	_advance(5.0)
	assert_eq(_heard.size(), heard, "nothing further, and nothing lingering")


func test_the_noise_names_the_player_so_suspicion_can_attribute_it() -> void:
	var body: Node = autofree(Node3D.new())
	_emitter.body = body
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(TICK)
	assert_eq(_heard[0].source_player, body, "the emitter's body, not the component")


func test_binding_the_same_emitter_twice_does_not_double_the_noise() -> void:
	_relay.bind(_emitter)
	_relay.bind(_emitter)
	_emitter.emit(10.0, Vector3.ZERO, 1)
	_advance(TICK)
	assert_eq(_heard.size(), 1, "one connection, however many times it was asked for")


func test_two_emitters_are_both_heard_rather_than_clobbering_each_other() -> void:
	# A player is not one noise source: the body reports thrust and the beam reports the cut
	# at its far endpoint. A single latest-wins slot meant whichever announced last was the
	# only one the creature ever heard.
	var beam: _FakeEmitter = autofree(_FakeEmitter.new())
	_relay.bind(beam)
	_emitter.emit(5.0, Vector3(0.0, 0.0, 0.0), 1)
	beam.emit(10.0, Vector3(6.0, 0.0, 0.0), 1)
	_advance(TICK)

	assert_eq(_heard.size(), 2, "one event per emitter")
	var positions: Array = _heard.map(func(event: NoiseEvent) -> Vector3: return event.position)
	assert_has(positions, Vector3.ZERO, "the gun")
	assert_has(positions, Vector3(6.0, 0.0, 0.0), "and the rock it is cutting")


func test_the_gun_arrives_at_half_the_loudness_of_the_cut() -> void:
	# PlayerSettings ships mining_noise_strength 10.0 and mining_muzzle_noise_fraction 0.5, so
	# the pair reaches the relay as 5.0 and 10.0 and leaves it as 0.5 and 1.0.
	var beam: _FakeEmitter = autofree(_FakeEmitter.new())
	_relay.bind(beam)
	_emitter.emit(5.0, Vector3.ZERO, 1)
	beam.emit(10.0, Vector3(6.0, 0.0, 0.0), 1)
	_advance(TICK)

	var by_position: Dictionary = {}
	for event: NoiseEvent in _heard:
		by_position[event.position] = event.loudness
	assert_almost_eq(float(by_position[Vector3.ZERO]), 0.5, 0.001, "the gun")
	assert_almost_eq(float(by_position[Vector3(6.0, 0.0, 0.0)]), 1.0, 0.001, "the cut")


func test_one_emitter_going_quiet_does_not_silence_the_other() -> void:
	var beam: _FakeEmitter = autofree(_FakeEmitter.new())
	_relay.bind(beam)
	_emitter.emit(5.0, Vector3.ZERO, 0)
	beam.emit(10.0, Vector3(6.0, 0.0, 0.0), 1)
	_advance(2.0)
	beam.emit(0.0, Vector3(6.0, 0.0, 0.0), 1)
	_heard = []
	_advance(2.0)

	assert_gt(_heard.size(), 0, "the body is still thrusting")
	for event: NoiseEvent in _heard:
		assert_eq(event.position, Vector3.ZERO, "and only the body")


func test_each_emitter_keeps_its_own_interval() -> void:
	# The up-throttle protects a ring capped at SuspicionConfig.max_evidence_count (64).
	# Two emitters should double the trickle, not remove the limit.
	var beam: _FakeEmitter = autofree(_FakeEmitter.new())
	_relay.bind(beam)
	_emitter.emit(5.0, Vector3.ZERO, 1)
	beam.emit(10.0, Vector3(6.0, 0.0, 0.0), 1)
	_advance(1.0)
	assert_lt(_heard.size(), 10, "twice a second each, not sixty times each")


func test_an_emitter_that_starts_late_is_heard_at_once() -> void:
	_emitter.emit(5.0, Vector3.ZERO, 0)
	_advance(1.0)
	var heard: int = _heard.size()
	var beam: _FakeEmitter = autofree(_FakeEmitter.new())
	_relay.bind(beam)
	beam.emit(10.0, Vector3(6.0, 0.0, 0.0), 1)
	_advance(TICK)
	assert_eq(_heard.size(), heard + 1, "its own silent-to-loud edge, not the other's interval")


func test_the_relay_reads_a_wall_clock_from_nowhere() -> void:
	# The delta it is handed is the only time, which is what lets this whole suite run without
	# a tree and what keeps the relay honest under get_tree().paused and Engine.time_scale.
	_emitter.emit(10.0, Vector3.ZERO, 1)
	assert_eq(_relay.clock, 0.0, "not started until it is driven")
	_advance(1.0)
	assert_almost_eq(_relay.clock, 1.0, 0.02, "and driven only by advance()")


func _advance(seconds: float) -> void:
	for _i: int in maxi(int(roundf(seconds / TICK)), 1):
		_relay.advance(TICK)


## Anything with the signal drives the relay. This is the shape PlayerNoiseEmitter publishes.
class _FakeEmitter:
	extends Node

	signal noise_emitted(strength: float, at: Vector3, source: int)

	var body: Node = null
	var announcements: int = 0

	func emit(strength: float, at: Vector3, source: int) -> void:
		announcements += 1
		noise_emitted.emit(strength, at, source)
