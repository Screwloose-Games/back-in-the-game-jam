extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## Negative evidence: what happens when the creature looks somewhere and finds nothing
## (suspicion.md, "Investigation State" and "Spatial Suspicion").
##
## This suite is the reason Behavior has no `clear_hotspot()`. Everything here happens
## because Perception reported an absence, and the only knob Behavior has is deciding
## where to send the creature next.
##
## The property worth protecting is spatial: a sweep of one end of a wide, vague
## hotspot must NOT clear the other end. Get that wrong and searching becomes a single
## boolean, the creature declares a twelve-metre sphere empty after glancing into one
## corner of it, and the player's hiding place stops mattering.


## A search that covers the whole of a tight hotspot should take most of it away --
## the spec's ".84 -> .34" step.
##
## investigation_progress is asserted alongside the suspicion drop because it is the
## SATURATION-FREE quantity: `suspicion` is squashed toward 1.0 by
## hotspot_saturation_rate, so a ratio of two suspicions understates how much belief
## actually went away, and tuning that rate would otherwise move this assertion.
func test_searching_a_hotspot_it_covers_takes_most_of_its_suspicion() -> void:
	var before: float = _hotspot_from_one_noise(Vector3.ZERO, 2.0).suspicion

	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0))
	_settle()

	var hotspot: SuspicionHotspot = _suspicion.get_strongest_hotspot()
	assert_gt(before, 0.4, "there was something to clear")
	assert_gt(hotspot.investigation_progress, 0.8, "and the sweep accounted for most of it")
	assert_lt(hotspot.suspicion, before * 0.4)


## Suspicion.md's worked example: after searching, "another unsearched portion of the
## hotspot still contains .52", and Behavior asks again and moves there.
func test_searching_the_middle_moves_the_best_unresolved_location_outward() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(Vector3.ZERO, 10.0)
	assert_almost_eq(
		_suspicion.get_best_unresolved_location(hotspot.id).length(),
		0.0,
		0.001,
		"unsearched, the middle is the best guess"
	)

	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 5.0))
	_settle()

	var next: Vector3 = _suspicion.get_best_unresolved_location(hotspot.id)
	assert_gt(next.length(), 4.5, "the creature already looked in the middle")
	assert_lt(next.length(), hotspot.radius + 0.1, "and the answer stays inside the hotspot")


## THE CENTRAL SPATIAL RULE. One sweep of a small part of a big vague area has checked
## a small fraction of where the player might be, and must not be allowed to rule out
## the rest of it.
## Measured with investigation_progress rather than with a ratio of suspicions:
## `suspicion` is saturated, so the same amount of belief cleared reads differently
## depending on how much there was, and this comparison is between two hotspots of
## deliberately different sizes.
func test_a_small_search_barely_dents_a_wide_vague_hotspot() -> void:
	_hotspot_from_one_noise(Vector3.ZERO, 12.0)
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 3.0))
	_settle()
	var vague_checked: float = _suspicion.get_strongest_hotspot().investigation_progress

	before_each()
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 3.0))
	_settle()
	var tight_checked: float = _suspicion.get_strongest_hotspot().investigation_progress

	assert_lt(vague_checked, 0.35, "most of the vague hotspot is still unchecked")
	assert_gt(tight_checked, 0.6, "the same search covered most of the tight one")


## DisconfirmationObservation carries which senses took part precisely so this can
## differ. A region checked by touch alone is not a region that has been searched.
func test_a_search_on_one_sense_clears_less_than_a_search_on_two() -> void:
	var only_vision: int = 1 << int(SuspicionEvidence.Sense.VISION)
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0, 0.9, only_vision))
	_settle()
	var half_blind: float = _suspicion.get_strongest_hotspot().suspicion

	before_each()
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0, 0.9))
	_settle()

	assert_lt(_suspicion.get_strongest_hotspot().suspicion, half_blind)


## "I heard drilling here" stays true forever. "Whatever made that noise is still here"
## is the only claim a search disconfirms -- which is why the record survives, and why
## the area can become interesting again later.
func test_the_evidence_survives_the_search_that_disconfirmed_it() -> void:
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	var strength_before: float = _suspicion.memory.records[0].effective_strength(_suspicion.clock)

	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 8.0))
	_settle()

	assert_eq(_suspicion.memory.records.size(), 1, "the observation is a historical fact")
	assert_almost_eq(
		_suspicion.memory.records[0].effective_strength(_suspicion.clock), strength_before, 0.01
	)


## A creature that can rule an area out permanently eventually rules out the whole
## level and stands still. Evidence decay is switched off here so the recovery is the
## only thing moving.
func test_a_searched_area_becomes_worth_reconsidering_over_time() -> void:
	_config.hearing_decay_rate = 0.0
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0))
	_settle()
	var just_searched: float = _suspicion.get_suspicion_near(Vector3.ZERO, 2.0)

	_advance_coarse(90.0)

	assert_gt(
		_suspicion.get_suspicion_near(Vector3.ZERO, 2.0),
		just_searched * 1.5,
		"the search went stale; the noise did not"
	)


func test_investigation_progress_rises_as_a_hotspot_is_searched() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(Vector3.ZERO, 4.0)
	assert_almost_eq(hotspot.investigation_progress, 0.0, 0.001)

	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 8.0))
	_settle()

	assert_gt(_suspicion.get_hotspot(hotspot.id).investigation_progress, 0.5)


## Behavior's "is this area still worth attention?" question, and the answer that lets
## it search systematically rather than circling one point.
func test_get_suspicion_near_falls_where_the_creature_looked_and_not_elsewhere() -> void:
	_hotspot_from_one_noise(Vector3.ZERO, 10.0)
	var searched_end := Vector3(0, 0, -8)
	var far_end := Vector3(0, 0, 8)
	var before_far: float = _suspicion.get_suspicion_near(far_end, 3.0)
	var now: float = _suspicion.clock
	var raw_before: float = _suspicion.memory.unresolved_at(searched_end, now)

	_suspicion.submit_disconfirmation(_search(searched_end, 5.0))
	_settle()

	# The raw quantity, because get_suspicion_near() is saturated and a 75% drop in
	# belief shows up there as a much smaller drop in the reported number.
	assert_lt(
		_suspicion.memory.unresolved_at(searched_end, _suspicion.clock),
		raw_before * 0.3,
		"the creature looked here"
	)
	assert_lt(_suspicion.get_suspicion_near(searched_end, 3.0), before_far, "and it shows")
	assert_almost_eq(
		_suspicion.get_suspicion_near(far_end, 3.0), before_far, 0.02, "and not over here"
	)


## Eventually the creature does get to stop. It takes actually searching the place.
func test_searching_a_hotspot_repeatedly_resolves_it() -> void:
	var hotspot_id: int = _hotspot_from_one_noise(Vector3.ZERO, 2.0).id

	for _sweep: int in 3:
		_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0))
		_settle()

	assert_eq(_resolved, [hotspot_id] as Array[int])
	assert_eq(_suspicion.get_hotspots().size(), 0)
	assert_eq(_suspicion.get_overall_suspicion(), 0.0)


func test_overlapping_searches_cannot_drive_belief_below_zero() -> void:
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	for _sweep: int in 6:
		_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0))
	_settle()

	assert_eq(_suspicion.get_overall_suspicion(), 0.0)
	assert_eq(_suspicion.get_suspicion_near(Vector3.ZERO, 4.0), 0.0)
	assert_gte(_suspicion.memory.unresolved_at(Vector3.ZERO, _suspicion.clock), 0.0)


func test_a_search_somewhere_else_entirely_changes_nothing() -> void:
	var before: float = _hotspot_from_one_noise(Vector3.ZERO, 3.0).suspicion

	_suspicion.submit_disconfirmation(_search(Vector3(80, 0, 0), 6.0))
	_settle()

	assert_almost_eq(_suspicion.get_strongest_hotspot().suspicion, before, 0.001)


## Behavior can race a hotspot_resolved and ask about an id that has just gone. Sending
## the creature to the world origin would look like a pathfinding bug.
func test_asking_for_an_unknown_hotspots_best_location_is_not_a_crash() -> void:
	assert_eq(_suspicion.get_best_unresolved_location(999), Vector3.ZERO)
	assert_null(_suspicion.get_hotspot(999))
