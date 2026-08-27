class_name ClingerSurface
extends RefCounted

## Tangent-plane arithmetic for a body that lives on walls: projecting a heading into the
## surface it is holding, building a basis from a normal, and slewing between two of them
## without shearing. The maths is `SurfaceCrawlController`'s, rewritten here rather than
## imported, because the clinger is deliberately not a citizen of `gameplay/creature/`.

## How far off the rock the body rides. NEVER NEGATIVE: the level trimesh is
## backface-blind, so an origin inside rock is one no ray can see out of. MineralScatter
## carries the same figure for the same reason.
const SURFACE_LIFT := 0.05

## Past this, forward and up are close enough to parallel that a basis built from them is
## degenerate and the body spins rather than leans. CrawlerBody's figure.
const PARALLEL_LIMIT := 0.985

## Six world axes and eight cube diagonals -- CorridorProbe's set, without the dependency.
## Only ever cast when the body has lost the surface it was holding; an ordinary tick is
## one ray straight into the rock.
const FAN: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3.BACK,
	Vector3.FORWARD,
	Vector3(1, 1, 1),
	Vector3(1, 1, -1),
	Vector3(1, -1, 1),
	Vector3(1, -1, -1),
	Vector3(-1, 1, 1),
	Vector3(-1, 1, -1),
	Vector3(-1, -1, 1),
	Vector3(-1, -1, -1),
]


## `vector` with everything pointing along `normal` removed, so a heading that aimed into
## the rock comes back as one along it rather than being dropped.
static func project(vector: Vector3, normal: Vector3) -> Vector3:
	if normal.is_zero_approx():
		return vector
	var unit := normal.normalized()
	return vector - unit * vector.dot(unit)


## An orthonormal basis facing `forward` with `normal` as up. -Z is forward, matching
## Vector3.FORWARD and this project's facing convention.
##
## X IS `ahead.cross(up)` AND NOT `up.cross(ahead)`. The other order also yields the right
## forward and the right up, and is what SurfaceCrawlController writes -- but it is
## left-handed, and that module only ever reads the two vectors back out. Applied as a
## transform, as this one is, a mirrored basis flips the winding and the shell renders
## inside-out, because the palette material is single-sided.
static func basis_from(forward: Vector3, normal: Vector3) -> Basis:
	var up := normal.normalized()
	if up.is_zero_approx():
		return Basis.IDENTITY
	var ahead := project(forward, up)
	if ahead.is_zero_approx():
		return Basis.IDENTITY
	ahead = ahead.normalized()
	return Basis(ahead.cross(up), up, -ahead)


static func too_parallel(a: Vector3, b: Vector3) -> bool:
	if a.is_zero_approx() or b.is_zero_approx():
		return true
	return absf(a.normalized().dot(b.normalized())) > PARALLEL_LIMIT


## `from` turned toward `to` by at most `max_radians`.
static func turn_limited(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	var start := from.normalized()
	var goal := to.normalized()
	if start.is_zero_approx() or goal.is_zero_approx():
		return from
	var angle := start.angle_to(goal)
	if angle <= max_radians:
		return goal
	var axis := start.cross(goal)
	# Exactly opposed, so every axis is equally correct. Picking one beats normalising a
	# zero, which returns NaN and keeps returning it for the rest of the run.
	if axis.is_zero_approx():
		axis = start.cross(Vector3.UP)
		if axis.is_zero_approx():
			axis = start.cross(Vector3.RIGHT)
	return start.rotated(axis.normalized(), max_radians)


## The current pose turned toward `target`, rate-limited so the up vector never snaps.
static func slew(
	current_forward: Vector3, current_up: Vector3, target: Basis, max_radians: float
) -> Basis:
	var forward := turn_limited(current_forward, -target.z, max_radians)
	var up := turn_limited(current_up, target.y, max_radians)
	# Re-orthogonalise: two independently turned vectors do not stay perpendicular, and a
	# basis built from a skewed pair shears the body a little more every frame.
	forward = forward.normalized()
	var side := forward.cross(up)
	if side.is_zero_approx():
		return target
	side = side.normalized()
	return Basis(side, (-forward).cross(side).normalized(), -forward)


## Where a shed clinger is trying to be: a point on a circle about the player, in the plane
## of whatever surface it is currently holding.
static func orbit_target(
	player_at: Vector3, from: Vector3, normal: Vector3, radius: float, phase: float
) -> Vector3:
	if normal.is_zero_approx():
		return from
	var out := project(from - player_at, normal)
	if out.is_zero_approx():
		out = project(Vector3.RIGHT, normal)
	if out.is_zero_approx():
		out = project(Vector3.UP, normal)
	if out.is_zero_approx():
		return from
	return player_at + out.normalized().rotated(normal.normalized(), phase) * radius


## Frame-rate independent lerp weight for a first-order chase at `rate` per second.
static func smoothing(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0))
