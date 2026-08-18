extends GutTest

## CreatureTouch (perception.md section 15). The sense that cannot be fooled, and
## therefore the one the fiction keeps short-ranged.

var _config: PerceptionConfig = null
var _touch: CreatureTouch = null


func before_each() -> void:
	_config = PerceptionConfig.new()
	_touch = CreatureTouch.new()
	_touch.config = _config


## Section 15's worked example, asserted: high strength, high confidence, very low
## uncertainty.
func test_contact_is_strong_certain_and_nearly_exact() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _touch.perceive_contact(player, Vector3(1, 0, 2), 4.0)

	assert_not_null(evidence)
	assert_eq(evidence.sense, SuspicionEvidence.Sense.TOUCH)
	assert_eq(evidence.position, Vector3(1, 0, 2))
	assert_eq(evidence.strength, 1.0)
	assert_eq(evidence.confidence, 1.0)
	assert_almost_eq(evidence.uncertainty_radius, 0.1, 0.0001)
	assert_eq(evidence.observed_at, 4.0)
	assert_eq(evidence.category, &"contact")


## Not zero. Touching something is not the same as knowing its exact centre, and a
## zero radius is the claim of perfect knowledge section 31 forbids every sense from
## making.
func test_contact_uncertainty_is_small_but_never_zero() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _touch.perceive_contact(player, Vector3.ZERO, 0.0)
	assert_gt(evidence.uncertainty_radius, 0.0)


func test_touch_attributes_the_body_it_touched() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _touch.perceive_contact(player, Vector3.ZERO, 0.0)
	assert_same(evidence.source_player, player)
	assert_eq(evidence.source_confidence, 1.0)


func test_disabling_touch_produces_nothing_by_either_switch() -> void:
	var player: Node3D = autofree(Node3D.new())

	_config.touch_enabled = false
	assert_null(_touch.perceive_contact(player, Vector3.ZERO, 0.0))

	_config.touch_enabled = true
	_touch.enabled = false
	assert_null(_touch.perceive_contact(player, Vector3.ZERO, 0.0))


# ----- proximity -----


func test_proximity_degrades_with_distance_unlike_contact() -> void:
	var player: Node3D = autofree(Node3D.new())
	var near := _touch.perceive_proximity(player, Vector3(0, 0, 0.2), 0.2, 0.0)
	var far := _touch.perceive_proximity(player, Vector3(0, 0, 1.4), 1.4, 0.0)

	assert_not_null(near)
	assert_not_null(far)
	assert_gt(near.strength, far.strength)
	assert_gt(near.confidence, far.confidence)
	assert_lt(near.uncertainty_radius, far.uncertainty_radius)


func test_proximity_beyond_its_range_produces_nothing() -> void:
	var player: Node3D = autofree(Node3D.new())
	var beyond := _config.proximity_detection_range + 0.5
	assert_null(_touch.perceive_proximity(player, Vector3(0, 0, beyond), beyond, 0.0))


func test_proximity_is_weaker_evidence_than_contact() -> void:
	var player: Node3D = autofree(Node3D.new())
	var contact := _touch.perceive_contact(player, Vector3.ZERO, 0.0)
	var nearby := _touch.perceive_proximity(player, Vector3(0, 0, 1.0), 1.0, 0.0)
	assert_lt(nearby.strength, contact.strength)
	assert_lt(nearby.source_confidence, contact.source_confidence)


func test_proximity_is_still_reported_as_the_touch_sense() -> void:
	var player: Node3D = autofree(Node3D.new())
	var evidence := _touch.perceive_proximity(player, Vector3(0, 0, 0.5), 0.5, 9.0)
	assert_eq(evidence.sense, SuspicionEvidence.Sense.TOUCH)
	assert_eq(evidence.category, &"proximity")
	assert_eq(evidence.observed_at, 9.0)
