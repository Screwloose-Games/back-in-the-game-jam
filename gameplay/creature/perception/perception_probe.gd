class_name PerceptionProbe
extends RefCounted

## THE ONLY FILE IN THIS MODULE ALLOWED TO NAME A PHYSICS QUERY.
##
## Every sense reaches the world through these six methods and nothing else.
## `verify_perception_static.gd` greps the whole module for `intersect_ray`,
## `intersect_shape`, `direct_space_state` and friends, and fails if any file other
## than this one names them. That grep is what keeps the seam from eroding.
##
## The seam exists so the GUT suite can run with no scene, no world and no physics
## server: tests substitute a subclass with scripted answers. The subclass EXTENDS
## this class rather than duck-typing it, so changing a signature here breaks every
## fake at parse time instead of at assertion time.
##
## Deliberately NOT the alternative design -- a nullable PhysicsDirectSpaceState3D
## passed into each sense. That makes every pure test exercise the `if space == null`
## branch, so the path the tests prove is not the path that ships, and the null
## fallback silently makes the creature either deaf or omniscient in a headless run.

## How many stacked blockers count as total obstruction. Past this, more walls
## change nothing -- sound through three walls and through six is the same "no".
const BLOCKER_SATURATION: int = 3
## Hard cap on rays per obstruction query. Without it a ray that re-hits the same
## body (a concave trimesh will) loops until the frame budget is gone.
const MAX_RAY_STEPS: int = 8
## Nudge along the ray after each hit, so the next cast starts past the surface
## rather than exactly on it and re-reporting the face it just left.
const RAY_ADVANCE: float = 0.01

var _world: World3D = null
var _box_shape: BoxShape3D = null


## Fetched fresh per query rather than cached. A PhysicsDirectSpaceState3D held
## across frames is a documented way to get "Can't change this state while flushing
## queries"; holding the World3D and asking it each time costs nothing.
func bind(world: World3D) -> void:
	_world = world


func is_bound() -> bool:
	return _world != null


## How much matter stands between two points, 0.0 (clear) to 1.0 (saturated).
##
## A FLOAT, NOT A BLOCKER COUNT, deliberately. Sound is attenuated rather than
## blocked, and handing the sense a count would weld it to "we implemented this by
## counting raycast hits" -- swapping in a thickness integral or a portal graph
## later would then mean rewriting hearing's tests as well as hearing.
func obstruction_between(from: Vector3, to: Vector3, mask: int) -> float:
	if _world == null or mask == 0:
		return 0.0
	var space: PhysicsDirectSpaceState3D = _world.direct_space_state
	if space == null:
		return 0.0

	var span: Vector3 = to - from
	var length: float = span.length()
	if length <= 0.0:
		return 0.0
	var direction: Vector3 = span / length

	var blockers: int = 0
	var travelled: float = 0.0
	var excluded: Array[RID] = []
	for _step: int in MAX_RAY_STEPS:
		var origin: Vector3 = from + direction * travelled
		var query := PhysicsRayQueryParameters3D.create(origin, to, mask, excluded)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		blockers += 1
		if blockers >= BLOCKER_SATURATION:
			break
		excluded.append(hit["rid"] as RID)
		travelled = (hit["position"] as Vector3 - from).length() + RAY_ADVANCE
		if travelled >= length:
			break

	return clampf(float(blockers) / float(BLOCKER_SATURATION), 0.0, 1.0)


## Whether nothing at all stands between two points.
##
## A BOOL, unlike hearing's float. Sight through a wall is not dimmer sight; it is
## no sight. Modelling it as a fraction would be pretending.
func has_clear_line(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> bool:
	if _world == null:
		return true
	var space: PhysicsDirectSpaceState3D = _world.direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return space.intersect_ray(query).is_empty()


## Whether any collider overlaps this volume.
##
## The box shape is reused across calls; a fresh BoxShape3D per geometry cell would
## allocate hundreds of resources per scan.
func is_volume_solid(box: AABB, mask: int) -> bool:
	if _world == null or box.get_volume() <= 0.0:
		return false
	var space: PhysicsDirectSpaceState3D = _world.direct_space_state
	if space == null:
		return false
	if _box_shape == null:
		_box_shape = BoxShape3D.new()
	_box_shape.size = box.size

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _box_shape
	query.transform = Transform3D(Basis.IDENTITY, box.get_center())
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_shape(query, 1).is_empty()


## Free distance from `origin` along `direction`, capped at `max_length`.
## Returns `max_length` when nothing is hit -- open space measured as open, not as
## an error case the caller has to special-case.
func clearance_at(origin: Vector3, direction: Vector3, mask: int, max_length: float) -> float:
	if _world == null or max_length <= 0.0:
		return max_length
	var space: PhysicsDirectSpaceState3D = _world.direct_space_state
	if space == null:
		return max_length
	var target: Vector3 = origin + direction.normalized() * max_length
	var query := PhysicsRayQueryParameters3D.create(origin, target, mask)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return max_length
	return minf((hit["position"] as Vector3 - origin).length(), max_length)
