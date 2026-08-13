extends "res://gameplay/creature/perception/tests/perception_test_case.gd"

## CreaturePerception's clock, its two output channels, and section 19's search fork.
##
## The architectural invariants of sections 28 and 31 live next door in
## test_perception_invariants.gd -- split only because gdlint caps a class at 20
## public methods and GUT tests are public methods.

# ----- the clock -----


func test_the_clock_starts_at_zero_and_advances_with_delta() -> void:
	assert_eq(_perception.clock, 0.0)
	_advance(1.0)
	assert_almost_eq(_perception.clock, 1.0, TICK)


func test_observations_are_stamped_with_the_perception_clock() -> void:
	_advance(2.0)
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 2), 1.0, &"drill"))

	assert_eq(_evidence.size(), 1)
	assert_almost_eq(_evidence[0].observed_at, _perception.clock, 0.0001)
	assert_lt(_evidence[0].observed_at, 100.0, "seconds since spawn, not milliseconds since boot")


# ----- routing: the two channels never cross -----


func test_a_heard_noise_reaches_the_evidence_signal_only() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 3), 1.0, &"drill"))

	assert_eq(_evidence.size(), 1)
	assert_eq(_evidence[0].sense, SuspicionEvidence.Sense.HEARING)
	assert_eq(_disconfirmations.size(), 0)
	assert_eq(_geometry.size(), 0)


func test_contact_reaches_the_evidence_signal_only() -> void:
	_perception.receive_contact(autofree(Node3D.new()), Vector3(1, 0, 0))

	assert_eq(_evidence.size(), 1)
	assert_eq(_evidence[0].sense, SuspicionEvidence.Sense.TOUCH)
	assert_eq(_geometry.size(), 0)


## Section 31: geometry goes to Spatial Memory, evidence goes to Suspicion. A wall
## is not evidence of a player.
func test_geometry_observations_never_appear_on_the_evidence_signal() -> void:
	_config.geometry_perception_enabled = true
	_probe.add_wall(AABB(Vector3(2, -5, -5), Vector3(10, 10, 10)))

	_advance(1.0)

	assert_gt(_geometry.size(), 0, "passive geometry scanning should have run")
	assert_eq(_evidence.size(), 0, "and produced no activity evidence whatsoever")
	assert_eq(_disconfirmations.size(), 0)
	for batch: Array in _geometry:
		for observation: Variant in batch:
			assert_true(observation is GeometryObservation)


func test_activity_evidence_never_appears_on_the_geometry_signal() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 2), 1.0))
	_perception.receive_contact(autofree(Node3D.new()), Vector3.ZERO)

	assert_eq(_geometry.size(), 0)


## Section 29 wants "the alien didn't hear me" and "the alien heard me and didn't
## care" to be different, visible failures. That needs a report even when nothing
## was perceived.
func test_an_unheard_noise_still_reports_that_it_was_evaluated() -> void:
	var seen: Array = []
	_perception.noise_evaluated.connect(
		func(_e: NoiseEvent, evidence: SuspicionEvidence, distance: float, _o: float) -> void:
			seen.append([evidence, distance])
	)
	_perception.receive_noise(NoiseEvent.make(Vector3(0, 0, 5000.0), 1.0))

	assert_eq(_evidence.size(), 0, "it was not heard")
	assert_eq(seen.size(), 1, "but the evaluation still happened and is still reported")
	assert_null(seen[0][0])


# ----- activity scan: section 19's fork -----


func test_a_search_that_finds_nothing_disconfirms_exactly_once() -> void:
	_perception.request_activity_scan(_empty_region(), 1.0)
	assert_true(_perception.is_activity_scan_active())

	_advance(_config.search_scan_duration_max + 0.5)

	assert_true(_perception.is_activity_scan_complete())
	assert_eq(_disconfirmations.size(), 1, "exactly one, not one per sample")
	assert_eq(_evidence.size(), 0)
	assert_gt(_disconfirmations[0].strength, 0.0)


func test_a_search_that_finds_the_player_emits_evidence_and_no_disconfirmation() -> void:
	_add_target(Vector3.ZERO)

	_perception.request_activity_scan(_search_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_gt(_evidence.size(), 0, "the player was in the region and in plain sight")
	assert_eq(_disconfirmations.size(), 0, "a search that found something disconfirms nothing")


## A thorough sweep takes max_scan_samples looks. A stationary player is found by
## almost all of them, and reporting each one would hand Suspicion hundreds of
## identical maximum-strength records for a single sighting.
func test_a_search_reports_each_target_once_however_many_samples_find_it() -> void:
	_add_target(Vector3.ZERO)
	_add_target(Vector3(0.5, 0, 0.5))

	_perception.request_activity_scan(_search_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_gt(_config.scan_sample_count(1.0), 50, "the sweep really did take many looks")
	assert_eq(_evidence.size(), 2, "one record per target, not one per sample")


func test_a_second_search_can_report_the_same_target_again() -> void:
	_add_target(Vector3.ZERO)
	_perception.request_activity_scan(_search_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)
	assert_eq(_evidence.size(), 1)

	_perception.request_activity_scan(_search_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_eq(_evidence.size(), 2, "the once-per-scan rule must not persist across scans")


## Section 19's fork drawn literally: never both, never neither, at any thoroughness.
func test_every_completed_search_produces_exactly_one_outcome() -> void:
	for thoroughness: float in [0.0, 0.25, 1.0]:
		for player_present: bool in [false, true]:
			before_each()
			if player_present:
				_add_target(Vector3.ZERO)

			_perception.request_activity_scan(_search_region(), thoroughness)
			_advance(_config.search_scan_duration_max + 0.5)

			var found_evidence: bool = _evidence.size() > 0
			assert_true(_perception.is_activity_scan_complete())
			assert_eq(
				_disconfirmations.size(),
				0 if found_evidence else 1,
				"thoroughness %s, player %s" % [thoroughness, player_present]
			)


## A search requested while its senses cannot run must STILL complete. Otherwise
## Behavior's request-then-poll loop hangs forever on a config flag, silently -- and
## the creature stands still with nothing in the log.
func test_a_search_that_cannot_run_completes_immediately() -> void:
	_probe.bound = false

	_perception.request_activity_scan(AABB(Vector3.ZERO, Vector3(4, 4, 4)), 1.0)

	assert_true(_perception.is_activity_scan_complete(), "it must not hang Behavior")
	assert_false(_perception.is_activity_scan_active())
	assert_eq(_disconfirmations.size(), 1)
	assert_eq(_disconfirmations[0].strength, 0.0, "it did not really look, so it clears nothing")


func test_a_degenerate_search_region_completes_immediately() -> void:
	_perception.request_activity_scan(AABB(), 1.0)
	assert_true(_perception.is_activity_scan_complete())
	assert_eq(_disconfirmations.size(), 1)


func test_a_thorough_search_disconfirms_more_than_a_glance() -> void:
	_perception.request_activity_scan(_empty_region(), 0.2)
	_advance(_config.search_scan_duration_max + 0.5)
	var glance: float = _disconfirmations[0].strength

	before_each()
	_perception.request_activity_scan(_empty_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_gt(_disconfirmations[0].strength, glance, "section 9: a sweep clears more than a glance")


func test_a_search_records_which_senses_took_part() -> void:
	_perception.set_alertness_context(1.0)
	_perception.request_activity_scan(_empty_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	var observation: DisconfirmationObservation = _disconfirmations[0]
	assert_true(observation.has_sense(SuspicionEvidence.Sense.VISION))
	assert_true(observation.has_sense(SuspicionEvidence.Sense.TOUCH))
	assert_false(
		observation.has_sense(SuspicionEvidence.Sense.HEARING),
		"hearing is event-driven; it does not deliberately check a region"
	)


## Section 13: turning vision off must not require a change anywhere else. A search
## still runs and still resolves -- it just carries less weight.
func test_a_blind_creature_still_searches_but_disconfirms_on_fewer_senses() -> void:
	_config.vision_enabled = false
	_perception.request_activity_scan(_empty_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_eq(_disconfirmations.size(), 1, "vision off must not stop a search completing")
	assert_false(_disconfirmations[0].has_sense(SuspicionEvidence.Sense.VISION))


func test_a_search_hidden_behind_a_wall_finds_nothing() -> void:
	_add_target(Vector3.ZERO)
	# A wall through the middle of the region: the player is inside the search area
	# but not reachable by a clear line from most of it.
	_probe.force_clear_line = false

	_perception.request_activity_scan(_search_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_eq(_evidence.size(), 0, "searching a room should not see through its walls")
	assert_eq(_disconfirmations.size(), 1)
