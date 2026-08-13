extends PerceptionProbe

## A PerceptionProbe with scripted answers, so the whole module can be tested with
## no scene, no world and no physics server.
##
## EXTENDS THE REAL CLASS RATHER THAN DUCK-TYPING IT, and that is the point: change a
## signature on PerceptionProbe and this file stops parsing immediately, instead of
## the suite happily testing a method the real probe no longer has. It also avoids
## GUT's `double()` entirely, which matters on Godot 4.7 where stricter typed-return
## checking changed how doubles fabricate return values.
##
## No `class_name` -- test helpers must not occupy a global name.

## Segments that block sight and muffle sound. Each is [from, to] of an axis-aligned
## wall plane; see `add_wall`.
var walls: Array[AABB] = []
## Forced answers, used when a test cares about the sense rather than the geometry.
var force_clear_line: Variant = null
var force_obstruction: Variant = null
var force_solid: Variant = null
var force_clearance: Variant = null
var bound: bool = true

## Call counts, so a test can prove a sense did or did not reach for the world.
var clear_line_calls: int = 0
var obstruction_calls: int = 0
var solid_calls: int = 0
var clearance_calls: int = 0


func bind(_world: World3D) -> void:
	bound = true


func is_bound() -> bool:
	return bound


func add_wall(box: AABB) -> void:
	walls.append(box)


func obstruction_between(from: Vector3, to: Vector3, _mask: int) -> float:
	obstruction_calls += 1
	if force_obstruction != null:
		return float(force_obstruction)
	return clampf(float(_crossings(from, to)) / float(BLOCKER_SATURATION), 0.0, 1.0)


func has_clear_line(from: Vector3, to: Vector3, _mask: int, _exclude: Array[RID] = []) -> bool:
	clear_line_calls += 1
	if force_clear_line != null:
		return bool(force_clear_line)
	return _crossings(from, to) == 0


func is_volume_solid(box: AABB, _mask: int) -> bool:
	solid_calls += 1
	if force_solid != null:
		return bool(force_solid)
	for wall: AABB in walls:
		if wall.intersects(box):
			return true
	return false


func clearance_at(origin: Vector3, direction: Vector3, _mask: int, max_length: float) -> float:
	clearance_calls += 1
	if force_clearance != null:
		return minf(float(force_clearance), max_length)
	var step: Vector3 = direction.normalized()
	var nearest: float = max_length
	for wall: AABB in walls:
		var hit: Variant = wall.intersects_ray(origin, step)
		if hit != null:
			nearest = minf(nearest, origin.distance_to(hit as Vector3))
	return nearest


## How many registered walls a segment passes through. Sampled rather than solved:
## the fake only has to be consistent, not fast, and a marching test is far easier
## to reason about than an analytic slab intersection when a test fails.
func _crossings(from: Vector3, to: Vector3) -> int:
	var hits: int = 0
	for wall: AABB in walls:
		if _segment_hits(wall, from, to):
			hits += 1
	return hits


func _segment_hits(box: AABB, from: Vector3, to: Vector3) -> bool:
	var steps: int = 64
	for i: int in steps + 1:
		if box.has_point(from.lerp(to, float(i) / float(steps))):
			return true
	return false
