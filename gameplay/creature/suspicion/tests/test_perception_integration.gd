extends GutTest

## A real CreaturePerception wired to a real CreatureSuspicion.
##
## Every other suite hand-builds observations, which proves Suspicion agrees with the
## fixture. This one proves the fixture agrees with Perception -- that the two modules
## still fit together after either of them changes, without needing physics or a scene.
##
## The property under test is the one perception/README.md says the whole searching
## layer depends on: hearing reports a DISPLACED position with a wide uncertainty
## radius, and Suspicion has to turn that into a wide area to search rather than a
## precise coordinate to walk to. If a refactor ever makes hearing exact, the assertion
## about hotspot width here is what fails.

const FakeProbe := preload("res://gameplay/creature/perception/tests/fake_perception_probe.gd")
const TICK: float = 1.0 / 60.0

var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _perception_config: PerceptionConfig = null
var _suspicion_config: SuspicionConfig = null


func before_each() -> void:
	_perception_config = PerceptionConfig.new()
	_perception_config.geometry_perception_enabled = false
	_perception = autofree(CreaturePerception.new())
	_perception.config = _perception_config
	_perception.probe = FakeProbe.new()
	_perception.hearing.rng.seed = 99

	_suspicion_config = SuspicionConfig.new()
	_suspicion_config.hotspot_update_interval = 0.0
	_suspicion = autofree(CreatureSuspicion.new())
	_suspicion.config = _suspicion_config

	# The wiring the perception README documents. Four lines, and the only coupling
	# between the two modules.
	_perception.evidence_observed.connect(_suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)


func _advance(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_perception.advance(TICK)
		_suspicion.advance(TICK)


func test_a_heard_noise_becomes_a_hotspot() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 6), 1.0, &"drill"))
	_advance(TICK)

	var hotspot: SuspicionHotspot = _suspicion.get_strongest_hotspot()
	assert_not_null(hotspot, "perception heard it and suspicion believed it")
	assert_gt(hotspot.suspicion, 0.0)
	assert_gt(_suspicion.get_overall_suspicion(), 0.0)


## THE ASSERTION THIS FILE EXISTS FOR. A distant footstep arrives with a large
## uncertainty radius and a displaced position; a nearby drill arrives with a tight
## one. Suspicion must turn the first into a wide area to sweep, not a point to walk to.
func test_a_distant_faint_noise_produces_a_far_wider_hotspot_than_a_near_loud_one() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 3), 1.0, &"drill"))
	_advance(TICK)
	var near: SuspicionHotspot = _suspicion.get_strongest_hotspot()

	before_each()
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 16), 1.0, &"footstep"))
	_advance(TICK)
	var far: SuspicionHotspot = _suspicion.get_strongest_hotspot()

	assert_not_null(near)
	assert_not_null(far)
	assert_gt(
		far.radius,
		near.radius * 2.0,
		"if these are the same, hearing is handing Suspicion exact coordinates"
	)
	assert_gt(near.suspicion, far.suspicion, "and the near one is more alarming as well as tighter")


## Perception's detection floor and Suspicion's retention floor compound, on purpose. A
## noise at the very edge of hearing arrives so weak and so unconfident that believing
## it would mean the creature investigating everything that ever happens anywhere.
func test_a_noise_at_the_very_edge_of_hearing_forms_no_belief_at_all() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 38), 1.0, &"footstep"))
	_advance(TICK)

	assert_null(_suspicion.get_strongest_hotspot())
	assert_eq(_suspicion.get_overall_suspicion(), 0.0)


## Section 19's fork, followed all the way through: a search that finds nothing emits a
## disconfirmation, and that disconfirmation is what reduces belief.
func test_a_fruitless_search_reduces_the_suspicion_it_was_sent_to_check() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 4), 1.0, &"drill"))
	_advance(TICK)
	var hotspot: SuspicionHotspot = _suspicion.get_strongest_hotspot()
	var before: float = hotspot.suspicion
	var target: Vector3 = _suspicion.get_best_unresolved_location(hotspot.id)

	# Behavior's half of the loop: go where Suspicion said, and ask Perception to look.
	_perception.request_activity_scan(AABB(target - Vector3.ONE * 4.0, Vector3.ONE * 8.0), 1.0)
	_advance(_perception_config.search_scan_duration_max + 0.5)

	assert_gt(before, 0.0)
	assert_lt(
		_suspicion.get_suspicion_near(target, 3.0),
		before,
		"the creature looked where it believed and found nothing"
	)


## A search that DOES find the player must not reduce anything -- Perception emits
## evidence instead of a disconfirmation, and suspicion goes up.
func test_a_search_that_finds_the_player_raises_suspicion_instead() -> void:
	var player: Node3D = autofree(Node3D.new())
	player.position = Vector3(0, 0, 4)
	_perception.targets.append(player)

	_perception.request_activity_scan(AABB(Vector3(-4, -4, 0), Vector3(8, 8, 8)), 1.0)
	_advance(_perception_config.search_scan_duration_max + 0.5)

	assert_gt(_suspicion.get_overall_suspicion(), 0.0)
	assert_eq(
		_suspicion.memory.disconfirmations.size(), 0, "it found something; it cleared nothing"
	)
	assert_eq(_suspicion.get_strongest_hotspot().likely_source, player)
	assert_gt(_suspicion.get_player_suspicion(player), 0.0)


## An aborted scan reaches FINISHED so Behavior does not hang, and reports zero
## strength. Suspicion must treat that as "never looked", not as "checked and empty".
func test_a_search_that_could_not_run_clears_nothing() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 4), 1.0, &"drill"))
	_advance(TICK)
	var before: float = _suspicion.get_overall_suspicion()

	_perception.probe.bound = false
	_perception.request_activity_scan(AABB(Vector3(-4, -4, 0), Vector3(8, 8, 8)), 1.0)
	_advance(TICK)

	assert_eq(_suspicion.memory.disconfirmations.size(), 0)
	assert_almost_eq(_suspicion.get_overall_suspicion(), before, 0.02)


## The loop perception/README.md's wiring snippet closes and nothing else exercises:
## suspicion drives how hard perception looks, and never what it finds.
func test_suspicion_can_feed_perceptions_alertness_back() -> void:
	assert_false(_perception_config.vision_gate(_perception.get_alertness()), "calm: vision is off")

	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 3), 1.0, &"drill"))
	_advance(TICK)
	_perception.set_alertness_context(_suspicion.get_overall_suspicion())

	assert_gt(_perception.get_alertness(), 0.0)
	assert_true(_perception_config.vision_gate(_perception.get_alertness()), "alerted: it looks")


## Two clocks, started independently. Suspicion must not decay evidence from
## Perception's timestamps, or a perception that has been alive longer than its
## suspicion hands over records that are already dead.
func test_the_two_modules_keep_separate_clocks_without_corrupting_decay() -> void:
	_perception.advance(90.0)  # perception has been alive far longer than suspicion
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 4), 1.0, &"drill"))
	_advance(TICK)

	var record: SuspicionEvidenceRecord = _suspicion.memory.records[0]
	assert_gt(record.observed_at, 89.0, "stamped on perception's clock")
	assert_lt(record.received_at, 1.0, "and received on suspicion's own")
	assert_gt(_suspicion.get_overall_suspicion(), 0.1, "it arrived fresh, not ninety seconds stale")
