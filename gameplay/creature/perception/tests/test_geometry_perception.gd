extends GutTest

## CreatureGeometryPerception (perception.md sections 16-18).
##
## Kept separate from vision on purpose: the alien can be nearly blind to players
## and still perceive the cave. These tests use a FakePerceptionProbe rather than
## real physics; the runtime suite proves the real probe agrees with it.

const FakeProbe := preload("res://gameplay/creature/perception/tests/fake_perception_probe.gd")

var _config: PerceptionConfig = null
var _geometry: CreatureGeometryPerception = null
var _probe: RefCounted = null


func before_each() -> void:
	_config = PerceptionConfig.new()
	_geometry = CreatureGeometryPerception.new()
	_geometry.config = _config
	_probe = FakeProbe.new()


# ----- subdivide -----


func test_subdivision_tiles_the_region_exactly() -> void:
	var region := AABB(Vector3.ZERO, Vector3(4, 4, 4))
	var cells := CreatureGeometryPerception.subdivide(region, 2.0)

	assert_eq(cells.size(), 8, "4m cube at 2m resolution is 2x2x2")
	var total: float = 0.0
	for cell: AABB in cells:
		total += cell.get_volume()
		assert_true(region.encloses(cell), "no cell may spill outside the region")
	assert_almost_eq(total, region.get_volume(), 0.0001, "cells must tile with no gap or overlap")


## A fixed cell size with a ragged remainder at the far edge makes "did the scan
## cover the region" un-assertable. The count is rounded up and the size divided
## back down instead.
func test_a_region_that_does_not_divide_evenly_is_still_covered_exactly() -> void:
	var region := AABB(Vector3(1, 1, 1), Vector3(5, 3, 5))
	var cells := CreatureGeometryPerception.subdivide(region, 2.0)

	var total: float = 0.0
	var merged: AABB = cells[0]
	for cell: AABB in cells:
		total += cell.get_volume()
		merged = merged.merge(cell)
	assert_almost_eq(total, region.get_volume(), 0.0001)
	assert_almost_eq(merged.position.distance_to(region.position), 0.0, 0.0001)
	assert_almost_eq(merged.size.distance_to(region.size), 0.0, 0.0001)


func test_a_degenerate_region_subdivides_into_nothing() -> void:
	assert_eq(CreatureGeometryPerception.subdivide(AABB(), 1.0).size(), 0)
	assert_eq(
		CreatureGeometryPerception.subdivide(AABB(Vector3.ZERO, Vector3(4, 4, 4)), 0.0).size(),
		0,
		"a zero cell size would not terminate"
	)


func test_a_region_smaller_than_one_cell_is_still_one_cell() -> void:
	var cells := CreatureGeometryPerception.subdivide(AABB(Vector3.ZERO, Vector3.ONE), 10.0)
	assert_eq(cells.size(), 1)


func test_cell_count_agrees_with_subdivide() -> void:
	for size: float in [0.7, 1.0, 2.5]:
		var region := AABB(Vector3(-1, 0, 2), Vector3(5, 3, 7))
		assert_eq(
			CreatureGeometryPerception.cell_count(region, size),
			CreatureGeometryPerception.subdivide(region, size).size(),
			"cell size %s" % size
		)


## A passive scan at the default 6m radius and 1m resolution is a 12m cube -- 1728
## cells, each a shape query plus up to four raycasts, every half second. This is
## what stops that.
func test_a_large_region_is_coarsened_to_fit_the_sample_budget() -> void:
	var passive := AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	assert_eq(CreatureGeometryPerception.cell_count(passive, 1.0), 1728, "the cost being avoided")

	var coarsened := CreatureGeometryPerception.resolution_for(passive, 1.0, 256)

	assert_gt(coarsened, 1.0, "it had to get coarser")
	assert_lte(CreatureGeometryPerception.cell_count(passive, coarsened), 256)


## COARSEN, NOT TRUNCATE. Dropping cells past the budget leaves part of the region
## unobserved while still reporting a completed scan, so Spatial Memory keeps a
## stale belief about somewhere the creature is standing.
func test_coarsening_still_covers_the_whole_region() -> void:
	var passive := AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	_config.max_scan_samples = 64
	var observations := _geometry.scan_region(_probe, passive, Vector3.ZERO, 6.0, 0.0)

	assert_lte(observations.size(), 64, "the budget is respected")
	assert_gt(observations.size(), 0)
	var merged: AABB = observations[0].region
	var total: float = 0.0
	for observation: GeometryObservation in observations:
		merged = merged.merge(observation.region)
		total += observation.region.get_volume()
	assert_almost_eq(total, passive.get_volume(), 1.0, "every cubic metre is still observed")
	assert_almost_eq(merged.size.distance_to(passive.size), 0.0, 0.001)


func test_a_region_already_within_budget_keeps_its_preferred_resolution() -> void:
	var small := AABB(Vector3.ZERO, Vector3(4, 4, 4))
	assert_eq(CreatureGeometryPerception.resolution_for(small, 1.0, 256), 1.0)


# ----- classification -----


func test_classification_maps_the_three_cases() -> void:
	assert_eq(
		CreatureGeometryPerception.classify(true, 0.0, _config),
		GeometryObservation.ObservationType.SOLID
	)
	assert_eq(
		CreatureGeometryPerception.classify(false, _config.geometry_min_clearance - 0.1, _config),
		GeometryObservation.ObservationType.CLEARANCE,
		"open, but too narrow to be usefully free"
	)
	assert_eq(
		CreatureGeometryPerception.classify(false, _config.geometry_min_clearance + 5.0, _config),
		GeometryObservation.ObservationType.FREE
	)


func test_solid_beats_clearance() -> void:
	assert_eq(
		CreatureGeometryPerception.classify(true, 0.01, _config),
		GeometryObservation.ObservationType.SOLID
	)


# ----- confidence -----


func test_confidence_falls_with_sensing_distance_but_never_to_zero() -> void:
	var near := CreatureGeometryPerception.confidence_at(0.0, 6.0)
	var mid := CreatureGeometryPerception.confidence_at(3.0, 6.0)
	var edge := CreatureGeometryPerception.confidence_at(6.0, 6.0)

	assert_almost_eq(near, 1.0, 0.0001)
	assert_lt(mid, near)
	assert_lt(edge, mid)
	assert_gte(
		edge,
		CreatureGeometryPerception.MIN_CONFIDENCE,
		"an observation worth zero should not have been made"
	)


# ----- observing cells -----


func test_a_cell_full_of_wall_reports_solid() -> void:
	_probe.add_wall(AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)))
	var observation := _geometry.observe_cell(
		_probe, AABB(Vector3.ZERO, Vector3.ONE), Vector3.ZERO, 6.0, 1.0
	)

	assert_eq(observation.type, GeometryObservation.ObservationType.SOLID)
	assert_eq(observation.observed_at, 1.0)


func test_an_open_cell_in_open_space_reports_free() -> void:
	var observation := _geometry.observe_cell(
		_probe, AABB(Vector3.ZERO, Vector3.ONE), Vector3.ZERO, 6.0, 0.0
	)
	assert_eq(observation.type, GeometryObservation.ObservationType.FREE)
	assert_gt(observation.clearance, _config.geometry_min_clearance)


## A corridor narrower than the creature needs is open space it still cannot use.
func test_a_narrow_gap_reports_clearance_and_measures_it() -> void:
	_probe.force_clearance = 0.4
	var observation := _geometry.observe_cell(
		_probe, AABB(Vector3.ZERO, Vector3.ONE), Vector3.ZERO, 6.0, 0.0
	)

	assert_eq(observation.type, GeometryObservation.ObservationType.CLEARANCE)
	assert_almost_eq(observation.clearance, 0.8, 0.0001, "two opposing rays of 0.4 make a 0.8 gap")


func test_disabling_geometry_perception_produces_no_observations() -> void:
	_config.geometry_perception_enabled = false
	var region := AABB(Vector3.ZERO, Vector3(4, 4, 4))
	assert_eq(_geometry.scan_region(_probe, region, Vector3.ZERO, 6.0, 0.0).size(), 0)


func test_scanning_a_region_observes_every_cell_in_it() -> void:
	var region := AABB(Vector3.ZERO, Vector3(4, 4, 4))
	var observations := _geometry.scan_region(_probe, region, Vector3.ZERO, 6.0, 2.0)

	assert_eq(observations.size(), CreatureGeometryPerception.subdivide(region, 1.0).size())
	for observation: GeometryObservation in observations:
		assert_eq(observation.observed_at, 2.0)
		assert_true(region.encloses(observation.region))


## The half-wall case: a scan across a boundary must report both sides, or Spatial
## Memory learns a cave with no walls in it.
func test_a_scan_across_a_wall_reports_both_solid_and_free_cells() -> void:
	_probe.add_wall(AABB(Vector3(2, -5, -5), Vector3(10, 10, 10)))
	var region := AABB(Vector3.ZERO, Vector3(4, 2, 2))
	var observations := _geometry.scan_region(_probe, region, Vector3.ZERO, 6.0, 0.0)

	var solid: int = 0
	var open: int = 0
	for observation: GeometryObservation in observations:
		if observation.type == GeometryObservation.ObservationType.SOLID:
			solid += 1
		else:
			open += 1
	assert_gt(solid, 0, "the wall half must come back solid")
	assert_gt(open, 0, "the open half must not")


func test_passive_region_is_centred_on_the_creature() -> void:
	var region := _geometry.passive_region(Vector3(10, 0, -4))
	assert_eq(region.get_center(), Vector3(10, 0, -4))
	assert_almost_eq(region.size.x, _config.geometry_passive_scan_radius * 2.0, 0.0001)
