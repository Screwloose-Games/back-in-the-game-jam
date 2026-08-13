extends GutTest

## PerceptionConfig (perception.md section 27), and in particular the null-Curve
## trap that would otherwise crash a sense rather than a resource loader.


func test_a_bare_config_is_fully_usable() -> void:
	var config := PerceptionConfig.new()
	assert_eq(
		config.invariant_failures(),
		PackedStringArray(),
		"a config nobody has touched must not already be broken"
	)
	assert_true(config.hearing_enabled)
	assert_true(config.vision_enabled)
	assert_gt(config.hearing_max_range, 0.0)


## THE TRAP. `hearing_distance_falloff` is an exported Curve, so it defaults to null
## on every fresh config and on every .tres authored before anyone drew the curve.
## sample_baked() on null is a hard crash inside hearing, which surfaces as "the
## alien went deaf" rather than as a missing resource.
func test_distance_falloff_works_with_no_curve_assigned() -> void:
	var config := PerceptionConfig.new()
	assert_null(config.hearing_distance_falloff, "null is the default and the common case")

	assert_almost_eq(config.distance_falloff(0.0), 1.0, 0.001, "full strength at the ear")
	assert_almost_eq(config.distance_falloff(1.0), 0.0, 0.001, "nothing at max range")
	var previous: float = 2.0
	for step: int in 11:
		var value: float = config.distance_falloff(float(step) / 10.0)
		assert_lt(value, previous, "falloff must decrease monotonically")
		previous = value


func test_distance_falloff_clamps_out_of_range_input() -> void:
	var config := PerceptionConfig.new()
	assert_eq(config.distance_falloff(-5.0), config.distance_falloff(0.0))
	assert_eq(config.distance_falloff(99.0), config.distance_falloff(1.0))


func test_an_assigned_curve_replaces_the_analytic_default() -> void:
	var config := PerceptionConfig.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	config.hearing_distance_falloff = curve

	assert_almost_eq(
		config.distance_falloff(1.0), 1.0, 0.01, "a flat curve means no attenuation at all"
	)
	assert_ne(
		config.distance_falloff(1.0),
		PerceptionConfig.new().distance_falloff(1.0),
		"which is visibly different from the analytic default"
	)


## Section 14: alertness changes how hard the creature looks, and nothing else.
func test_alertness_shortens_the_vision_interval() -> void:
	var config := PerceptionConfig.new()
	# almost_eq, not eq: lerpf(0.6, 0.1, 1.0) lands on 0.09999999999999998, and the
	# failure message prints "expected [0.1] to equal [0.1]".
	assert_almost_eq(config.vision_scan_interval(0.0), config.vision_scan_interval_calm, 0.0001)
	assert_almost_eq(config.vision_scan_interval(1.0), config.vision_scan_interval_alert, 0.0001)
	assert_lt(
		config.vision_scan_interval(1.0),
		config.vision_scan_interval(0.0),
		"an alert creature scans more often, not less"
	)


func test_vision_gate_follows_activation_threshold() -> void:
	var config := PerceptionConfig.new()
	config.vision_activation_suspicion = 0.5

	assert_false(config.vision_gate(0.0), "section 14: low suspicion, vision disabled")
	assert_false(config.vision_gate(0.49))
	assert_true(config.vision_gate(0.5), "the threshold is inclusive")
	assert_true(config.vision_gate(1.0))

	config.vision_enabled = false
	assert_false(config.vision_gate(1.0), "the master switch beats the threshold")


func test_scan_duration_interpolates_on_thoroughness() -> void:
	var config := PerceptionConfig.new()
	assert_eq(config.scan_duration(0.0), config.search_scan_duration_min)
	assert_eq(config.scan_duration(1.0), config.search_scan_duration_max)
	assert_gt(config.scan_duration(1.0), config.scan_duration(0.0))


## A scan budgeted zero probes can never find anything, so it would always
## disconfirm -- a confidently wrong answer rather than a cheap one.
func test_scan_sample_count_is_never_zero() -> void:
	var config := PerceptionConfig.new()
	assert_eq(config.scan_sample_count(0.0), 1)
	assert_eq(config.scan_sample_count(-3.0), 1)
	assert_eq(config.scan_sample_count(1.0), config.max_scan_samples)


func test_invariant_failures_catches_a_zero_world_mask() -> void:
	var config := PerceptionConfig.new()
	config.world_mask = 0
	var failures := config.invariant_failures()
	assert_eq(failures.size(), 1)
	assert_string_contains(failures[0], "world_mask")


func test_invariant_failures_catches_inverted_uncertainty_bounds() -> void:
	var config := PerceptionConfig.new()
	config.hearing_min_uncertainty = 20.0
	config.hearing_max_uncertainty = 2.0
	assert_eq(config.invariant_failures().size(), 1)


## An alert interval slower than the calm one inverts section 14 without erroring:
## the creature would pay LESS attention the more suspicious it got.
func test_invariant_failures_catches_inverted_scan_intervals() -> void:
	var config := PerceptionConfig.new()
	config.vision_scan_interval_calm = 0.1
	config.vision_scan_interval_alert = 0.6
	var failures := config.invariant_failures()
	assert_eq(failures.size(), 1)
	assert_string_contains(failures[0], "alertness would slow scanning")
