class_name NavSurfaceReading
extends RefCounted

## One fan of surface probes taken at a single body pose, plus the three scalars sections
## 9 and 21 derive from it.
##
## THE FAN IS PAID FOR ONCE AND READ THREE WAYS, which is the only reason the local
## planner fits inside section 32's budget. Surface crawl wants the nearest surface and
## its normal (section 8.1); tunnel swim wants how enclosed the body is (section 9.3) and
## which way the middle of the tunnel lies (section 9.1). Those are three questions about
## the same set of rays, so taking three sets of rays would triple the per-tick cost to
## learn nothing new.
##
## `medial` IS AN APPROXIMATION OF AN APPROXIMATION, AND THAT IS FINE. Section 9.1 wants
## the local medial axis and offers the clearance field as "an approximation of this
## axis". Sampling that field's gradient costs six `clearance_at` calls -- 42 probe
## queries -- every tick. This instead sums the inverse-weighted inward directions of a
## fan the crawler has already paid for, which points the same way for nothing.

var samples: Array[NavSurfaceSample] = []
## The closest hit, or null when the fan found nothing at all.
var nearest: NavSurfaceSample = null
## Fraction of the fan that found terrain within reach, 0..1. Section 9.3's
## confined-space test, computed from local geometry rather than read off a flag.
var enclosure: float = 0.0
## Unit direction away from nearby walls, or ZERO in the open. Section 9.1's centering.
var medial: Vector3 = Vector3.ZERO
## Normal of the surface the body would consider itself on. UP when nothing was found.
var dominant_normal: Vector3 = Vector3.UP


static func make(
	p_samples: Array[NavSurfaceSample],
	p_nearest: NavSurfaceSample,
	p_enclosure: float,
	p_medial: Vector3
) -> NavSurfaceReading:
	var reading := NavSurfaceReading.new()
	reading.samples = p_samples
	reading.nearest = p_nearest
	reading.enclosure = p_enclosure
	reading.medial = p_medial
	if p_nearest != null:
		reading.dominant_normal = p_nearest.normal
	return reading


## Whether anything is within tentacle reach. Invariant 3's question, and the reason
## surface crawl is allowed to refuse a tick.
func has_surface() -> bool:
	return nearest != null


## Distance to the nearest surface, or INF. Used as the crawler's clearance proxy, which
## is cheaper than a `clearance_at` and answers the same question at this scale.
func nearest_distance() -> float:
	if nearest == null:
		return INF
	return nearest.distance


func to_dictionary() -> Dictionary:
	return {
		"samples": samples.size(),
		"hit": has_surface(),
		"nearest_distance": nearest_distance(),
		"enclosure": enclosure,
		"medial": medial,
		"dominant_normal": dominant_normal,
	}
