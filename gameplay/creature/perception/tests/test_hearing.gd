extends GutTest

## CreatureHearing (perception.md sections 11-12).
##
## The strength arithmetic is the easy half. The half that matters is the
## uncertainty: a faint, distant or muffled noise must report a WIDER possible
## origin and a DISPLACED point, because that is the only thing stopping Suspicion
## from receiving magically precise coordinates from a sound in the dark.

var _config: PerceptionConfig = null
var _hearing: CreatureHearing = null


func before_each() -> void:
	_config = PerceptionConfig.new()
	_hearing = CreatureHearing.new()
	_hearing.config = _config
	# Pinned, so jittered positions are reproducible run to run.
	_hearing.rng = RandomNumberGenerator.new()
	_hearing.rng.seed = 12345


func _noise(at: Vector3, loudness: float = 1.0) -> NoiseEvent:
	return NoiseEvent.make(at, loudness, &"drill")


# ----- received strength (section 11's four-term product) -----


func test_strength_falls_monotonically_with_distance() -> void:
	var previous: float = 2.0
	for metres: int in range(0, 41, 4):
		var received := CreatureHearing.received_strength(1.0, float(metres), 0.0, _config)
		assert_lt(received, previous, "strength must fall as distance grows")
		previous = received


func test_nothing_is_heard_beyond_max_range() -> void:
	assert_eq(
		CreatureHearing.received_strength(1.0, _config.hearing_max_range + 0.1, 0.0, _config), 0.0
	)


func test_obstruction_attenuates_rather_than_blocks() -> void:
	var clear := CreatureHearing.received_strength(1.0, 10.0, 0.0, _config)
	var half := CreatureHearing.received_strength(1.0, 10.0, 0.5, _config)
	var blocked := CreatureHearing.received_strength(1.0, 10.0, 1.0, _config)

	assert_lt(half, clear)
	assert_lt(blocked, half)
	assert_gt(blocked, 0.0, "a wall muffles sound; it does not make the creature deaf")
	assert_almost_eq(blocked, clear * _config.hearing_obstruction_multiplier, 0.0001)


func test_sensitivity_scales_the_whole_product() -> void:
	var normal := CreatureHearing.received_strength(1.0, 10.0, 0.0, _config)
	_config.hearing_sensitivity = 2.0
	var keen := CreatureHearing.received_strength(1.0, 10.0, 0.0, _config)
	assert_almost_eq(keen, minf(normal * 2.0, 1.0), 0.0001)


func test_louder_noise_is_received_more_strongly() -> void:
	var quiet := CreatureHearing.received_strength(0.2, 10.0, 0.0, _config)
	var loud := CreatureHearing.received_strength(1.0, 10.0, 0.0, _config)
	assert_gt(loud, quiet)


# ----- uncertainty (the point of the whole class) -----


func test_a_more_distant_noise_yields_a_wider_uncertainty() -> void:
	var previous: float = -1.0
	for metres: int in range(0, 41, 4):
		var distance := float(metres)
		var received := CreatureHearing.received_strength(1.0, distance, 0.0, _config)
		var uncertainty := CreatureHearing.estimate_uncertainty(received, distance, _config)
		assert_gt(uncertainty, previous, "distance must widen the possible-origin area")
		previous = uncertainty


func test_a_muffled_noise_yields_a_wider_uncertainty_than_a_clear_one() -> void:
	var clear := CreatureHearing.received_strength(1.0, 10.0, 0.0, _config)
	var muffled := CreatureHearing.received_strength(1.0, 10.0, 1.0, _config)
	assert_gt(
		CreatureHearing.estimate_uncertainty(muffled, 10.0, _config),
		CreatureHearing.estimate_uncertainty(clear, 10.0, _config)
	)


func test_uncertainty_stays_within_its_configured_bounds() -> void:
	for received: float in [0.0, 0.01, 0.5, 0.99, 1.0, 5.0]:
		for distance: float in [0.0, 20.0, 40.0, 500.0]:
			var uncertainty := CreatureHearing.estimate_uncertainty(received, distance, _config)
			assert_between(
				uncertainty, _config.hearing_min_uncertainty, _config.hearing_max_uncertainty
			)


## Section 11's own illustration: nearby drilling lands around a metre, distant
## footsteps land in a wide area.
func test_nearby_drilling_is_far_more_precise_than_distant_footsteps() -> void:
	var drill_received := CreatureHearing.received_strength(1.0, 1.0, 0.0, _config)
	var footstep_received := CreatureHearing.received_strength(0.25, 30.0, 0.0, _config)
	var drill := CreatureHearing.estimate_uncertainty(drill_received, 1.0, _config)
	var footsteps := CreatureHearing.estimate_uncertainty(footstep_received, 30.0, _config)

	assert_lt(drill, 3.0, "drilling next door is roughly locatable")
	assert_gt(footsteps, drill * 3.0, "distant footsteps are an area, not a point")


# ----- perceive_noise -----


func test_a_close_noise_produces_evidence_tagged_as_hearing() -> void:
	var evidence := _hearing.perceive_noise(_noise(Vector3(0, 0, 5)), Vector3.ZERO, 0.0, 7.5)

	assert_not_null(evidence)
	assert_eq(evidence.sense, SuspicionEvidence.Sense.HEARING)
	assert_eq(evidence.observed_at, 7.5, "the clock is handed in, never read")
	assert_eq(evidence.category, &"drill", "the event's tag passes through untouched")
	assert_gt(evidence.strength, 0.0)
	assert_gt(evidence.uncertainty_radius, 0.0)


func test_an_inaudible_noise_produces_nothing() -> void:
	var far_away := Vector3(0, 0, _config.hearing_max_range + 50.0)
	assert_null(
		_hearing.perceive_noise(_noise(far_away), Vector3.ZERO, 0.0, 0.0),
		"not hearing something is a real answer, not an error"
	)


func test_a_noise_below_the_detection_floor_produces_nothing() -> void:
	_config.hearing_min_detectable_strength = 0.95
	assert_null(_hearing.perceive_noise(_noise(Vector3(0, 0, 20)), Vector3.ZERO, 0.0, 0.0))


func test_disabling_hearing_produces_nothing() -> void:
	_config.hearing_enabled = false
	assert_null(_hearing.perceive_noise(_noise(Vector3.ZERO), Vector3.ZERO, 0.0, 0.0))

	_config.hearing_enabled = true
	_hearing.enabled = false
	assert_null(
		_hearing.perceive_noise(_noise(Vector3.ZERO), Vector3.ZERO, 0.0, 0.0),
		"the sense's own switch works independently of the config's"
	)


## THE ARCHITECTURAL ONE. The NoiseEvent knows exactly who drilled. Copying that
## through would hand Behavior a free target identification from a sound in the
## dark; section 8's hearing example reads "source: unknown".
func test_hearing_never_attributes_a_source_player() -> void:
	var player: Node = autofree(Node.new())
	var event := NoiseEvent.make(Vector3(0, 0, 3), 1.0, &"drill", player, player)

	var evidence := _hearing.perceive_noise(event, Vector3.ZERO, 0.0, 0.0)

	assert_not_null(evidence)
	assert_null(evidence.source_player, "hearing must not identify who made the noise")
	assert_eq(evidence.source_confidence, 0.0)


# ----- positional jitter -----


## Without displacement, hearing hands Suspicion an exact point alongside a note
## saying it might be twelve metres out -- and any consumer that reads the point and
## ignores the radius gets a perfectly omniscient alien for free.
func test_the_reported_origin_is_displaced_from_the_true_one() -> void:
	var truth := Vector3(0, 0, 25)
	var displaced: int = 0
	for _i: int in 20:
		var evidence := _hearing.perceive_noise(_noise(truth), Vector3.ZERO, 0.0, 0.0)
		assert_not_null(evidence)
		if evidence.position.distance_to(truth) > 0.001:
			displaced += 1
		assert_lte(
			evidence.position.distance_to(truth),
			evidence.uncertainty_radius + 0.001,
			"the displacement must stay inside the radius it reports"
		)
	assert_gt(displaced, 15, "a distant noise should almost always be mislocated")


func test_jitter_can_be_switched_off_for_an_exact_report() -> void:
	_config.hearing_position_jitter = 0.0
	var truth := Vector3(0, 0, 25)
	var evidence := _hearing.perceive_noise(_noise(truth), Vector3.ZERO, 0.0, 0.0)
	assert_eq(evidence.position, truth)


func test_the_same_seed_mishears_a_noise_identically() -> void:
	var first := _hearing.perceive_noise(_noise(Vector3(0, 0, 25)), Vector3.ZERO, 0.0, 0.0)

	var other := CreatureHearing.new()
	other.config = _config
	other.rng = RandomNumberGenerator.new()
	other.rng.seed = 12345
	var second := other.perceive_noise(_noise(Vector3(0, 0, 25)), Vector3.ZERO, 0.0, 0.0)

	assert_eq(first.position, second.position)


func test_confidence_rises_with_received_strength() -> void:
	var faint := CreatureHearing.estimate_confidence(
		_config.hearing_min_detectable_strength, _config
	)
	var strong := CreatureHearing.estimate_confidence(1.0, _config)
	assert_almost_eq(faint, 0.0, 0.001, "barely detectable is barely believable")
	assert_almost_eq(strong, 1.0, 0.001)
