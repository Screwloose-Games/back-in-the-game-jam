extends "res://gameplay/director/tests/director_test_case.gd"

## Menace -- the brake (director.md, "Two accumulators").
##
## Every weighted term in isolation, then the two traps that only show up downstream: a route
## that does not exist must read as NO pressure, and a target that cannot be reached must
## DRAIN the meter rather than merely slow it.


func test_a_creature_that_is_not_hunting_accrues_no_menace() -> void:
	_state(CreatureState.State.INVESTIGATING)
	_advance(10.0)
	assert_eq(_track().menace, 0.0, "menace rises only while HUNTING")


func test_a_hunt_with_no_contact_at_all_still_rises_on_the_clock() -> void:
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(10.0)
	assert_almost_eq(_track().menace, _config.w_time * 10.0, 0.002, "w_time is the floor")


func test_an_alien_with_no_route_reports_no_proximity_pressure() -> void:
	# THE TRAP THE MODULE README LEADS WITH. RouteFollower.distance_remaining returns 0.0
	# with no route, and a raw 0.0 through `1 - route/range` is MAXIMUM dread -- an alien
	# idling at a nest would breathe down your neck forever, with nothing in the log.
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(10.0)
	var with_no_route: float = _track().menace

	_track().end_encounter()
	_hunt(0.0, false)
	_advance(10.0)
	assert_gt(_track().menace, with_no_route, "a real route at zero metres is the pressure case")
	assert_almost_eq(with_no_route, _config.w_time * 10.0, 0.002, "no route contributes nothing")


func test_proximity_pressure_falls_off_across_menace_range() -> void:
	assert_almost_eq(_config.proximity_pressure(0.0), 1.0, 0.001, "arm's length is full pressure")
	assert_almost_eq(
		_config.proximity_pressure(_config.menace_range_m * 0.5), 0.5, 0.001, "half range, half"
	)
	assert_eq(_config.proximity_pressure(_config.menace_range_m), 0.0, "spent at the range")
	assert_eq(_config.proximity_pressure(999.0), 0.0, "and clamped beyond it")


func test_visual_contact_adds_its_own_term() -> void:
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(10.0)
	var unseen: float = _track().menace

	_track().end_encounter()
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, true)
	_advance(10.0)
	assert_almost_eq(_track().menace - unseen, _config.w_sight * 10.0, 0.002, "w_sight, exactly")


func test_an_open_attack_window_is_priced_as_a_sustained_window() -> void:
	# NOT AS AN IMPULSE. HuntingState puts the rate limit in a BtCooldown decorator OUTSIDE
	# the condition, deliberately, so `attack_window_open` stays true across the cooldown --
	# folding it in would leave the flag true for the single frame a strike fires and the
	# Director would price a whole encounter at roughly nothing.
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false, true)
	_advance(3.0)
	var expected: float = (_config.w_time + _config.w_attack) * 3.0
	assert_almost_eq(_track().menace, expected, 0.002, "three seconds in reach is three seconds")


func test_lurking_at_a_mouth_keeps_menace_climbing_with_nothing_in_sight() -> void:
	_hunt(2.0, false, false, true)
	_advance(10.0)
	assert_gt(_track().menace, 0.0, "a thing waiting outside your hole is delivering pressure")
	var rate: float = _config.w_time + _config.w_proximity * _config.proximity_pressure(2.0)
	assert_almost_eq(_track().menace, (rate + _config.w_lurk) * 10.0, 0.003, "w_lurk, exactly")


func test_an_unreachable_target_drains_menace_rather_than_merely_slowing_it() -> void:
	# The invariant behind w_stall > w_time + w_proximity. Without it a stalemate slowly
	# accrues a SATED exit and the game congratulates a player who did nothing.
	_hunt(0.0, true)
	_advance(20.0)
	var earned: float = _track().menace
	assert_gt(earned, 0.0, "the chase delivered something first")

	_hunt(0.0, false, false, false, false)
	_advance(10.0)
	assert_lt(_track().menace, earned, "an unreachable target takes pressure back off the board")


func test_menace_decays_the_moment_the_hunt_stops() -> void:
	_hunt(0.0, true)
	_advance(20.0)
	var earned: float = _track().menace

	_state(CreatureState.State.INVESTIGATING)
	_advance(5.0)
	assert_almost_eq(
		_track().menace, earned - _config.menace_relief_rate * 5.0, 0.003, "menace_relief_rate"
	)


func test_menace_is_clamped_to_the_ceiling_and_to_the_floor() -> void:
	_hunt(0.0, true, true)
	_advance(120.0)
	assert_eq(_track().menace, 1.0, "clamped at the ceiling rather than running past PEAK")

	_state(CreatureState.State.UNALERTED)
	_advance(300.0)
	assert_eq(_track().menace, 0.0, "and never negative")


func test_full_pressure_sates_inside_the_calibrated_window() -> void:
	# The calibration the config docstring quotes: 20 s at full pressure, 28 s typical. If
	# these move, the worked encounter no longer reproduces and the defaults need re-deriving.
	_hunt(0.0, true, true)
	_advance(19.0)
	assert_lt(_track().menace, 1.0, "not before 19 s")
	_advance(2.0)
	assert_eq(_track().menace, 1.0, "and reached by 21 s")


func test_bare_presence_cannot_sate_inside_the_stall_cap() -> void:
	# THE RULE THAT MAKES THE TWO EXITS MEAN DIFFERENT THINGS. A hunt delivering nothing but
	# its own duration must time out STALLED, never fill the meter and leave triumphantly.
	var reachable: float = _config.w_time * _config.hunt_max_duration_s
	assert_lt(reachable, _config.peak_threshold, "w_time alone cannot reach PEAK in the window")
