extends GutTest

## CreatureVision (perception.md section 13).
##
## Vision is the sense that must be switchable off without anything else in the AI
## noticing, so half of these tests are about the ways it declines to see.

const EYE := Transform3D.IDENTITY

var _config: PerceptionConfig = null
var _vision: CreatureVision = null


func before_each() -> void:
	_config = PerceptionConfig.new()
	_vision = CreatureVision.new()
	_vision.config = _config


## Godot's forward is -Z, which is also this project's model-facing convention.
func _ahead(metres: float) -> Vector3:
	return Vector3(0, 0, -metres)


# ----- cone geometry -----


func test_cone_alignment_reads_as_a_cosine() -> void:
	assert_almost_eq(CreatureVision.cone_alignment(Vector3.FORWARD, _ahead(5.0)), 1.0, 0.0001)
	assert_almost_eq(CreatureVision.cone_alignment(Vector3.FORWARD, Vector3(5, 0, 0)), 0.0, 0.0001)
	assert_almost_eq(CreatureVision.cone_alignment(Vector3.FORWARD, Vector3(0, 0, 5)), -1.0, 0.0001)


func test_cone_alignment_survives_a_zero_length_vector() -> void:
	assert_eq(CreatureVision.cone_alignment(Vector3.ZERO, _ahead(1.0)), 0.0)
	assert_eq(CreatureVision.cone_alignment(Vector3.FORWARD, Vector3.ZERO), 0.0)


# ----- visibility: each rejection independently drives it to zero -----


func test_line_of_sight_alone_drives_visibility_to_zero() -> void:
	assert_gt(CreatureVision.visibility(5.0, 1.0, true, 1.0, _config), 0.0)
	assert_eq(
		CreatureVision.visibility(5.0, 1.0, false, 1.0, _config),
		0.0,
		"sight through a wall is not dimmer sight; it is no sight"
	)


func test_range_alone_drives_visibility_to_zero() -> void:
	assert_gt(CreatureVision.visibility(_config.vision_range - 0.1, 1.0, true, 1.0, _config), 0.0)
	assert_eq(CreatureVision.visibility(_config.vision_range + 0.1, 1.0, true, 1.0, _config), 0.0)


func test_cone_alone_drives_visibility_to_zero() -> void:
	var half := _config.vision_angle * 0.5
	var inside := cos(half * 0.5)
	var outside := cos(half * 1.5)
	assert_gt(CreatureVision.visibility(5.0, inside, true, 1.0, _config), 0.0)
	assert_eq(CreatureVision.visibility(5.0, outside, true, 1.0, _config), 0.0)


func test_darkness_alone_drives_visibility_to_zero() -> void:
	assert_gt(CreatureVision.visibility(5.0, 1.0, true, 1.0, _config), 0.0)
	assert_eq(CreatureVision.visibility(5.0, 1.0, true, 0.0, _config), 0.0)


func test_visibility_decreases_with_distance_and_off_centredness() -> void:
	var close_centred := CreatureVision.visibility(2.0, 1.0, true, 1.0, _config)
	var far_centred := CreatureVision.visibility(15.0, 1.0, true, 1.0, _config)
	var close_edge := CreatureVision.visibility(
		2.0, cos(_config.vision_angle * 0.5), true, 1.0, _config
	)

	assert_lt(far_centred, close_centred, "farther is worse")
	assert_lt(close_edge, close_centred, "the edge of the cone is worse than the middle")
	assert_gt(close_edge, 0.0, "but the cone edge is not a wall")


func test_visibility_never_leaves_zero_to_one() -> void:
	for distance: float in [0.0, 1.0, 10.0, 17.9]:
		for alignment: float in [1.0, 0.9, 0.71]:
			var seen := CreatureVision.visibility(distance, alignment, true, 1.0, _config)
			assert_between(seen, 0.0, 1.0)


# ----- target selection -----


func test_an_explicit_target_list_wins_over_the_group() -> void:
	var explicit: Array[Node3D] = [autofree(Node3D.new())]
	var grouped: Array[Node3D] = [autofree(Node3D.new()), autofree(Node3D.new())]
	assert_eq(CreatureVision.choose_targets(explicit, grouped), explicit)


func test_the_group_is_the_fallback_when_nothing_is_wired() -> void:
	var grouped: Array[Node3D] = [autofree(Node3D.new())]
	assert_eq(CreatureVision.choose_targets([] as Array[Node3D], grouped), grouped)


func test_no_candidates_anywhere_is_an_empty_list_not_a_crash() -> void:
	assert_eq(CreatureVision.choose_targets([] as Array[Node3D], [] as Array[Node3D]).size(), 0)


# ----- evaluate_target -----


func test_a_clear_sighting_produces_precise_high_confidence_evidence() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _vision.evaluate_target(player, _ahead(4.0), EYE, true, 1.0, 3.0)

	assert_not_null(evidence)
	assert_eq(evidence.sense, SuspicionEvidence.Sense.VISION)
	assert_eq(evidence.observed_at, 3.0)
	assert_gt(evidence.strength, 0.5)
	assert_gt(evidence.confidence, 0.8)
	assert_lt(
		evidence.uncertainty_radius,
		1.0,
		"section 8's vision example is a quarter-metre, not a search area"
	)


## Vision DOES attribute, unlike hearing. Seeing a thing is what tells you which
## thing it was.
func test_vision_attributes_the_player_it_saw() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _vision.evaluate_target(player, _ahead(4.0), EYE, true, 1.0, 0.0)

	assert_same(evidence.source_player, player)
	assert_gt(evidence.source_confidence, 0.0)


func test_a_blocked_target_produces_nothing() -> void:
	var player: Node3D = autofree(Node3D.new())
	assert_null(_vision.evaluate_target(player, _ahead(4.0), EYE, false, 1.0, 0.0))


func test_a_target_behind_the_creature_produces_nothing() -> void:
	var player: Node3D = autofree(Node3D.new())
	assert_null(_vision.evaluate_target(player, Vector3(0, 0, 4.0), EYE, true, 1.0, 0.0))


func test_a_target_below_the_visibility_floor_produces_nothing() -> void:
	var player: Node3D = autofree(Node3D.new())
	_config.vision_min_visibility = 0.99
	assert_null(_vision.evaluate_target(player, _ahead(4.0), EYE, true, 1.0, 0.0))


## Section 13: "Vision can be disabled entirely. No other AI subsystem should
## require changes when vision is disabled."
func test_disabling_vision_produces_nothing_by_either_switch() -> void:
	var player: Node3D = autofree(Node3D.new())

	_config.vision_enabled = false
	assert_null(_vision.evaluate_target(player, _ahead(2.0), EYE, true, 1.0, 0.0))

	_config.vision_enabled = true
	_vision.enabled = false
	assert_null(_vision.evaluate_target(player, _ahead(2.0), EYE, true, 1.0, 0.0))


func test_a_dimmer_sighting_reports_a_wider_uncertainty() -> void:
	var player: Node3D = autofree(Node3D.new())
	var bright := _vision.evaluate_target(player, _ahead(3.0), EYE, true, 1.0, 0.0)
	var dim := _vision.evaluate_target(player, _ahead(3.0), EYE, true, 0.4, 0.0)

	assert_not_null(dim)
	assert_gt(dim.uncertainty_radius, bright.uncertainty_radius)
	assert_lt(dim.strength, bright.strength)


## The eye's own rotation is what defines forward -- not the world axes.
func test_the_cone_follows_the_eye_transform() -> void:
	var player: Node3D = autofree(Node3D.new())
	var behind := Vector3(0, 0, 4.0)
	assert_null(_vision.evaluate_target(player, behind, EYE, true, 1.0, 0.0))

	var turned := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	assert_not_null(
		_vision.evaluate_target(player, behind, turned, true, 1.0, 0.0),
		"turning round should bring the same point into view"
	)
