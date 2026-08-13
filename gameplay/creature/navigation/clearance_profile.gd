class_name ClearanceProfile
extends Resource

## The alien's two collision envelopes (navigation.md section 6).
##
## THE RADIUS EQUIVALENTS AND THE SHAPES ANSWER DIFFERENT QUESTIONS, and conflating
## them is the single easiest way to break section 13.2. The radii are a coarse scalar
## used to reject candidate points against a sampled clearance value; the shapes are
## what actually decides whether an edge exists, via a swept cast. Section 6 says so
## outright: "the radius equivalents are used for coarse clearance tests. Actual
## feasibility is determined using the collision shapes."
##
## They are therefore allowed to disagree. A capsule alien has one radius equivalent
## and a shape that is much longer than it is wide, and the coarse test being slightly
## optimistic is fine -- the swept cast is downstream of it and has the final say. The
## reverse (a radius equivalent LARGER than the shape) is not fine: it rejects
## candidates in space the alien would actually fit, and the shape cast never gets the
## chance to disagree because the node was never created.
##
## Section 6 puts the squeeze at "a total body diameter reduction of approximately
## 1.0 m", which is where the shipped defaults come from: 2.2 m across normally,
## 1.2 m compressed.
##
## A bare `ClearanceProfile.new()` is fully usable. The shapes are built on demand from
## the radii, so nothing needs a .tres until someone wants a non-spherical body.

## Normal body radius for coarse clearance tests.
@export_range(0.1, 8.0, 0.01, "or_greater", "suffix:m") var normal_radius_equivalent: float = 1.1
## Compressed body radius. Section 6's ~1.0 m diameter reduction, halved.
@export_range(0.05, 8.0, 0.01, "or_greater", "suffix:m") var squeezed_radius_equivalent: float = 0.6
## Added to both radii before any clearance comparison.
##
## This is the difference between "the alien fits exactly" and "the alien fits". Zero
## produces a graph full of edges the locomotion layer then grinds against, which is
## exactly the section 40.2 crevice-grinding failure the margin exists to prevent.
@export_range(0.0, 2.0, 0.01, "suffix:m") var safety_margin: float = 0.15

## Overrides the sphere built from `normal_radius_equivalent`. Null is the normal case.
@export var normal_shape: Shape3D = null
## Overrides the sphere built from `squeezed_radius_equivalent`. Null is the normal case.
@export var squeezed_shape: Shape3D = null

var _normal_fallback: SphereShape3D = null
var _squeezed_fallback: SphereShape3D = null


## The shape section 13.2 casts first. An edge it clears is NORMAL_VOLUME.
func normal_body() -> Shape3D:
	if normal_shape != null:
		return normal_shape
	if _normal_fallback == null:
		_normal_fallback = SphereShape3D.new()
	# Rebuilt rather than cached-and-trusted: the radius is an @export and the sandbox
	# changes it live, and a stale cached sphere silently keeps validating edges against
	# the body size the alien had two seconds ago.
	_normal_fallback.radius = normal_clearance()
	return _normal_fallback


## The shape section 13.2 falls back to. An edge only this one clears is WIGGLE.
func squeezed_body() -> Shape3D:
	if squeezed_shape != null:
		return squeezed_shape
	if _squeezed_fallback == null:
		_squeezed_fallback = SphereShape3D.new()
	_squeezed_fallback.radius = min_traversal_clearance()
	return _squeezed_fallback


## Clearance the normal body needs. Below this a route is WIGGLE at best.
func normal_clearance() -> float:
	return normal_radius_equivalent + safety_margin


## Clearance below which nothing is traversable at all (section 10.3).
##
## This is the section 12.1 candidate reject threshold, and it is also the whole of
## Invariant 5. A player-only tunnel is not a flagged special case -- it is simply a
## passage narrower than this number, so no candidate survives inside it and no edge
## is ever validated through it.
func min_traversal_clearance() -> float:
	return squeezed_radius_equivalent + safety_margin


func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if normal_radius_equivalent <= 0.0:
		failures.append("normal_radius_equivalent must be positive")
	if squeezed_radius_equivalent <= 0.0:
		failures.append("squeezed_radius_equivalent must be positive")
	if squeezed_radius_equivalent > normal_radius_equivalent:
		var sizes: Array = [squeezed_radius_equivalent, normal_radius_equivalent]
		failures.append("squeezed radius %.2f exceeds normal %.2f; squeezing enlarges it" % sizes)
	if safety_margin < 0.0:
		failures.append("safety_margin must not be negative")
	return failures
