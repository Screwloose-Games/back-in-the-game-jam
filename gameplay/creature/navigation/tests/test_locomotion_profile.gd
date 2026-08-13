extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## LocomotionProfile, and the section 43 scenarios NavigationConfig pins on its behalf.
##
## THE LEAP SCENARIOS ARE THE POINT OF THIS FILE. Section 11.4 asks that a leap become
## attractive at "approximately 10 m of crawling saved" and leaves the number to us, so
## the only thing between `leap_bias` and an alien that leaps across every room is
## somebody remembering. Section 43 wrote the two cases down, `NavigationConfig` turns
## them into invariants, and `verify_navigation_static.gd` runs them on every build.
##
## An invariant nothing can trip is not an invariant, so each one below is checked in
## both directions: the shipped defaults satisfy it, and a plausible mistuning breaks it.


func test_the_shipped_defaults_satisfy_every_locomotion_invariant() -> void:
	assert_eq(
		LocomotionProfile.new().invariant_failures(),
		PackedStringArray(),
		"the defaults a bare CreatureNavigation runs on must themselves be valid"
	)


# ----- section 43, scenarios D and E -----


func test_scenario_d_prefers_a_twenty_metre_leap_to_a_thirty_metre_crawl() -> void:
	var config := NavigationConfig.new()
	assert_lt(
		config.locomotion_profile.leap_travel_time(20.0),
		config.normal_travel_time(30.0),
		"section 43 Scenario D: the alien should take the shortcut across the chamber"
	)


func test_scenario_e_keeps_crawling_when_the_leap_saves_only_three_metres() -> void:
	var config := NavigationConfig.new()
	assert_gt(
		config.locomotion_profile.leap_travel_time(18.0),
		config.normal_travel_time(21.0),
		"section 43 Scenario E: leap overhead outweighs 3 m saved, so it keeps crawling"
	)


## The failure mode this pair exists to catch, from the too-keen side.
func test_a_leap_bias_of_zero_breaks_scenario_e_and_says_so() -> void:
	var config := NavigationConfig.new()
	config.locomotion_profile.leap_bias = 0.0
	var failures: PackedStringArray = config.invariant_failures()
	assert_gt(failures.size(), 0, "with no bias at all the alien leaps everywhere")
	assert_true(
		_mentions(failures, "Scenario E"),
		"the failure has to name the scenario, or nobody knows what they broke"
	)


## And from the too-timid side, which is the quieter of the two: the alien simply never
## uses zero gravity for anything and nothing anywhere reports a problem.
func test_an_enormous_leap_bias_breaks_scenario_d_and_says_so() -> void:
	var config := NavigationConfig.new()
	config.locomotion_profile.leap_bias = 4.0
	var failures: PackedStringArray = config.invariant_failures()
	assert_gt(failures.size(), 0, "a leap that always loses is a leap system nobody sees")
	assert_true(_mentions(failures, "Scenario D"), "the failure has to name the scenario")


func test_section_eleven_one_puts_no_ceiling_on_leap_distance() -> void:
	var profile := LocomotionProfile.new()
	assert_gt(
		profile.leap_travel_time(200.0),
		profile.leap_travel_time(20.0),
		"cost must keep rising with distance rather than saturating or rejecting"
	)


# ----- the cost model and the controllers must agree -----


func test_a_crawler_slower_than_routing_believes_is_rejected() -> void:
	_config.locomotion_profile.crawl_max_speed = _config.normal_speed + 1.0
	assert_true(
		_mentions(_config.invariant_failures(), "crawl_max_speed"),
		"routing would charge a travel time the body cannot deliver, on every route"
	)


func test_a_squeeze_penalty_that_does_not_cover_both_transitions_is_rejected() -> void:
	_config.squeeze_transition_penalty = 0.5
	_config.locomotion_profile.squeeze_transition_time = 0.6
	assert_true(
		_mentions(_config.invariant_failures(), "squeeze_transition_penalty"),
		"compressing and decompressing are both paid for, or squeezes look cheap"
	)


# ----- section 9.3 hysteresis -----


func test_a_single_enclosure_threshold_is_rejected() -> void:
	_config.locomotion_profile.tunnel_enter_enclosure = 0.5
	_config.locomotion_profile.tunnel_exit_enclosure = 0.5
	assert_true(
		_mentions(_config.invariant_failures(), "tunnel_exit_enclosure"),
		"one threshold makes the mode flicker every frame at a tunnel mouth"
	)


# ----- section 22 turn geometry -----


func test_turn_angle_is_arc_geometry_rather_than_a_fudge_factor() -> void:
	# A body at 5 m/s for 0.5 s covers 2.5 m; on a 2.5 m radius that is exactly 1 radian.
	assert_almost_eq(LocomotionProfile.max_turn_angle(5.0, 0.5, 2.5), 1.0, 0.0001)


func test_a_faster_body_turns_less_sharply_over_the_same_distance() -> void:
	var slow: float = LocomotionProfile.max_turn_angle(1.0, 0.1, 2.5)
	var fast: float = LocomotionProfile.max_turn_angle(8.0, 0.1, 2.5)
	assert_lt(slow, fast, "per tick a faster body sweeps through more of the arc")


func test_a_stationary_body_is_unconstrained() -> void:
	assert_almost_eq(
		LocomotionProfile.max_turn_angle(0.0, 0.1, 2.5),
		PI,
		0.0001,
		"turn radius is a consequence of momentum, and at rest there is none"
	)


func test_turning_is_never_more_than_a_half_turn_per_tick() -> void:
	assert_almost_eq(
		LocomotionProfile.max_turn_angle(500.0, 1.0, 0.1),
		PI,
		0.0001,
		"beyond half a turn the clamp stops meaning anything and starts wrapping"
	)


func _mentions(failures: PackedStringArray, fragment: String) -> bool:
	for line: String in failures:
		if line.contains(fragment):
			return true
	return false
