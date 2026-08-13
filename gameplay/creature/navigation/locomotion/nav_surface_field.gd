class_name NavSurfaceField
extends RefCounted

## Turns probe rays into "where can I hold on" (navigation.md sections 8.1, 9.1, 21).
##
## THE ONE PLACE LOCAL GEOMETRY IS SAMPLED. Section 21 asks the crawler to steer by local
## geometry rather than by voxel-perfect paths, and section 9.3 asks that confinement be
## decided by geometry rather than by a hand-authored tunnel flag. Both need the same fan
## of rays, so both get it from here and neither takes its own.
##
## THE PROBE IS AN ARGUMENT, NEVER A FIELD. Same seam the rest of the module uses: this
## class holds no world, no clock and no state at all, so a test can hand it an analytic
## fake and assert on exact distances.
##
## THE FAN IS DETERMINISTIC AND ORIENTATION-INDEPENDENT -- a Fibonacci lattice in world
## axes, the same construction SuspicionHotspotField uses for the same reason. Two
## consequences worth knowing: the same pose always produces the same reading, so a test
## that passes once passes always; and enclosure does not change when the body rolls,
## which is what makes section 9.3's threshold a statement about the tunnel rather than
## about the alien's posture.

## PI * (3 - sqrt(5)). The angle that makes a Fibonacci lattice spread evenly instead of
## banding, stored pre-computed because a const initialiser cannot call sqrt().
const GOLDEN_ANGLE: float = 2.399963229728653


## Directions to probe: the six axes first, then a Fibonacci fill. Deterministic.
##
## THE SIX AXES ARE NOT DECORATION, AND LEAVING THEM OUT COST AN ALIEN ITS FLOOR. A pure
## Fibonacci lattice contains no axis-aligned ray -- at ten samples the most vertical one
## has a y component of 0.9 -- so `crawl_surface_reach` does not mean what it says. Its
## effective reach straight down is 0.9 of the nominal, and a body 3.4 m above a floor
## with a 3.5 m reach finds NOTHING, reports itself unsupported, and stops dead. That is
## observed, not theoretical: the creature swam out of the demo cave's tunnel and stalled
## 4.4 m from its goal with `nearest surface inf` over a floor 3.4 m below it.
##
## Axis-aligned rays are also the ones most likely to matter. Floors, walls and tunnel
## bores in a boxy cave are axis-aligned, and even in an organic one the question "how far
## is the surface I am lying on" is asked perpendicular to that surface.
static func fan_directions(count: int) -> PackedVector3Array:
	var directions := PackedVector3Array(
		[
			Vector3.RIGHT,
			Vector3.LEFT,
			Vector3.UP,
			Vector3.DOWN,
			Vector3.BACK,
			Vector3.FORWARD,
		]
	)
	var extra: int = maxi(count, directions.size()) - directions.size()
	for index: int in extra:
		# Equal-area bands in y, then the golden angle around. Closed form, no rejection
		# sampling, no RNG -- which is what makes it repeatable.
		var height: float = 1.0 - 2.0 * (float(index) + 0.5) / float(extra)
		var ring: float = sqrt(maxf(1.0 - height * height, 0.0))
		var angle: float = GOLDEN_ANGLE * float(index)
		directions.append(Vector3(cos(angle) * ring, height, sin(angle) * ring))
	return directions


## Fraction of the fan that found terrain within `reach`. Section 9.3.
static func enclosure_of(samples: Array[NavSurfaceSample], reach: float) -> float:
	if samples.is_empty() or reach <= 0.0:
		return 0.0
	var enclosed: int = 0
	for sample: NavSurfaceSample in samples:
		if sample.hit and sample.distance <= reach:
			enclosed += 1
	return float(enclosed) / float(samples.size())


## Unit direction away from nearby walls, or ZERO when nothing is near. Section 9.1.
##
## Each hit pushes back along its own direction, weighted by 1/distance, so a wall at 1 m
## counts for four times one at 4 m. In a symmetric tunnel the opposing walls cancel and
## the result is the tunnel axis -- which is exactly the medial answer, arrived at for the
## price of rays that were taken anyway.
static func medial_of(samples: Array[NavSurfaceSample], reach: float) -> Vector3:
	var push := Vector3.ZERO
	if reach <= 0.0:
		return push
	for sample: NavSurfaceSample in samples:
		if not sample.hit or sample.distance > reach:
			continue
		push -= sample.direction / maxf(sample.distance, 0.01)
	if push.is_zero_approx():
		return Vector3.ZERO
	return push.normalized()


## The impure entry point. Never returns null: a fan that hit nothing is a reading with
## `enclosure` 0 and `nearest` null, which is a real and common answer in a big chamber.
func sample(
	at: Vector3, probe: NavigationProbe, profile: LocomotionProfile, mask: int
) -> NavSurfaceReading:
	var reach: float = maxf(profile.crawl_surface_reach, profile.tunnel_enclosure_reach)
	var samples: Array[NavSurfaceSample] = []
	var nearest: NavSurfaceSample = null
	for direction: Vector3 in fan_directions(profile.crawl_surface_ray_count):
		var found: NavSurfaceSample = probe.surface_along(at, direction, reach, mask)
		samples.append(found)
		if found.hit and (nearest == null or found.distance < nearest.distance):
			nearest = found
	var enclosure: float = enclosure_of(samples, profile.tunnel_enclosure_reach)
	return NavSurfaceReading.make(samples, nearest, enclosure, medial_of(samples, reach))


## The nearest surface at any distance, for a body that has lost contact with all of them.
## Null only in genuinely unbounded space.
##
## A SEPARATE METHOD RATHER THAN A LONGER DEFAULT FAN, and that is a cost decision rather
## than a taste one. `sample()` runs every tick of every mode; this runs only on a tick
## where that one found nothing at all, which by Invariant 3 means the body has slipped and
## is somewhere it may not legally be. Folding `recovery_reach` into the default fan would
## charge every ordinary tick for an answer only a slipped body needs -- and would also
## quietly break `enclosure`, which is a statement about terrain within *tentacle* reach
## and means nothing measured at 24 m.
##
## Reuses the same lattice, so the six principal axes are probed first here too. In a boxy
## cave the way back to a floor is almost always straight down one of them.
func reacquire(
	at: Vector3, probe: NavigationProbe, profile: LocomotionProfile, mask: int
) -> NavSurfaceSample:
	var nearest: NavSurfaceSample = null
	for direction: Vector3 in fan_directions(profile.crawl_surface_ray_count):
		var found: NavSurfaceSample = probe.surface_along(
			at, direction, profile.recovery_reach, mask
		)
		if found.hit and (nearest == null or found.distance < nearest.distance):
			nearest = found
	return nearest


## Section 19's surface-crawl shortcut test: is there continuous holdable surface all the
## way along this line?
##
## THIS IS WHAT KEEPS SMOOTHING FROM BREAKING INVARIANT 3. "Nothing is in the way" is not
## the question -- a straight line across an open chamber is perfectly unobstructed and
## is still not something a surface crawler can do. Any sample with no terrain within
## `crawl_surface_reach` is section 19's "unsupported open-space section", and one is
## enough to refuse the whole shortcut.
##
## Sampled a FIXED number of times rather than per metre, so the cost of considering a
## shortcut cannot grow with its length.
func continuous_surface_between(
	from: Vector3, to: Vector3, probe: NavigationProbe, config: NavigationConfig
) -> bool:
	var profile: LocomotionProfile = config.locomotion_profile
	var steps: int = maxi(config.smoothing_surface_samples, 2)
	for index: int in steps + 1:
		var at: Vector3 = from.lerp(to, float(index) / float(steps))
		var reading: NavSurfaceReading = sample(at, probe, profile, config.world_mask)
		if not reading.has_surface():
			return false
		if reading.nearest_distance() > profile.crawl_surface_reach:
			return false
	return true
