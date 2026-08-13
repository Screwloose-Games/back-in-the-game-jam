class_name CreatureGeometryPerception
extends RefCounted

## Perceives physical space, separately from perceiving players (perception.md
## sections 16-18).
##
## SEPARATE FROM VISION ON PURPOSE. The alien can be nearly blind to players and
## still move confidently through a cave -- echolocation, vibration sensing,
## tendrils, physical probing. Implementing it with physics queries does not imply
## conventional sight, and keeping it out of vision.gd is what lets vision be turned
## off (section 13) without the creature losing the ability to walk.
##
## Output goes to Spatial Memory, never to Suspicion. A wall is not evidence of a
## player.

## Reasons Navigation or Behavior might ask for a look (section 18).
##
## Lives HERE rather than on CreaturePerception, even though request_geometry_scan()
## is the facade's method. Putting it on the facade would force this file to name
## CreaturePerception, which is a class_name cycle against section 25's explicitly
## one-way dependency graph -- senses never reference the facade.
enum GeometryScanReason {
	PASSIVE, PATH_BLOCKED, EXPECTED_WALL_MISSING, CLEARANCE_MISMATCH, SEARCH_BEHAVIOR
}

## Directions clearance is measured along. Horizontal pairs only: a cave's ceiling
## height is rarely what stops a creature, and six directions is 50% more raycasts
## per cell for a number nothing reads.
const CLEARANCE_AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
## Floor on how much a far-edge observation is trusted. Never zero -- an observation
## worth zero should not have been made, and Spatial Memory would have to special-case it.
const MIN_CONFIDENCE: float = 0.15

var enabled: bool = true
var config: PerceptionConfig = null


## Tile `region` with cells of at most `cell_size` on each edge.
##
## The cell count per axis is ceil(size / cell_size) and the ACTUAL cell size is
## then size / count, so cells tile the region exactly: no gaps, no overlap, and the
## union is the region itself. A fixed cell size with a ragged remainder at the far
## edge would make "did the scan cover the region" un-assertable.
static func subdivide(region: AABB, cell_size: float) -> Array[AABB]:
	var cells: Array[AABB] = []
	if cell_size <= 0.0 or region.size.x <= 0.0 or region.size.y <= 0.0 or region.size.z <= 0.0:
		return cells
	var counts := Vector3i(
		maxi(1, int(ceilf(region.size.x / cell_size))),
		maxi(1, int(ceilf(region.size.y / cell_size))),
		maxi(1, int(ceilf(region.size.z / cell_size)))
	)
	var step := Vector3(
		region.size.x / float(counts.x),
		region.size.y / float(counts.y),
		region.size.z / float(counts.z)
	)
	for ix: int in counts.x:
		for iy: int in counts.y:
			for iz: int in counts.z:
				var corner: Vector3 = (
					region.position
					+ Vector3(step.x * float(ix), step.y * float(iy), step.z * float(iz))
				)
				cells.append(AABB(corner, step))
	return cells


## How many cells `subdivide` would produce, without building them.
static func cell_count(region: AABB, cell_size: float) -> int:
	if cell_size <= 0.0 or region.size.x <= 0.0 or region.size.y <= 0.0 or region.size.z <= 0.0:
		return 0
	return (
		maxi(1, int(ceilf(region.size.x / cell_size)))
		* maxi(1, int(ceilf(region.size.y / cell_size)))
		* maxi(1, int(ceilf(region.size.z / cell_size)))
	)


## The finest cell size that covers `region` in at most `max_cells` cells, never
## finer than `preferred`.
##
## COARSEN, DO NOT TRUNCATE. The obvious way to bound cost is to subdivide at the
## preferred resolution and drop the cells past the budget -- and that silently stops
## observing part of the region while still reporting a completed scan, so Spatial
## Memory keeps a stale belief about somewhere the creature is standing.
##
## This was not hypothetical. A passive scan at the default 6 m radius and 1 m
## resolution is a 12 m cube: 1728 cells, each one a shape query plus up to four
## raycasts, every 0.5 seconds. Coarsening keeps the whole volume covered and drops
## it to about 216.
static func resolution_for(region: AABB, preferred: float, max_cells: int) -> float:
	var size: float = maxf(preferred, 0.01)
	var budget: int = maxi(max_cells, 1)
	# Bounded rather than `while true`: a degenerate region returns a count of 0 and
	# would otherwise never exceed the budget, but a NaN extent would spin forever.
	for _step: int in 32:
		if cell_count(region, size) <= budget:
			break
		size *= 1.5
	return size


static func classify(
	solid: bool, clearance: float, config: PerceptionConfig
) -> GeometryObservation.ObservationType:
	if solid:
		return GeometryObservation.ObservationType.SOLID
	if config != null and clearance < config.geometry_min_clearance:
		return GeometryObservation.ObservationType.CLEARANCE
	return GeometryObservation.ObservationType.FREE


## How much to trust an observation made `distance` metres from the creature.
## Falls off linearly, floored at MIN_CONFIDENCE.
static func confidence_at(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return MIN_CONFIDENCE
	return clampf(1.0 - clampf(distance / radius, 0.0, 1.0) * 0.85, MIN_CONFIDENCE, 1.0)


## The volume the creature passively perceives from where it stands (section 17).
func passive_region(origin: Vector3) -> AABB:
	var radius: float = config.geometry_passive_scan_radius if config != null else 1.0
	return AABB(origin - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)


## Observe one cell. The only method here that touches the probe.
func observe_cell(
	probe: PerceptionProbe, cell: AABB, observer: Vector3, radius: float, now: float
) -> GeometryObservation:
	if not enabled or config == null or probe == null:
		return null
	var centre: Vector3 = cell.get_center()
	var confidence: float = confidence_at(observer.distance_to(centre), radius)
	if probe.is_volume_solid(cell, config.world_mask):
		return GeometryObservation.make(
			GeometryObservation.ObservationType.SOLID, cell, confidence, now
		)

	var clearance: float = _measure_clearance(probe, centre)
	return GeometryObservation.make(
		classify(false, clearance, config), cell, confidence, now, clearance
	)


## Subdivide and observe every cell. Returns a batch, because Spatial Memory takes
## batches (section 21) and a scan naturally produces many.
func scan_region(
	probe: PerceptionProbe, region: AABB, observer: Vector3, radius: float, now: float
) -> Array[GeometryObservation]:
	var observations: Array[GeometryObservation] = []
	if not enabled or config == null or not config.geometry_perception_enabled:
		return observations
	var cell_size: float = resolution_for(
		region, config.geometry_clearance_resolution, config.max_scan_samples
	)
	for cell: AABB in subdivide(region, cell_size):
		var observation: GeometryObservation = observe_cell(probe, cell, observer, radius, now)
		if observation != null:
			observations.append(observation)
	return observations


## Narrowest free width through `point`, measured as the smallest opposing-axis pair
## sum. A corridor two metres wide reports 2.0 whichever way it runs.
func _measure_clearance(probe: PerceptionProbe, point: Vector3) -> float:
	var reach: float = config.geometry_passive_scan_radius
	var widths: Array[float] = []
	for axis: Vector3 in CLEARANCE_AXES:
		widths.append(probe.clearance_at(point, axis, config.world_mask, reach))
	# CLEARANCE_AXES is ordered as opposing pairs: (RIGHT, LEFT), (FORWARD, BACK).
	return minf(widths[0] + widths[1], widths[2] + widths[3])
