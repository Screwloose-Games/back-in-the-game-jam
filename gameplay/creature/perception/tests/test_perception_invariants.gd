extends "res://gameplay/creature/perception/tests/perception_test_case.gd"

## The architectural rules of perception.md sections 14, 22, 28 and 31.
##
## These are the tests that stop the module quietly becoming something else. Every
## one of them would still pass if it were merely written in a comment -- which is
## exactly why it is written here instead.

## Section 28's forbidden state, as substrings. Perception represents present
## senses, not memory: anything matching these belongs to Suspicion, Spatial Memory,
## Navigation or Behavior.
const FORBIDDEN_STATE: Array[String] = [
	"last_known",
	"suspicion_value",
	"hotspot",
	"remembered",
	"nav_target",
	"navigation_target",
	"hunt",
	"current_target",
	"believed",
	"memory",
]

# ----- section 18/22: Navigation requests a look, not a conclusion -----


func test_a_geometry_scan_publishes_observations_and_completes() -> void:
	_config.geometry_perception_enabled = true
	_perception.request_geometry_scan(
		AABB(Vector3.ZERO, Vector3(3, 3, 3)),
		CreatureGeometryPerception.GeometryScanReason.PATH_BLOCKED
	)
	assert_true(_perception.is_geometry_scan_active())

	_advance(_config.geometry_scan_duration + 0.2)

	assert_true(_perception.is_geometry_scan_complete())
	assert_gt(_geometry.size(), 0)
	assert_eq(_disconfirmations.size(), 0, "geometry validation is not a search for a player")


func test_a_geometry_scan_with_geometry_perception_disabled_still_completes() -> void:
	_config.geometry_perception_enabled = false
	_perception.request_geometry_scan(
		AABB(Vector3.ZERO, Vector3(3, 3, 3)),
		CreatureGeometryPerception.GeometryScanReason.EXPECTED_WALL_MISSING
	)

	assert_true(_perception.is_geometry_scan_complete(), "Navigation must not wait forever")
	assert_eq(_geometry.size(), 0)


## Navigation says "my expectation seems incorrect, inspect this region". It does
## not say "the geometry is now SOLID" -- so the reason it gives must not change one
## thing about what comes back.
func test_the_scan_reason_does_not_change_what_is_observed() -> void:
	var region := AABB(Vector3.ZERO, Vector3(3, 3, 3))
	var results: Array[int] = []

	for reason: int in [
		CreatureGeometryPerception.GeometryScanReason.PASSIVE,
		CreatureGeometryPerception.GeometryScanReason.PATH_BLOCKED,
		CreatureGeometryPerception.GeometryScanReason.CLEARANCE_MISMATCH,
		CreatureGeometryPerception.GeometryScanReason.SEARCH_BEHAVIOR,
	]:
		before_each()
		_config.geometry_perception_enabled = true
		_probe.add_wall(AABB(Vector3(1, -5, -5), Vector3(10, 10, 10)))
		_perception.request_geometry_scan(region, reason)
		_advance(_config.geometry_scan_duration + 0.2)
		results.append(_solid_count())

	for index: int in results.size():
		assert_eq(results[index], results[0], "reason %d changed the observation" % index)
	assert_gt(results[0], 0, "and the wall really was found, so this is not vacuous")


func _solid_count() -> int:
	var solid: int = 0
	for batch: Array in _geometry:
		for observation: Variant in batch:
			if (
				(observation as GeometryObservation).type
				== GeometryObservation.ObservationType.SOLID
			):
				solid += 1
	return solid


# ----- section 14: alertness is read-only context -----


func test_alertness_gates_whether_vision_runs_at_all() -> void:
	_add_target(Vector3(0, 0, -3))
	_config.vision_activation_suspicion = 0.5

	_perception.set_alertness_context(0.0)
	_advance(1.0)
	assert_eq(_evidence.size(), 0, "section 14: low suspicion, vision disabled")

	_perception.set_alertness_context(1.0)
	_advance(1.0)
	assert_gt(_evidence.size(), 0, "high suspicion, vision enabled")


func test_alertness_increases_scan_frequency() -> void:
	_add_target(Vector3(0, 0, -3))
	_config.vision_activation_suspicion = 0.0

	_perception.set_alertness_context(0.0)
	_advance(3.0)
	var calm: int = _evidence.size()

	before_each()
	_add_target(Vector3(0, 0, -3))
	_config.vision_activation_suspicion = 0.0
	_perception.set_alertness_context(1.0)
	_advance(3.0)

	assert_gt(_evidence.size(), calm, "an alert creature looks more often")


## THE LINE SECTION 14 DRAWS. Suspicion may affect HOW the alien looks, never WHAT
## the world contains. Identical input at opposite alertness must produce an
## identical observation.
func test_alertness_does_not_change_what_a_sighting_reports() -> void:
	_config.vision_activation_suspicion = 0.0
	_add_target(Vector3(0, 0, -3))
	_perception.set_alertness_context(0.0)
	_advance(1.0)
	var calm: SuspicionEvidence = _evidence[0]

	before_each()
	_config.vision_activation_suspicion = 0.0
	_add_target(Vector3(0, 0, -3))
	_perception.set_alertness_context(1.0)
	_advance(1.0)
	var alert: SuspicionEvidence = _evidence[0]

	assert_eq(alert.strength, calm.strength)
	assert_eq(alert.confidence, calm.confidence)
	assert_eq(alert.uncertainty_radius, calm.uncertainty_radius)
	assert_eq(alert.position, calm.position)


func test_alertness_is_clamped() -> void:
	_perception.set_alertness_context(5.0)
	assert_eq(_perception.get_alertness(), 1.0)
	_perception.set_alertness_context(-5.0)
	assert_eq(_perception.get_alertness(), 0.0)


# ----- section 28: perception is senses, not memory -----


## Enumerated rather than eyeballed. A field called `last_known_position` would make
## the alien omniscient in a way no behavioural test catches -- the creature would
## simply start working better.
func test_perception_declares_no_remembered_state() -> void:
	var offenders: Array[String] = []
	for property: Dictionary in _perception.get_property_list():
		var name: String = String(property["name"]).to_lower()
		for banned: String in FORBIDDEN_STATE:
			if name.contains(banned):
				offenders.append(name)
	assert_eq(offenders, [] as Array[String], "section 28: perception is senses, not memory")


func test_perception_does_not_accumulate_anything_per_observation() -> void:
	var target := _add_target(Vector3(0, 0, -3))
	_config.vision_activation_suspicion = 0.0
	_perception.set_alertness_context(1.0)

	for i: int in 100:
		_perception.receive_noise(NoiseEvent.make(Vector3(float(i) * 0.1, 0, 2), 1.0))
		_perception.receive_contact(target, Vector3(float(i), 0, 0))
	_advance(2.0)
	_perception.request_activity_scan(_empty_region(), 1.0)
	_advance(_config.search_scan_duration_max + 0.5)

	assert_gt(_evidence.size(), 100, "all of that really was observed")
	var state := _perception.debug_state()
	assert_false(state.has("recent_evidence"), "the overlay keeps its own buffer, not perception")
	assert_false(state.has("last_evidence"))
	assert_eq(
		_perception.candidate_targets().size(), 1, "candidates are wiring, not accumulated memory"
	)


func test_debug_state_is_computed_not_cached() -> void:
	var first: Dictionary = _perception.debug_state()
	_advance(1.0)
	var second: Dictionary = _perception.debug_state()

	assert_ne(first["clock"], second["clock"])
	assert_true(second.has("probe_bound"))


# ----- section 20/31: observations, never commands -----


func test_perception_exposes_no_behavioural_commands() -> void:
	for method: String in [
		"increase_suspicion",
		"start_hunting",
		"set_hotspot",
		"clear_hotspot",
		"set_target",
		"set_destination",
	]:
		assert_false(
			_perception.has_method(method),
			"%s would couple sensing to interpretation (section 20)" % method
		)


## Section 25: senses reach the outside world only through the facade, which is what
## makes each of them independently replaceable.
func test_the_senses_hold_no_reference_to_suspicion_or_spatial_memory() -> void:
	for sense: RefCounted in [
		_perception.hearing, _perception.vision, _perception.touch, _perception.geometry_perception
	]:
		for property: Dictionary in sense.get_property_list():
			var name: String = String(property["name"]).to_lower()
			assert_false(name.contains("suspicion"), name)
			assert_false(name.contains("spatial"), name)
			assert_false(name.contains("facade"), name)
