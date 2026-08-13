class_name NavigationProbe
extends RefCounted

## THE ONLY FILE IN THIS MODULE ALLOWED TO NAME A PHYSICS OR VOXEL QUERY.
##
## Every question this module asks the world goes through these seven methods and
## nothing else. `verify_navigation_static.gd` greps the whole module for
## `intersect_shape`, `cast_motion`, `intersect_ray`, `direct_space_state`, `VoxelTool`
## and friends, and fails if any file other than this one names them. That grep is what
## keeps the seam from eroding.
##
## The seam exists so the GUT suite can run with no scene, no world, no physics server
## AND NO VOXEL EXTENSION -- which matters more here than it did for perception,
## because `addons/zylann.voxel` is a GDExtension that is not present in the CI image.
## Tests substitute a subclass with scripted answers. The subclass EXTENDS this class
## rather than duck-typing it, so changing a signature here breaks every fake at parse
## time instead of at assertion time.
##
## AN UNBOUND PROBE REFUSES EVERYTHING, which is the opposite of what PerceptionProbe
## does and is deliberate. Perception's permissive defaults make an unbound alien deaf
## and blind -- a visibly broken creature. Navigation's permissive defaults would make
## every shape cast succeed, every candidate look infinitely open, and the builder
## connect every node to every other through solid rock: an alien that walks through
## walls, in a graph that looks entirely plausible in the overlay. Refusing instead
## produces an empty graph, which is impossible to mistake for working.
##
## TERRAIN THIS MODULE MEASURES MUST BE CONVEX, OR MUST ANSWER `is_solid` ITSELF.
## `clearance_at` and `shape_fits` are overlap tests, so they need something to overlap.
## A concave trimesh -- what CSG and voxel meshing both produce -- has no interior, so a
## point deep inside rock touches no triangle and measures as wide open. `is_solid` closes
## that hole for convex colliders exactly, and cannot close it for trimeshes at all under
## Jolt; its docstring records the three measurements that establish this, and
## tools/verify_navigation_csg.tscn pins them so a future engine change is caught rather
## than assumed. The consequence for callers is a build-time one, not a runtime one:
## greybox with CSG if you like, but collide with generated convex boxes, which is what
## NavigationSandboxGeometry does and why the phase 1-2 suite never met this.

## Safe-fraction at or above which a swept cast counts as having completed. Godot
## returns exactly 1.0 for an unobstructed sweep; the epsilon is against float drift
## on very long edges, not against a real partial block.
const SWEEP_CLEAR_FRACTION: float = 0.999
## Fraction returned when a sweep has no trajectory at all -- an origin already in
## penetration, or a query the engine could not resolve.
##
## DELIBERATELY NOT 0.0. A leap blocked at its first centimetre still has a direction and
## a landing point; a leap whose launch pose is inside rock has neither, and the leap
## planner has to reject the two for different reasons. Any comparison against
## SWEEP_CLEAR_FRACTION treats this as blocked either way.
const SWEEP_NO_TRAJECTORY: float = -1.0
## The heading `is_solid` casts along.
##
## CHOSEN TO LIE IN NO AXIS PLANE AND ON NO 45-DEGREE DIAGONAL, so the ray can never run
## along a box face or a triangle edge -- the two places a ray/trimesh intersection is
## free to answer either way. Stored pre-normalised because a const initialiser cannot
## call a method. It is Vector3(1.0, 1.7, 2.3) normalised.
const SOLIDITY_HEADING := Vector3(0.330116, 0.561197, 0.759266)
## Smallest sphere the clearance search will test. Below this the answer is "no
## traversable space here" for every body the alien has, so the remaining bisection
## steps would be spent resolving a number nothing reads.
const MIN_PROBED_RADIUS: float = 0.01

## Space queries issued since the last `reset_query_count()`.
##
## Counted HERE rather than estimated by the caller, because this is the only file that
## knows how many queries a clearance sample actually costs. NavGraphBuilder spends the
## section 32 frame budget against this number, and an estimate that drifts from
## reality is a frame budget that silently stops being one.
var queries_spent: int = 0

var _world: World3D = null
var _sphere: SphereShape3D = null


## Fetched fresh per query rather than cached. A PhysicsDirectSpaceState3D held across
## frames is a documented way to get "Can't change this state while flushing queries";
## holding the World3D and asking it each time costs nothing.
func bind(world: World3D) -> void:
	_world = world


func is_bound() -> bool:
	return _world != null


func reset_query_count() -> void:
	queries_spent = 0


## Distance from `point` to the nearest solid terrain, capped at `max_radius`
## (section 5.1).
##
## Bisection on a growing sphere rather than a distance transform. Section 4's dense
## 0.24 m field is ~2M cells across a 30 m cave, which no amount of GDScript fits into
## the section 32 budget; section 5.1 licenses the approximation outright, because
## exact traversal feasibility is decided later by `shape_sweep_clear` and not by this
## number.
##
## Costs `1 + steps` queries. Each step halves the remaining error, so the default 6
## resolves a 6 m ceiling to about 9 cm -- finer than the field it replaces.
func clearance_at(point: Vector3, mask: int, max_radius: float, steps: int) -> float:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null:
		return 0.0
	if max_radius <= MIN_PROBED_RADIUS:
		return 0.0
	# Open space measures as open. Without this early out, wide chambers cost the full
	# bisection to report a number the caller clamps to the ceiling anyway.
	if _sphere_fits(space, point, mask, max_radius):
		return max_radius

	var low: float = 0.0
	var high: float = max_radius
	for _step: int in maxi(steps, 1):
		var mid: float = 0.5 * (low + high)
		if _sphere_fits(space, point, mask, mid):
			low = mid
		else:
			high = mid
	return low


## Whether the body fits, stationary, at this pose.
##
## Returns FALSE when unbound, per the refuse-everything rule above.
func shape_fits(shape: Shape3D, at: Transform3D, mask: int) -> bool:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null or shape == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	queries_spent += 1
	return space.intersect_shape(query, 1).is_empty()


## Whether the body can sweep from `from` to `to` without touching terrain
## (section 13.2).
##
## A SWEPT SHAPE, NOT A RAY, and section 13.2 is explicit about it. A ray is a
## zero-radius body: it threads a two-metre alien through a ten-centimetre crack and
## reports a perfectly good edge, which is exactly the Scenario C and G failure.
##
## THE ORIGIN OVERLAP TEST IS NOT OPTIONAL. `cast_motion` returns [0, 0] for a shape
## that is already in penetration at the start of the sweep -- the same answer it gives
## for a legitimate immediate block. Without the separate test, a body spawned slightly
## inside geometry makes every single edge from that node fail validation, and the node
## is silently isolated with nothing in the log to say why.
func shape_sweep_clear(shape: Shape3D, from: Vector3, to: Vector3, mask: int) -> bool:
	return shape_sweep_fraction(shape, from, to, mask) >= SWEEP_CLEAR_FRACTION


## How far along the sweep the body gets, as a fraction of `to - from`, or
## SWEEP_NO_TRAJECTORY.
##
## `shape_sweep_clear` is written in terms of this rather than the other way around,
## because section 11 needs the number and section 13.2 only needs the comparison.
## Query cost and every rejection rule are therefore shared by construction, which is the
## point: an edge and a leap must agree about what fits.
func shape_sweep_fraction(shape: Shape3D, from: Vector3, to: Vector3, mask: int) -> float:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null or shape == null:
		return SWEEP_NO_TRAJECTORY

	var motion: Vector3 = to - from
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.motion = motion

	queries_spent += 1
	if not space.intersect_shape(query, 1).is_empty():
		return SWEEP_NO_TRAJECTORY
	if motion.length_squared() <= 0.0:
		return 1.0

	queries_spent += 1
	var fractions: PackedFloat32Array = space.cast_motion(query)
	# Godot returns an empty array if the query could not be resolved at all. Treating
	# that as clear would invent an edge out of an engine error.
	if fractions.size() < 2:
		return SWEEP_NO_TRAJECTORY
	return fractions[0]


## The nearest terrain surface along `direction`, with its normal (section 8.1).
##
## The one query in this file that IS a ray, and legitimately so: it asks where a surface
## is, not whether a body fits through a gap. Section 13.2's ban on rays is about the
## second question, where a zero-radius probe threads a two-metre alien through a
## ten-centimetre crack. Nothing here decides feasibility.
##
## Costs 1 query. Section 21 spends a fan of these per tick and that is the crawler's
## whole per-frame budget, so the count is the caller's to choose.
func surface_along(
	from: Vector3, direction: Vector3, max_distance: float, mask: int
) -> NavSurfaceSample:
	var heading: Vector3 = direction.normalized()
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null or max_distance <= 0.0 or heading.is_zero_approx():
		return NavSurfaceSample.missed(heading, max_distance)

	var query := PhysicsRayQueryParameters3D.create(from, from + heading * max_distance, mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	queries_spent += 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return NavSurfaceSample.missed(heading, max_distance)

	var point: Vector3 = result["position"]
	return NavSurfaceSample.make(heading, point, result["normal"], from.distance_to(point))


## Whether `point` lies inside solid matter. EXACT FOR CONVEX COLLIDERS ONLY.
##
## THE ANSWER `clearance_at` AND `shape_fits` CANNOT GIVE FOR THEMSELVES. Both are overlap
## tests, so they need something to overlap; a point deep inside rock touches nothing and
## measures as wide open. For a convex collider that never arises -- a sphere inside a box
## overlaps the box -- which is why nothing in phases 1-2 needed this. It arises the
## moment terrain is a trimesh, which is what CSG and voxel meshing both produce.
##
## HOW IT WORKS, AND WHY IT IS ONLY HALF AN ANSWER. Jolt reports a ray that begins inside
## a CONVEX shape as a hit at the ray's own origin with a ZEROED NORMAL. No real surface
## hit produces that, so it is an exact and cheap tell.
##
## THERE IS NO EQUIVALENT TELL FOR A CONCAVE TRIMESH UNDER JOLT, and this was measured
## rather than assumed -- see tools/verify_navigation_csg.tscn, which pins all three
## behaviours. A ray starting inside a CSG collider returns NOTHING, because back faces
## are not hit and every boundary it would cross is a back face. Turning on the shape's
## own `backface_collision` does register the hit, but Jolt then FLIPS the reported normal
## to face the ray -- making a back-face hit byte-identical to a legitimate front-face hit
## from open space. So neither "no hit" nor the normal's orientation separates rock from
## air, and the obvious raycast fix genuinely does not exist here.
##
## THE CONSEQUENCE, STATED PLAINLY: terrain this module must measure exactly has to be
## convex, or has to answer this question itself. `NavigationSandboxGeometry` builds the
## test cave from convex boxes for exactly this reason, and voxel terrain will override
## this method in a VoxelTool-backed subclass where the occupancy field answers directly
## and no ray is involved. A greybox that wants CSG's authoring convenience should draw
## with CSG and collide with generated convex boxes.
##
## RETURNS TRUE WHEN UNBOUND, which is the refuse-everything rule pointed the immobilising
## way. "Everything is rock" produces an empty graph; "nothing is rock" produces a graph
## full of nodes inside walls, and only one of those is impossible to mistake for working.
func is_solid(point: Vector3, mask: int, probe_distance: float) -> bool:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null or probe_distance <= 0.0:
		return true

	var query := PhysicsRayQueryParameters3D.create(
		point, point + SOLIDITY_HEADING * probe_distance, mask
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	queries_spent += 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return false
	# The convex tell, and the only one this engine gives. Jolt reports the hit AT the
	# ray origin with a zeroed normal, which no legitimate surface hit ever produces.
	return Vector3(result["normal"]).is_zero_approx()


# ----- internals -----


func _space() -> PhysicsDirectSpaceState3D:
	if _world == null:
		return null
	return _world.direct_space_state


## The sphere is reused across calls. A fresh SphereShape3D per bisection step would
## allocate seven resources per candidate, and a full bake samples thousands.
func _sphere_fits(
	space: PhysicsDirectSpaceState3D, point: Vector3, mask: int, radius: float
) -> bool:
	if radius <= 0.0:
		return true
	if _sphere == null:
		_sphere = SphereShape3D.new()
	_sphere.radius = radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	queries_spent += 1
	return space.intersect_shape(query, 1).is_empty()
