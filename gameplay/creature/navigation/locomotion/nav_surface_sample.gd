class_name NavSurfaceSample
extends RefCounted

## One probed surface hit, or a miss (navigation.md section 8.1).
##
## SECTION 8.1'S "GRABBABLE TERRAIN SURFACE", AS A RECORD RATHER THAN A DICTIONARY.
## Surface crawl needs a position AND a normal, and no probe method shipped in phases 1-2
## returns either: `shape_fits` and `shape_sweep_clear` answer bool, `clearance_at`
## answers one scalar. A crawler cannot steer along a wall whose distance is the only
## thing it can measure.
##
## A MISS IS A SAMPLE, NOT A NULL. Section 21 scores a fan of directions every tick, and
## in an open chamber most of them miss. Returning null for those forces every consumer
## to branch before it can read `direction` -- which is the one field a miss still
## carries, and the field the fan's geometry is built out of.

## The direction probed, normalised. Meaningful on a miss as well as a hit.
var direction: Vector3 = Vector3.FORWARD
var hit: bool = false
var point: Vector3 = Vector3.ZERO
## Surface normal at `point`. Left as UP on a miss rather than zeroed, so a caller that
## reads it unguarded gets a usable basis instead of a degenerate one.
var normal: Vector3 = Vector3.UP
## Distance from the ray origin to `point`. On a miss this is the probed reach, so
## scoring can divide by it without a special case and an unreached direction scores as
## the worst possible surface rather than as division by zero.
var distance: float = 0.0


static func make(
	p_direction: Vector3, p_point: Vector3, p_normal: Vector3, p_distance: float
) -> NavSurfaceSample:
	var sample := NavSurfaceSample.new()
	sample.direction = p_direction
	sample.hit = true
	sample.point = p_point
	sample.normal = p_normal
	sample.distance = p_distance
	return sample


static func missed(p_direction: Vector3, p_reach: float) -> NavSurfaceSample:
	var sample := NavSurfaceSample.new()
	sample.direction = p_direction
	sample.hit = false
	sample.point = Vector3.ZERO
	sample.normal = Vector3.UP
	sample.distance = p_reach
	return sample


func to_dictionary() -> Dictionary:
	return {
		"direction": direction,
		"hit": hit,
		"point": point,
		"normal": normal,
		"distance": distance,
	}
