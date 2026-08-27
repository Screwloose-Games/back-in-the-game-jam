extends McpTestSuite

## PlayerSettings' cross-field rules, which nothing tested before this file.
##
## Every rule in invariant_failures() describes a setting that produces a WORKING but
## nonsensical suit: nothing errors, nothing crashes, and the run is quietly the wrong
## shape. The shipped .tres is asserted alongside the defaults because its overrides
## are where a designer actually breaks one.

const SETTINGS_PATH := "res://prefabs/character/player/player_settings.tres"


func suite_name() -> String:
	return "player_settings"


func test_the_shipped_defaults_are_self_consistent() -> void:
	assert_eq(PlayerSettings.new().invariant_failures().size(), 0)


func test_the_shipped_resource_is_self_consistent() -> void:
	var settings: PlayerSettings = load(SETTINGS_PATH)
	assert_true(settings != null, "player_settings.tres must load")
	assert_eq(settings.invariant_failures().size(), 0, "the overrides must be green too")


## Health would outrun the drain and an empty tank would be a permanent inconvenience
## rather than a way to die.
func test_suffocation_that_cannot_beat_recovery_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.suffocation_damage_per_second = 1.0
	settings.health_regen_per_second = 2.0
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "suffocation_damage_per_second")


## The cliff the pool exists to replace, back again.
func test_suffocation_that_kills_too_fast_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.suffocation_damage_per_second = 40.0
	assert_gt(settings.invariant_failures().size(), 0)


## Pillar 1: only the stalker kills outright.
func test_a_gas_pod_that_kills_outright_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.hazard_gas_pod_damage = settings.max_health
	assert_gt(settings.invariant_failures().size(), 0)


func test_an_arc_that_empties_the_suit_too_fast_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.hazard_arc_power_drain_per_second = 90.0
	assert_gt(settings.invariant_failures().size(), 0)


func test_a_deadband_past_the_reference_speed_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.impact_damage_min_speed = settings.impact_reference_speed
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "impact_damage_min_speed")


func test_a_zero_rate_reports_no_time_rather_than_dividing_by_zero() -> void:
	var settings := PlayerSettings.new()
	settings.suffocation_damage_per_second = 0.0
	settings.hazard_arc_power_drain_per_second = 0.0
	assert_eq(settings.seconds_of_suffocation(), INF)
	assert_eq(settings.seconds_of_arc_drain(), INF)


func test_impact_damage_is_priced_off_the_shared_reference_speed() -> void:
	var settings := PlayerSettings.new()
	var at_reference := settings.impact_damage_for(-settings.impact_reference_speed)
	assert_true(absf(at_reference - settings.impact_damage_at_reference_speed) < 0.0001)
	assert_eq(settings.impact_damage_for(-1.0), 0.0, "a scrape is not a hit")


## Under this the contact trigger fires first, the proximity countdown never gets a turn,
## and a gas pod loses its entire warning without erroring. Exactly the bug the shipped
## 0.55 m contact sphere caused before it was tightened.
func test_a_trigger_range_inside_the_bubble_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.hazard_gas_pod_trigger_range = settings.gas_pod_contact_distance()
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "hazard_gas_pod_trigger_range")


func test_a_wider_bubble_pushes_the_trigger_range_floor_out() -> void:
	var settings := PlayerSettings.new()
	var narrow := settings.gas_pod_contact_distance()
	settings.hazard_gas_pod_diameter *= 2.0
	assert_gt(settings.gas_pod_contact_distance(), narrow)
	assert_gt(settings.invariant_failures().size(), 0, "and the shipped range no longer clears it")


## Wearing one would then cost nothing: regeneration would quietly pay the whole bill and
## the encounter would be a noise with no price attached.
func test_a_clinger_that_cannot_outpace_recovery_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_health_drain_per_second = settings.health_regen_per_second
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_health_drain_per_second")


## Pillar 1 again, from the other side. Shedding one is escape; a clinger that empties the
## pool before you can finish mashing is an ending, and endings belong to the stalker.
func test_a_clinger_that_kills_too_fast_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_health_drain_per_second = 19.0
	assert_gt(settings.invariant_failures().size(), 0)


## It would leap from further than the beam reaches, so the laser could never be an answer
## to one and requirement seven would be unreachable in play.
func test_a_leap_from_outside_beam_range_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_jump_range = settings.mining_range + 1.0
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_jump_range")


## "Slowly, visibly, on the rock -- you can outrun it" is the whole counter, and it is one
## slider away from not being true.
func test_a_clinger_that_cannot_be_outrun_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_crawl_speed = settings.max_speed
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_crawl_speed")


func test_a_zero_clinger_drain_reports_forever_rather_than_dividing_by_zero() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_health_drain_per_second = 0.0
	assert_eq(settings.seconds_of_clinger_grip(), INF)


## A shed one that circles wider than it can leap never attacks again, and the encounter
## quietly ends with the creature still on screen.
func test_the_orbit_stays_inside_leap_range() -> void:
	var settings := PlayerSettings.new()
	assert_true(settings.clinger_orbit_radius() < settings.clinger_jump_range)
