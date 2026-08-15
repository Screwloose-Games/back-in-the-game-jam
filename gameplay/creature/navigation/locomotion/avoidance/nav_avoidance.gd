class_name NavAvoidance
extends RefCounted

## Local obstacle avoidance, from rays that have already been paid for (navigation.md
## sections 9.2, 21).
##
## THE OBSTACLE HALF OF `avoidance/`. Its sibling `NavAdhesion` answers the opposite
## failure -- too far from the surface rather than too close to a wall -- off the same
## reading. Both are here, and nothing else in the directory is, because a solver that
## could take a ray or issue a command would be a second movement system running beside
## the four modes rather than a bias applied to them.
##
## THE MODULE HAD FOUR THINGS THAT LOOKED LIKE AVOIDANCE AND NONE THAT DID IT. Section 21's
## `collision_penalty` was set by `SurfaceCrawlController` only AFTER a swept cast had
## already failed -- which is after scoring is over, so it never influenced which direction
## was chosen and existed purely for the overlay. `NavSurfaceReading.medial` is
## direction-agnostic: it centres a body in a tunnel and says nothing whatever about the
## wall the body is angling at. `TunnelSwimController` had exactly one candidate direction.
## And the crawl fan is an arc around the current heading, so an obstacle needing a wider
## turn had no candidate at all. Between them the alien could reject a step into rock but
## could not steer around it.
##
## IT TAKES NO RAYS OF ITS OWN, AND THAT IS THE WHOLE DESIGN. `NavSurfaceField` already
## fans ten directions per tick for enclosure and the medial axis; both questions here --
## "is this direction heading into something" and "which way is not" -- are answerable from
## that same set. The alternative, one forward ray per crawl candidate, would take the
## crawler from 10 rays a tick to 19 to learn something the fan already knew.
##
## STATIC, STATELESS, AND WITHOUT A PROBE, matching the rest of `locomotion/`. Every
## function here is assertable against a hand-built reading with exact distances, which is
## what makes a retune a failure with a name rather than an alien that moves differently.
##
## THE RESOLUTION IS THE FAN'S, NOT THE GEOMETRY'S. Ten rays over a sphere is roughly a 40
## degree spacing, so this is a soft, wide-angle sense of "something over there", not a
## substitute for the swept cast that actually validates a step. Both are needed and they
## answer different questions: this one biases the choice, the cast vetoes it.


## How much `direction` heads into something, 0 for clear and 1 for pressed against it.
##
## THE MAXIMUM OVER SAMPLES RATHER THAN THE SUM. A body in a corridor has walls on both
## sides and is in no danger from either while it travels down the middle; summing would
## make the safest place in a tunnel score as the most dangerous. What matters is the worst
## single thing in the way, which is what a sum cannot express and a maximum can.
##
## Samples behind the direction of travel are skipped rather than weighted -- a wall the
## body is moving away from is not a collision risk, and charging for it is how a creature
## ends up refusing to leave a surface it is standing on.
static func risk(direction: Vector3, reading: NavSurfaceReading, margin: float) -> float:
	if direction.is_zero_approx() or reading == null or margin <= 0.0:
		return 0.0
	var heading: Vector3 = direction.normalized()
	var worst: float = 0.0
	for sample: NavSurfaceSample in reading.samples:
		if not sample.hit:
			continue
		var alignment: float = heading.dot(sample.direction)
		if alignment <= 0.0:
			continue
		var closeness: float = clampf(1.0 - sample.distance / margin, 0.0, 1.0)
		worst = maxf(worst, alignment * closeness)
	return worst


## `direction` with the part of it heading into nearby terrain removed.
##
## SUBTRACTIVE RATHER THAN A BLEND WITH `medial`, and the difference is the point of this
## function. Blending toward the medial axis moves a body away from every wall equally;
## subtracting the inward component of the walls it is actually pointing at leaves the
## direction alone when it is already clear. A swimmer heading straight down a tunnel
## should not be pushed anywhere, and a swimmer angling at the wall should be pushed
## exactly as much as it is angling.
##
## `strength` scales how hard, so a caller that was refused can ask again more firmly
## rather than reaching for a different mechanism. Returns the input unchanged when
## nothing is in the way, and falls back to the input when the correction cancels it
## entirely -- there is no better answer available from this data, and returning ZERO
## would silently stop the body.
static func steer_clear(
	direction: Vector3, reading: NavSurfaceReading, margin: float, strength: float
) -> Vector3:
	if direction.is_zero_approx() or reading == null or margin <= 0.0 or strength <= 0.0:
		return direction
	var heading: Vector3 = direction.normalized()
	var correction := Vector3.ZERO
	for sample: NavSurfaceSample in reading.samples:
		if not sample.hit:
			continue
		var alignment: float = heading.dot(sample.direction)
		if alignment <= 0.0:
			continue
		var closeness: float = clampf(1.0 - sample.distance / margin, 0.0, 1.0)
		correction -= sample.direction * alignment * closeness
	if correction.is_zero_approx():
		return heading
	var steered: Vector3 = heading + correction * strength
	if steered.is_zero_approx():
		return heading
	return steered.normalized()
