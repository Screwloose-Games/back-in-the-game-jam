extends GutTest

## BehaviorConfig's defaults and its cross-field rules.
##
## Named test_behavior_config.gd rather than test_config.gd because perception and
## navigation already have one each and GUT collects every suite in a single run.
##
## Every rule in invariant_failures() describes a setting that produces a WORKING but
## nonsensical creature: nothing errors, nothing crashes, and the alien is quietly broken in
## a way that reads as a bug somewhere else entirely.


func test_a_bare_config_is_fully_usable() -> void:
	var config := BehaviorConfig.new()
	assert_eq(config.invariant_failures().size(), 0, "the shipped defaults must be self-consistent")
	assert_gt(config.nest_dwell_s, 0.0)
	assert_gt(config.search_half_extent, 0.0)


## The shipped defaults have to agree with the shipped PerceptionConfig too, or a searching
## alien is blind and nothing says so.
func test_the_defaults_agree_with_a_default_perception_config() -> void:
	var failures: PackedStringArray = BehaviorConfig.new().invariant_failures(
		PerceptionConfig.new()
	)
	assert_eq(failures.size(), 0, "; ".join(failures))


func test_the_measured_prototype_values_carried_across() -> void:
	var config := BehaviorConfig.new()
	assert_eq(config.investigate_threshold, 0.25)
	assert_eq(config.investigate_timeout_s, 45.0)
	assert_eq(config.nest_dwell_s, 4.0)
	assert_eq(config.arrive_distance, 3.0)
	assert_eq(config.search_half_extent, 4.0)


func test_alertness_is_answered_for_every_state() -> void:
	var config := BehaviorConfig.new()
	assert_eq(config.alertness_for(CreatureState.State.UNALERTED), config.alertness_unalerted)
	assert_eq(
		config.alertness_for(CreatureState.State.INVESTIGATING), config.alertness_investigating
	)
	assert_eq(config.alertness_for(CreatureState.State.HUNTING), config.alertness_hunting)
	assert_eq(config.alertness_for(CreatureState.State.RETREATING), config.alertness_retreating)


## Below the vision gate on purpose: an alien walking away genuinely stops looking for you.
func test_a_retreating_creature_is_below_the_vision_gate() -> void:
	var config := BehaviorConfig.new()
	assert_false(PerceptionConfig.new().vision_gate(config.alertness_retreating))


func test_the_threshold_shift_is_clamped_and_scaled() -> void:
	var config := BehaviorConfig.new()
	assert_almost_eq(config.threshold_shift(1.0), config.bias_span, 0.001)
	assert_almost_eq(config.threshold_shift(-1.0), -config.bias_span, 0.001)
	assert_almost_eq(config.threshold_shift(50.0), config.bias_span, 0.001, "bias must clamp")
	assert_eq(config.threshold_shift(0.0), 0.0)


## `set_goal` nulls the route AND resets navigation's 2 s stuck watchdog, so re-issuing more
## often than that disables the only backstop against a wedged alien. Silent, and it presents
## as a creature standing still forever with a trip count of zero.
func test_a_goal_refresh_below_the_watchdog_window_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.goal_refresh_m = 0.5
	assert_string_contains(config.invariant_failures()[0], "goal_refresh_m")


func test_the_minimum_goal_refresh_matches_navigations_replan_threshold() -> void:
	assert_eq(
		BehaviorConfig.MINIMUM_GOAL_REFRESH_M,
		NavigationConfig.new().target_move_threshold,
		"below navigation's own drift threshold, Behavior is worse than doing nothing"
	)


func test_an_investigate_threshold_under_the_attention_floor_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.investigate_threshold = 0.01
	config.attention_floor = 0.5
	assert_gt(config.invariant_failures().size(), 0, "it would investigate and give up at once")


## Hunting straight out of calm must not be EASIER than hunting mid-investigation.
func test_a_direct_hunt_threshold_below_the_hunt_threshold_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.direct_hunt_threshold = 0.1
	assert_gt(config.invariant_failures().size(), 0)


## A fixed lurk is something the player counts, and a tunnel with a known safe interval
## stops being a gamble.
func test_a_fixed_lurk_duration_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.lurk_min_s = 8.0
	config.lurk_max_s = 8.0
	assert_gt(config.invariant_failures().size(), 0)


func test_an_inverted_lurk_range_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.lurk_min_s = 20.0
	config.lurk_max_s = 2.0
	assert_gt(config.invariant_failures().size(), 0)


func test_a_lurk_duration_lands_inside_its_range() -> void:
	var config := BehaviorConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 20:
		assert_between(config.lurk_duration(rng), config.lurk_min_s, config.lurk_max_s)


## The backstop must not fire before the retreat is allowed to end normally.
func test_a_retreat_cap_below_its_floor_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.retreat_max_s = 2.0
	config.retreat_min_s = 10.0
	assert_gt(config.invariant_failures().size(), 0)


## Below the vision gate a searching alien is blind, and each search clears half as much
## because the VISION bit drops out of the disconfirmation mask.
func test_a_blind_investigating_alertness_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.alertness_investigating = 0.0
	var failures: PackedStringArray = config.invariant_failures(PerceptionConfig.new())
	assert_gt(failures.size(), 0)
	assert_string_contains(failures[0], "alertness_investigating")


func test_a_contact_grace_shorter_than_a_vision_interval_is_reported() -> void:
	var config := BehaviorConfig.new()
	config.visual_contact_grace_s = 0.05
	assert_gt(config.invariant_failures(PerceptionConfig.new()).size(), 0)


## The perception rules are skipped rather than guessed at when there is no companion config
## to check against.
func test_the_perception_rules_are_silent_without_a_perception_config() -> void:
	var config := BehaviorConfig.new()
	config.alertness_investigating = 0.0
	assert_eq(config.invariant_failures().size(), 0)
