extends NavigationProbe

## A NavigationProbe that answers from analytic boxes, so the whole module can be
## tested with no scene, no world, no physics server and no voxel extension.
##
## EXTENDS THE REAL CLASS RATHER THAN DUCK-TYPING IT, and that is the point: change a
## signature on NavigationProbe and this file stops parsing immediately, instead of the
## suite happily testing a method the real probe no longer has. It also avoids GUT's
## `double()`, which on Godot 4.7 fabricates return values under stricter typed-return
## checking.
##
## ANALYTIC RATHER THAN SCRIPTED, unlike perception's fake. The thing under test here
## is mostly geometry -- does a candidate survive, does a swept body fit, is the nearest
## node through a wall -- and a probe that returns canned booleans tests the arithmetic
## around the geometry rather than the geometry. Boxes and exact distances give the
## builder something real to be right or wrong about, and keep every assertion below
## hand-checkable.
##
## The one scripted escape hatch is `unreachable_nodes`, for section 16's pathological
## case: a node the alien cannot get to however close it is. Building real geometry that
## puts a wall between two specific points is possible but makes the test about the
## wall; naming the node makes it about attachment.
##
## No `class_name` -- test helpers must not occupy a global name.

## Solid boxes. Everything else is open space.
var solids: Array[AABB] = []
## Positions no sweep may ever reach, whatever the geometry says.
##
## Deliberately UNTYPED. A typed Array[Vector3] refuses assignment from a plain array
## literal, which is how every test writes this, and the failure is a runtime error
## inside the test rather than a compile error anyone would notice.
var unreachable_nodes: Array = []
## Sample count along a swept segment. High enough that a 1 m gap in a 40 m sweep is
## never stepped over.
var sweep_samples: int = 64

var fits_calls: int = 0
var clearance_calls: int = 0
var sweep_calls: int = 0
var surface_calls: int = 0
var solid_calls: int = 0


func bind(_world: World3D) -> void:
	pass


func is_bound() -> bool:
	return true


func add_solid(box: AABB) -> void:
	solids.append(box)


## A hollow room: six slabs around `interior`, so open space is bounded.
##
## Without this the void outside a test's geometry has unlimited clearance and every
## candidate in it survives -- which is the same mistake the sandbox's shell exists to
## prevent, at test scale.
func add_room(interior: AABB, thickness: float = 2.0) -> void:
	var wall := Vector3(thickness, thickness, thickness)
	var outer := AABB(interior.position - wall, interior.size + wall * 2.0)
	add_solid(AABB(outer.position, Vector3(outer.size.x, thickness, outer.size.z)))
	add_solid(
		AABB(
			Vector3(outer.position.x, interior.end.y, outer.position.z),
			Vector3(outer.size.x, thickness, outer.size.z)
		)
	)
	add_solid(AABB(outer.position, Vector3(thickness, outer.size.y, outer.size.z)))
	add_solid(
		AABB(
			Vector3(interior.end.x, outer.position.y, outer.position.z),
			Vector3(thickness, outer.size.y, outer.size.z)
		)
	)
	add_solid(AABB(outer.position, Vector3(outer.size.x, outer.size.y, thickness)))
	add_solid(
		AABB(
			Vector3(outer.position.x, outer.position.y, interior.end.z),
			Vector3(outer.size.x, outer.size.y, thickness)
		)
	)


func clearance_at(point: Vector3, _mask: int, max_radius: float, _steps: int) -> float:
	clearance_calls += 1
	queries_spent += 1
	return minf(free_distance(point), max_radius)


func shape_fits(shape: Shape3D, at: Transform3D, _mask: int) -> bool:
	fits_calls += 1
	queries_spent += 1
	return free_distance(at.origin) > radius_of(shape)


## `shape_sweep_clear` is deliberately NOT overridden. The real probe defines it as a
## comparison against this number, so overriding both would let the fake answer "clear"
## and "how far" inconsistently -- and every leap test reads the second one.
func shape_sweep_fraction(shape: Shape3D, from: Vector3, to: Vector3, _mask: int) -> float:
	sweep_calls += 1
	queries_spent += 1
	for blocked: Vector3 in unreachable_nodes:
		if to.is_equal_approx(blocked) or from.is_equal_approx(blocked):
			return NavigationProbe.SWEEP_NO_TRAJECTORY
	var radius: float = radius_of(shape)
	# The origin overlap, answered separately for the same reason the real probe does it:
	# a launch pose inside rock has no trajectory, which is not the same as a trajectory
	# blocked immediately.
	if free_distance(from) <= radius:
		return NavigationProbe.SWEEP_NO_TRAJECTORY
	for sample: int in sweep_samples + 1:
		var travelled: float = float(sample) / float(sweep_samples)
		if free_distance(from.lerp(to, travelled)) <= radius:
			return travelled
	return 1.0


## Exact for analytic boxes, and needing none of the real probe's back-face reasoning --
## which is the whole point of the seam. The concave case it exists for is covered by
## tools/verify_navigation_csg.tscn against real physics instead.
func is_solid(point: Vector3, _mask: int, _probe_distance: float) -> bool:
	solid_calls += 1
	queries_spent += 1
	for box: AABB in solids:
		if box.has_point(point):
			return true
	return false


func surface_along(
	from: Vector3, direction: Vector3, max_distance: float, _mask: int
) -> NavSurfaceSample:
	surface_calls += 1
	queries_spent += 1
	var heading: Vector3 = direction.normalized()
	if heading.is_zero_approx() or max_distance <= 0.0:
		return NavSurfaceSample.missed(heading, max_distance)

	var nearest: float = max_distance
	var facing := Vector3.UP
	var found: bool = false
	for box: AABB in solids:
		var contact: Array = _ray_box(from, heading, max_distance, box)
		if contact.is_empty() or contact[0] >= nearest:
			continue
		nearest = contact[0]
		facing = contact[1]
		found = true
	if not found:
		return NavSurfaceSample.missed(heading, max_distance)
	return NavSurfaceSample.make(heading, from + heading * nearest, facing, nearest)


## Distance from `point` to the nearest solid. Zero inside one.
func free_distance(point: Vector3) -> float:
	var nearest: float = INF
	for box: AABB in solids:
		nearest = minf(nearest, _distance_to_box(point, box))
		if nearest <= 0.0:
			return 0.0
	return nearest


## Sphere radius, since ClearanceProfile's defaults are spheres. A test that supplies
## some other shape is asking a question this fake cannot answer, so it says so.
func radius_of(shape: Shape3D) -> float:
	var sphere := shape as SphereShape3D
	assert(sphere != null, "FakeNavigationProbe only understands SphereShape3D")
	return sphere.radius


## Slab intersection. Returns [distance, face_normal], or [] for a miss.
##
## Solved rather than marched, unlike the sweep above: a sweep only has to agree with
## itself, but a surface normal is the thing surface crawl steers by, and a marched
## approximation of it would make every crawl assertion a tolerance argument.
func _ray_box(from: Vector3, heading: Vector3, reach: float, box: AABB) -> Array:
	var enter: float = 0.0
	var exit: float = reach
	var entry_axis: int = -1
	var entry_sign: float = -1.0
	for axis: int in 3:
		var origin: float = from[axis]
		var step: float = heading[axis]
		if absf(step) < 1e-6:
			# Parallel to this pair of faces: either always between them, or never.
			if origin < box.position[axis] or origin > box.end[axis]:
				return []
			continue
		var near: float = (box.position[axis] - origin) / step
		var far: float = (box.end[axis] - origin) / step
		# Travelling in -axis enters through the HIGH face, whose outward normal is +axis.
		var sign_at_entry: float = -1.0
		if near > far:
			var swapped: float = near
			near = far
			far = swapped
			sign_at_entry = 1.0
		if near > enter:
			enter = near
			entry_axis = axis
			entry_sign = sign_at_entry
		exit = minf(exit, far)
		if enter > exit:
			return []
	if enter > reach:
		return []
	# entry_axis stays -1 when the origin is already inside the box, and a normal facing
	# back down the ray is what a physics ray reports for a surface it is sitting on.
	if entry_axis < 0:
		return [enter, -heading]
	var normal := Vector3.ZERO
	normal[entry_axis] = entry_sign
	return [enter, normal]


func _distance_to_box(point: Vector3, box: AABB) -> float:
	var outside := Vector3(
		maxf(maxf(box.position.x - point.x, 0.0), point.x - box.end.x),
		maxf(maxf(box.position.y - point.y, 0.0), point.y - box.end.y),
		maxf(maxf(box.position.z - point.z, 0.0), point.z - box.end.z)
	)
	return outside.length()
