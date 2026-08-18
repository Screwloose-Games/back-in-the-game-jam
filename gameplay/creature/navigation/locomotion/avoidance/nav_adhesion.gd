class_name NavAdhesion
extends RefCounted

## Keeping the body on the surface it is holding (navigation.md section 8.1).

## THE CONTACT HALF OF `avoidance/`, and it is a different failure from its sibling's.
## `NavAvoidance` answers "something is too close in the direction I am going"; this
## answers "the thing I am holding on to is getting too far away". They share a reading
## and share nothing else, which is why they are two files rather than one with two moods.
##
## SECTION 8.1 SAYS "MAINTAINING BODY CONTACT" AND THE MODULE'S DEFINITION OF CONTACT WAS
## "WITHIN TENTACLE REACH", WITH NOTHING EVER CLOSING THE GAP. So a crawler drifts outward
## -- pushed by the swimmer's centring at a tunnel mouth, or simply by velocity that
## outlasts the steer that created it -- until it passes `crawl_surface_reach`, at which
## point the fan finds nothing, the crawler refuses, and the alien is finished for the rest
## of the run. Observed at (15.9, 5.4, 6.6) in the demo cave: floating mid-room, 1.9 m from
## its next anchor, holding a COMPLETE route, with all ten rays missing.
##
## STATIC, STATELESS AND WITHOUT A PROBE, on the same terms as the rest of this directory:
## it reads the fan somebody else already paid for and returns a vector.


## Toward the surface the body is holding, when it has drifted off it.
##
## THE PULL COMES FROM `nearest.direction`, NOT FROM THE NORMAL. That field is the fan ray
## that found the surface, so it already points from the body at it: no normal to flip, no
## sign to get wrong, and it stays correct on an overhang where the surface normal and the
## direction to the surface are not opposite.
##
## Capped, because adhesion is a correction and not a destination. Uncapped, a body that
## has drifted 3 m returns a pull that dwarfs the step it was taking and the crawler stops
## making progress in order to hug a wall.
static func pull(reading: NavSurfaceReading, hold: float, gain: float, cap: float) -> Vector3:
	if reading == null or not reading.has_surface() or gain <= 0.0 or cap <= 0.0:
		return Vector3.ZERO
	var excess: float = reading.nearest_distance() - hold
	if excess <= 0.0:
		return Vector3.ZERO
	return reading.nearest.direction.normalized() * minf(excess * gain, cap)
