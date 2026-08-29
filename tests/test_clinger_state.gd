extends McpTestSuite

## ClingerState: every guard between the clinger's six phases, with no scene.
##
## The two that carry the design are `hears` and `can_leap`. Hearing is what makes "you can
## go quiet and it loses you" true rather than aspirational, and the cooldown is measured
## from the frame a leap STARTS -- measured from the landing instead, a clinger that misses
## and lands next to you attacks again immediately, which is a different creature.

const EPSILON := 0.0001

## The shipped figures, so a default that drifts fails here rather than in a playtest.
const WAKE := 2.0
const METRES_PER_UNIT := 4.0
const HEARING_RANGE := 30.0


func suite_name() -> String:
	return "clinger_state"


func test_a_loud_noise_nearby_wakes_it() -> void:
	assert_true(_hears(6.0, 10.0), "full thrust at ten metres did not wake it")


func test_a_quiet_noise_never_wakes_it_however_close() -> void:
	assert_false(_hears(WAKE - 0.5, 0.5), "a whisper on top of it woke it")


func test_a_noise_carries_only_as_far_as_its_own_strength() -> void:
	# 3.0 units at 4 m per unit reaches 12 m and no further.
	assert_true(_hears(3.0, 11.0), "inside the radius went unheard")
	assert_false(_hears(3.0, 13.0), "outside the radius was heard anyway")


## A creature that answers every noise in the level is never escaped, only outrun.
func test_hearing_range_caps_a_noise_loud_enough_to_carry_further() -> void:
	assert_false(_hears(20.0, HEARING_RANGE + 5.0), "an 80 m noise reached past the ear")
	assert_true(_hears(20.0, HEARING_RANGE - 1.0), "a loud close noise went unheard")


func test_it_will_not_leap_while_the_cooldown_is_live() -> void:
	assert_false(ClingerState.can_leap(0.1, 1.0, 4.0), "leapt during the cooldown")
	assert_true(ClingerState.can_leap(0.0, 1.0, 4.0), "did not leap once the cooldown cleared")


func test_it_will_not_leap_from_outside_its_range() -> void:
	assert_true(ClingerState.can_leap(0.0, 4.0, 4.0), "the boundary should be reachable")
	assert_false(ClingerState.can_leap(0.0, 4.01, 4.0), "leapt from past its range")


func test_an_escape_leap_needs_a_stuck_body_and_a_clear_cooldown() -> void:
	var crawling := ClingerState.Phase.CRAWLING
	assert_true(ClingerState.can_surface_leap(0.0, true, crawling), "a stuck body did not escape")
	assert_false(ClingerState.can_surface_leap(0.1, true, crawling), "escaped during the cooldown")
	assert_false(ClingerState.can_surface_leap(0.0, false, crawling), "escaped without being stuck")


## A clinger thrashing on a rock beside you is the most visible way this fails, so circling
## is not exempt. Everything else is either not navigating or not on a surface.
func test_a_crawling_or_orbiting_clinger_escape_leaps_and_nothing_else_does() -> void:
	for phase: ClingerState.Phase in [ClingerState.Phase.CRAWLING, ClingerState.Phase.ORBITING]:
		assert_true(
			ClingerState.can_surface_leap(0.0, true, phase),
			"a stuck %s clinger stayed stuck" % ClingerState.phase_name(phase)
		)
	for phase: ClingerState.Phase in [
		ClingerState.Phase.DORMANT,
		ClingerState.Phase.LEAPING,
		ClingerState.Phase.ATTACHED,
		ClingerState.Phase.DEAD,
		ClingerState.Phase.SURFACE_LEAPING,
	]:
		assert_false(
			ClingerState.can_surface_leap(0.0, true, phase),
			"a %s clinger escape-leapt" % ClingerState.phase_name(phase)
		)


## Shared, getting unstuck would silently cost the creature its next attack -- and a stuck
## clinger is one the player has already been ignoring.
func test_the_escape_cooldown_is_not_the_attack_cooldown() -> void:
	assert_true(
		ClingerState.can_surface_leap(0.0, true, ClingerState.Phase.CRAWLING),
		"the escape clock was not its own"
	)
	assert_true(ClingerState.can_leap(0.0, 1.0, 4.0), "and the pounce should be unaffected")


func test_the_peel_walks_from_nothing_to_all_of_it() -> void:
	assert_true(absf(ClingerState.peel_fraction(0, 4)) < EPSILON, "a fresh grip was already open")
	assert_true(absf(ClingerState.peel_fraction(2, 4) - 0.5) < EPSILON, "half is not half")
	assert_true(absf(ClingerState.peel_fraction(4, 4) - 1.0) < EPSILON, "the last press fell short")


## The shed has already happened; a player still mashing must not push it past full and
## invert the pose it is animating toward.
func test_mashing_past_the_count_does_not_overfill_it() -> void:
	assert_true(absf(ClingerState.peel_fraction(40, 4) - 1.0) < EPSILON, "the peel overfilled")


func test_a_count_of_zero_reports_open_rather_than_dividing_by_zero() -> void:
	assert_true(absf(ClingerState.peel_fraction(0, 0) - 1.0) < EPSILON, "a zero count divided")


## Nothing a hazard bills may come back negative, or a clinger would heal the suit it is
## sitting on.
func test_billing_is_never_negative() -> void:
	assert_true(absf(ClingerState.bill(-5.0, 0.1)) < EPSILON, "a negative rate paid out")
	assert_true(absf(ClingerState.bill(5.0, -0.1)) < EPSILON, "a negative step paid out")
	assert_true(absf(ClingerState.bill(6.0, 0.5) - 3.0) < EPSILON, "the ordinary case is wrong")


func test_the_orbit_never_outruns_the_body_chasing_it() -> void:
	var radius := 4.0
	var step := ClingerState.orbit_step(1.1, radius, 0.1)
	assert_true(absf(step * radius - 1.1 * 0.1) < EPSILON, "the goal moved at the wrong speed")


func test_a_zero_radius_orbit_does_not_divide_by_zero() -> void:
	assert_true(is_finite(ClingerState.orbit_step(1.1, 0.0, 0.1)), "a zero radius produced INF")


func test_every_phase_has_a_name() -> void:
	for phase: int in ClingerState.Phase.values():
		assert_ne(ClingerState.phase_name(phase), "", "phase %d has no name" % phase)


func _hears(strength: float, distance: float) -> bool:
	return ClingerState.hears(
		strength, Vector3(distance, 0.0, 0.0), Vector3.ZERO, WAKE, METRES_PER_UNIT, HEARING_RANGE
	)
