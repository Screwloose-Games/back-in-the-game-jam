extends GutTest

## SuspicionConfig's defaults and its cross-field rules.
##
## Named test_suspicion_config.gd rather than test_config.gd because the perception
## module already has one and GUT collects both suites in a single run.
##
## Every rule in invariant_failures() describes a setting that produces a WORKING but
## nonsensical creature: nothing errors, nothing crashes, and the alien is quietly
## broken in a way that reads as a bug in Behavior.


func test_a_bare_config_is_fully_usable() -> void:
	var config := SuspicionConfig.new()
	assert_eq(config.invariant_failures().size(), 0, "the shipped defaults must be self-consistent")
	assert_gt(config.max_evidence_count, 0)
	assert_gt(config.hotspot_sample_count, 0)


func test_a_suspicion_with_no_config_at_all_does_not_crash() -> void:
	var suspicion: CreatureSuspicion = autofree(CreatureSuspicion.new())
	suspicion.config = null

	suspicion.submit_evidence(
		SuspicionEvidence.make(SuspicionEvidence.Sense.HEARING, Vector3.ZERO, 4.0, 1.0, 1.0, 0.0)
	)
	suspicion.advance(1.0)

	assert_eq(suspicion.get_overall_suspicion(), 0.0)
	assert_eq(suspicion.get_hotspots().size(), 0)
	assert_null(suspicion.get_strongest_hotspot())


func test_decay_rates_are_per_sense() -> void:
	var config := SuspicionConfig.new()
	assert_eq(config.decay_rate_for(SuspicionEvidence.Sense.HEARING), config.hearing_decay_rate)
	assert_eq(config.decay_rate_for(SuspicionEvidence.Sense.VISION), config.vision_decay_rate)
	assert_eq(config.decay_rate_for(SuspicionEvidence.Sense.TOUCH), config.touch_decay_rate)
	assert_eq(config.weight_for(SuspicionEvidence.Sense.VISION), config.vision_weight)


func test_a_search_on_no_senses_earns_no_credit() -> void:
	var config := SuspicionConfig.new()
	assert_eq(config.disconfirmation_sense_scale(0), 0.0)
	assert_eq(config.disconfirmation_sense_scale(2), 1.0)
	assert_eq(config.disconfirmation_sense_scale(9), 1.0, "and it cannot exceed full credit")
	assert_lt(config.disconfirmation_sense_scale(1), 1.0)


func test_saturation_stays_inside_zero_to_one_for_any_amount_of_evidence() -> void:
	var config := SuspicionConfig.new()
	assert_eq(config.saturate(0.0, 1.2), 0.0)
	assert_lt(config.saturate(1000.0, 1.2), 1.0001)
	assert_gt(config.saturate(1000.0, 1.2), 0.99)
	assert_gt(config.saturate(2.0, 1.2), config.saturate(1.0, 1.2), "more is always more")


## exp() of a POSITIVE exponent. The record grows without bound, the creature becomes
## permanently and increasingly certain about a footstep it heard once, and nothing
## anywhere errors.
func test_a_negative_decay_rate_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.hearing_decay_rate = -0.1
	assert_string_contains(config.invariant_failures()[0], "hearing_decay_rate")


func test_a_saturation_rate_of_zero_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.hotspot_saturation_rate = 0.0
	assert_gt(config.invariant_failures().size(), 0, "every hotspot would read 0 suspicion")


func test_a_resolved_threshold_of_one_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.resolved_hotspot_threshold = 1.0
	assert_gt(config.invariant_failures().size(), 0, "every hotspot resolves as it forms")


func test_a_retention_floor_of_one_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.evidence_min_retention_strength = 1.0
	assert_gt(config.invariant_failures().size(), 0, "nothing would ever be remembered")


func test_a_merge_distance_larger_than_any_hotspot_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.hotspot_merge_distance = 60.0
	config.hotspot_max_radius = 5.0
	assert_gt(config.invariant_failures().size(), 0)


func test_zero_association_gain_is_reported() -> void:
	var config := SuspicionConfig.new()
	config.source_association_gain = 0.0
	assert_gt(config.invariant_failures().size(), 0, "nothing would ever be attributed")
