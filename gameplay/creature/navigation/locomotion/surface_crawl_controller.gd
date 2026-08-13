class_name SurfaceCrawlController
extends RefCounted

## Steers the body along terrain it is holding (navigation.md sections 8, 21, 22, 23).
##
## SCORED STEERING, NOT A PATH. Section 21 is explicit that the crawler "should not
## attempt to generate voxel-perfect paths" -- it samples local geometry, scores a fan of
## directions and takes the best one. The route only says roughly where to end up; how the
## body gets around this particular outcrop is decided here, one tick at a time.
##
## EVERY TERM IS A SEPARATE STATIC FUNCTION, and that is deliberate. Section 21 gives six
## weighted terms and calls the weights "tuning parameters", which means they will be
## retuned by someone watching an alien move, not by someone reading this file. A single
## fused score function can be tested only through its winner; six pure functions can each
## be asserted on their own, so a retune that breaks one is a failure with a name.
##
## THE CANDIDATES LIE IN THE SURFACE TANGENT PLANE. A crawler moves ALONG what it holds:
## directions with a component into the rock are not slow, they are impossible, and
## directions off the surface are section 11's leap and not this controller's business.
## Projecting first means the fan never contains an option the body cannot take.
##
## IT ALSO HOLDS ON, WHICH FOR A LONG TIME IT DID NOT. Section 8.1 says the crawler
## maintains body contact; the module's definition of contact was "within tentacle reach",
## and nothing ever closed the gap, so a body nudged outward -- by the swimmer's centring at
## a tunnel mouth, or by velocity outlasting the steer that made it -- drifted to the reach
## limit and then past it, and past it there is no surface to score against and no way back.
## `NavAvoidance.adhesion` is that missing half, and it is applied to the candidate step
## points so the pull is part of what gets validated.
##
## NULL IS A NORMAL ANSWER. Section 8.2: if the required surface cannot be reached while
## keeping contact, the alien must consider a leap instead. Returning a best-effort
## command there would be an alien drifting through open space, which Invariant 3 forbids
## and which no behavioural test would catch.

## Candidates scored so far this tick, for the section 39 overlay.
var last_candidates: Array[NavCrawlCandidate] = []
## Why the last call returned null, for the panel and for anyone debugging a stall.
##
## THE CRAWLER HAS FOUR VERY DIFFERENT WAYS TO REFUSE and they were all reported to the
## facade as one bare null, which the facade then labelled NO_SURFACE. That is right for
## exactly one of them; for the other three it is a stall whose stated reason is a lie,
## and chasing it costs an afternoon.
var last_refusal: String = ""


## How well a direction serves the goal. 0 for directly away, 1 for straight at it.
static func goal_alignment(direction: Vector3, to_goal: Vector3) -> float:
	if to_goal.is_zero_approx() or direction.is_zero_approx():
		return 0.0
	return 0.5 * (direction.normalized().dot(to_goal.normalized()) + 1.0)


## How good a hold the surface under a step point is. 1 for touching, 0 at the reach
## limit, 0 for nothing found -- so an unreachable direction scores as the worst hold
## rather than as no opinion.
static func surface_quality(surface: NavSurfaceSample, reach: float) -> float:
	if surface == null or not surface.hit or reach <= 0.0:
		return 0.0
	return clampf(1.0 - surface.distance / reach, 0.0, 1.0)


## Section 14's comfort term, reused locally: room to move is worth something, but only
## up to the point where more room stops mattering.
static func clearance_score(clearance: float, comfortable: float) -> float:
	if comfortable <= 0.0:
		return 0.0
	if is_inf(clearance):
		return 1.0
	return clampf(clearance / comfortable, 0.0, 1.0)


## Section 23. How little this direction disturbs the body's current facing.
static func orientation_continuity(direction: Vector3, forward: Vector3) -> float:
	if direction.is_zero_approx() or forward.is_zero_approx():
		return 0.0
	return 0.5 * (direction.normalized().dot(forward.normalized()) + 1.0)


## Section 22. What this turn costs, 0 for straight ahead and 1 for a reversal.
##
## SCALED BY WHAT THE BODY CAN ACTUALLY DO. A turn inside `max_angle` is free -- the body
## can simply make it -- and everything beyond is charged in proportion to how far beyond.
## Charging by raw angle instead would make a stationary alien, which can pivot freely,
## just as reluctant to turn as one at full speed.
static func turning_penalty(direction: Vector3, forward: Vector3, max_angle: float) -> float:
	if direction.is_zero_approx() or forward.is_zero_approx():
		return 0.0
	var turn: float = direction.normalized().angle_to(forward.normalized())
	if turn <= max_angle:
		return 0.0
	if max_angle >= PI:
		return 0.0
	return clampf((turn - max_angle) / (PI - max_angle), 0.0, 1.0)


## How much of top speed to use, given how far the body still has to turn (section 22).
##
## THE PENALTY ALONE WAS NOT ENOUGH, AND THIS IS THE DIFFERENCE BETWEEN AN ALIEN THAT
## ROUNDS A CORNER AND ONE THAT HITS IT. `turning_penalty` decides WHICH direction wins;
## `turn_limited` decides how fast the heading may rotate -- at the shipped 2.5 m radius
## and 5 m/s that is about two degrees per tick. Nothing decided how fast the body travels
## while it is still pointing the wrong way, so it travelled at full speed: a creature
## needing to turn 90 degrees covered four metres before it had turned thirty, which in a
## cave means it arrives at the wall it was trying to turn away from.
##
## Section 22 asks for exactly this -- turn cost that depends on "available turning
## distance" -- and slowing into a turn is what buys that distance.
static func cornering_speed(
	achieved: Vector3, wanted: Vector3, profile: LocomotionProfile
) -> float:
	if achieved.is_zero_approx() or wanted.is_zero_approx():
		return 1.0
	var alignment: float = achieved.normalized().dot(wanted.normalized())
	return lerpf(profile.crawl_cornering_floor, 1.0, clampf(alignment, 0.0, 1.0))


## Section 21's six terms, with the first four as rewards and the last two as penalties.
static func score(candidate: NavCrawlCandidate, profile: LocomotionProfile) -> float:
	return (
		candidate.goal_alignment * profile.weight_goal_alignment
		+ candidate.surface_quality * profile.weight_surface_quality
		+ candidate.clearance_score * profile.weight_clearance
		+ candidate.orientation_continuity * profile.weight_orientation_continuity
		- candidate.turning_penalty * profile.weight_turning_penalty
		- candidate.collision_penalty * profile.weight_collision_penalty
	)


## Section 22, applied as a constraint rather than a preference: the returned heading is
## the desired one rotated no further than the body could actually rotate this tick.
##
## The penalty above discourages sharp turns; this makes them impossible. Both are needed
## -- without the penalty the crawler keeps picking a direction it then cannot take and
## sidles toward it for several ticks; without the clamp a sufficiently attractive goal
## buys a pivot no amount of weighting forbids.
static func turn_limited(
	current: Vector3, desired: Vector3, speed: float, delta: float, profile: LocomotionProfile
) -> Vector3:
	if current.is_zero_approx():
		return desired.normalized()
	if desired.is_zero_approx():
		return current.normalized()
	var from: Vector3 = current.normalized()
	var to: Vector3 = desired.normalized()
	var limit: float = LocomotionProfile.max_turn_angle(speed, delta, profile.crawl_turn_radius)
	var turn: float = from.angle_to(to)
	if turn <= limit or turn <= 0.0:
		return to
	var axis: Vector3 = from.cross(to)
	if axis.is_zero_approx():
		# Exactly opposed, so every axis is equally valid and none is derivable. Any
		# perpendicular will do, and the next tick has a well-defined axis again.
		axis = from.cross(Vector3.UP)
		if axis.is_zero_approx():
			axis = from.cross(Vector3.RIGHT)
	return from.rotated(axis.normalized(), limit)


## Section 23. Body forward and up slewed toward their targets at a bounded rate.
##
## CONTINUITY, NOT SNAPPING. Global A* has no orientation (section 23 puts it here on
## purpose), so nothing upstream smooths this. An alien whose up vector jumps the instant
## it crosses from floor to wall reads as a bug even when every position is correct.
static func slew(
	current_forward: Vector3, current_up: Vector3, target: Basis, max_radians: float
) -> Basis:
	var forward: Vector3 = _rotate_toward(current_forward, -target.z, max_radians)
	var up: Vector3 = _rotate_toward(current_up, target.y, max_radians)
	# Re-orthogonalise: two independently slewed vectors do not stay perpendicular, and a
	# Basis built from a skewed pair shears the body a little more every frame.
	var side: Vector3 = up.cross(forward)
	if side.is_zero_approx():
		return target
	side = side.normalized()
	return Basis(side, side.cross(-forward).normalized(), -forward)


## The impure entry point. Null when nothing clears `crawl_minimum_score` -- section 8.2.
func steer(
	body: NavBodyState,
	toward: Vector3,
	reading: NavSurfaceReading,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	last_candidates = []
	last_refusal = ""
	if not reading.has_surface():
		last_refusal = "nothing within tentacle reach"
		return null
	var profile: LocomotionProfile = config.locomotion_profile
	var normal: Vector3 = reading.dominant_normal
	var to_goal: Vector3 = _project(toward - body.position, normal)
	var heading: Vector3 = _project(body.forward, normal)
	if heading.is_zero_approx():
		heading = to_goal
	if heading.is_zero_approx():
		# Both the body's facing and the goal lie along the surface normal, so there is no
		# direction in the tangent plane to score.
		last_refusal = "goal is straight into or out of the surface"
		return null

	_score_fan(
		body, heading, normal, to_goal, reading, probe, config, profile.crawl_candidate_arc_degrees
	)
	var chosen: NavCrawlCandidate = _best_validated(
		body, probe, config, profile.crawl_validated_count, true
	)
	if chosen == null:
		# THE ARC IS AN OPTIMISATION AND THIS IS ITS ESCAPE HATCH. Scoring nine directions
		# across 120 degrees is the right way to spend rays while the way ahead is open, and
		# exactly wrong at the one moment it matters: the way out of a dead end is usually
		# behind. Observed as an alien stopped in front of an outcrop with a COMPLETE route
		# and the whole rest of the sphere unexamined.
		#
		# THE ESCAPE PASS CASTS EVERY CANDIDATE AND IGNORES THE MINIMUM SCORE, and both of
		# those took a second observation to get right. A 360 degree fan still validated only
		# `crawl_validated_count` of its candidates, and the three best in a full circle are
		# the same three goal-ward directions the first pass already had blocked -- so the
		# alien re-cast the identical three and refused again, in a corner at the swim
		# tunnel's mouth with six unexamined directions behind it. Likewise the score gate:
		# a rear-facing candidate is charged for the turn and rewarded nothing for progress,
		# so it scores below `crawl_minimum_score` and used to break the loop before it was
		# ever cast. A body with no legal move should take a bad move over no move.
		#
		# One retry, and only on a tick that has already failed -- so the whole cost lands on
		# ticks that used to end in a stall.
		var escaped: String = last_refusal
		_score_fan(
			body, heading, normal, to_goal, reading, probe, config, profile.crawl_escape_arc_degrees
		)
		chosen = _best_validated(body, probe, config, profile.crawl_candidate_count, false)
		if chosen == null:
			last_refusal = "%s; escape fan also refused (%s)" % [escaped, last_refusal]
			return null

	var limited: Vector3 = turn_limited(heading, chosen.direction, body.speed(), delta, profile)
	var command := NavMotionCommand.make(
		NavLocomotion.Mode.SURFACE_CRAWL,
		limited,
		profile.crawl_max_speed * cornering_speed(limited, chosen.direction, profile),
		body.position
	)
	command.preferred_surface_normal = normal
	command.preferred_up = normal
	command.clearance = reading.nearest_distance()
	var target := _basis_from(limited, normal)
	var slewed: Basis = slew(body.forward, body.up, target, profile.orientation_slew_rate * delta)
	command.preferred_forward = -slewed.z
	command.preferred_up = slewed.y
	return command


# ----- internals -----


## Builds and scores the whole fan. One probe ray per candidate, which with the default
## nine directions is the crawler's per-tick cost.
##
## ADHESION IS BAKED INTO THE STEP POINT, NOT BLENDED INTO THE EMITTED DIRECTION, and the
## difference is a freeze. Everything downstream -- the surface ray, the swept cast, the
## command -- is derived from `step`, so pulling the body toward its surface here means the
## motion that gets validated is the motion that gets executed. Correcting the direction
## after `_best_validated` has approved a different one is how a body ends up moving
## somewhere no cast ever cleared.
func _score_fan(
	body: NavBodyState,
	heading: Vector3,
	normal: Vector3,
	to_goal: Vector3,
	reading: NavSurfaceReading,
	probe: NavigationProbe,
	config: NavigationConfig,
	arc_degrees: float
) -> void:
	last_candidates = []
	var profile: LocomotionProfile = config.locomotion_profile
	var limit: float = LocomotionProfile.max_turn_angle(
		body.speed(), 1.0, profile.crawl_turn_radius
	)
	var arc: float = deg_to_rad(arc_degrees)
	var count: int = maxi(profile.crawl_candidate_count, 1)
	var pull: Vector3 = NavAvoidance.adhesion(
		reading,
		profile.crawl_hold_distance,
		profile.crawl_adhesion_gain,
		profile.crawl_step_distance
	)
	for index: int in count:
		var offset: float = 0.0
		if count > 1:
			offset = arc * (float(index) / float(count - 1) - 0.5)
		var along: Vector3 = heading.rotated(normal.normalized(), offset).normalized()
		var step: Vector3 = body.position + along * profile.crawl_step_distance + pull
		var direction: Vector3 = step - body.position
		if direction.is_zero_approx():
			continue
		direction = direction.normalized()
		# Look back INTO the surface from the step point. A direction that leaves nothing
		# to hold on to is section 8.2's case, and it has to lose on quality rather than
		# be quietly dropped, so the overlay can show why the alien did not go that way.
		var under: NavSurfaceSample = probe.surface_along(
			step, -normal, profile.crawl_surface_reach, config.world_mask
		)
		var candidate := NavCrawlCandidate.make(direction, step, under)
		candidate.goal_alignment = goal_alignment(direction, to_goal)
		candidate.surface_quality = surface_quality(under, profile.crawl_surface_reach)
		candidate.clearance_score = clearance_score(
			reading.nearest_distance(), config.comfortable_clearance
		)
		candidate.orientation_continuity = orientation_continuity(direction, body.forward)
		candidate.turning_penalty = turning_penalty(direction, heading, limit)
		# SECTION 21'S SIXTH TERM, WHICH UNTIL NOW DID NOTHING. It was set to 1.0 further
		# down, after a swept cast had already failed -- which is after scoring is over, so
		# it never influenced the choice and existed only for the overlay. Scored here from
		# the body fan's own rays it costs nothing and does the job the spec gave it:
		# discouraging a direction BEFORE the cast, rather than explaining the cast after.
		candidate.collision_penalty = NavAvoidance.risk(direction, reading, profile.avoid_margin)
		candidate.score = score(candidate, profile)
		last_candidates.append(candidate)


## Takes the ranked fan and pays for a swept cast on each until one clears.
## Scoring is rays and casting is not, so ordinarily only the plausible few are proven.
##
## `casts` bounds how many are paid for and `enforce_minimum` decides whether
## `crawl_minimum_score` may end the search early. The ordinary pass keeps both tight; the
## escape pass relaxes both, because it only runs on a tick that would otherwise be a stall
## and there is nothing cheaper left to try.
func _best_validated(
	body: NavBodyState,
	probe: NavigationProbe,
	config: NavigationConfig,
	casts: int,
	enforce_minimum: bool
) -> NavCrawlCandidate:
	var profile: LocomotionProfile = config.locomotion_profile
	var ranked: Array[NavCrawlCandidate] = last_candidates.duplicate()
	ranked.sort_custom(
		func(a: NavCrawlCandidate, b: NavCrawlCandidate) -> bool: return a.score > b.score
	)
	var shape: Shape3D = config.clearance_profile.normal_body()
	if body.squeezed:
		shape = config.clearance_profile.squeezed_body()
	var budget: int = mini(casts, ranked.size())
	var scored_out: int = 0
	var unsupported: int = 0
	var blocked: int = 0
	for index: int in budget:
		var candidate: NavCrawlCandidate = ranked[index]
		if enforce_minimum and candidate.score < profile.crawl_minimum_score:
			scored_out += 1
			break
		if not candidate.surface.hit:
			unsupported += 1
			continue
		if probe.shape_sweep_clear(shape, body.position, candidate.step_point, config.world_mask):
			candidate.validated = true
			return candidate
		blocked += 1
		# Charged rather than discarded, so the overlay shows a rejected candidate with a
		# collision penalty rather than a candidate that silently vanished.
		candidate.collision_penalty = 1.0
		candidate.score = score(candidate, profile)
	last_refusal = (
		"%d of %d shortlisted blocked, %d had no surface ahead, %d scored too low"
		% [blocked, budget, unsupported, scored_out]
	)
	return null


## Component of `vector` lying in the plane whose normal is `normal`.
static func _project(vector: Vector3, normal: Vector3) -> Vector3:
	if normal.is_zero_approx():
		return vector
	var unit: Vector3 = normal.normalized()
	return vector - unit * vector.dot(unit)


## An orthonormal basis facing `forward` with `normal` as up. -Z is forward, matching
## Vector3.FORWARD and this project's facing convention.
static func _basis_from(forward: Vector3, normal: Vector3) -> Basis:
	var up: Vector3 = normal.normalized()
	var ahead: Vector3 = _project(forward, up)
	if ahead.is_zero_approx():
		return Basis.IDENTITY
	ahead = ahead.normalized()
	return Basis(up.cross(ahead), up, -ahead)


static func _rotate_toward(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	if from.is_zero_approx():
		return to.normalized()
	if to.is_zero_approx():
		return from.normalized()
	var start: Vector3 = from.normalized()
	var goal: Vector3 = to.normalized()
	var turn: float = start.angle_to(goal)
	if turn <= max_radians or turn <= 0.0:
		return goal
	var axis: Vector3 = start.cross(goal)
	if axis.is_zero_approx():
		return goal
	return start.rotated(axis.normalized(), max_radians)
