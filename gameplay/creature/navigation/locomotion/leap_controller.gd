class_name LeapController
extends RefCounted

## Executes a leap once one has been chosen (navigation.md section 11, Invariant 4).
##
## INVARIANT 4 IS ENFORCED BY STRUCTURE, NOT BY DISCIPLINE. "Once a leap begins, its
## trajectory cannot be redirected." So the velocity is computed once, at launch, stored,
## and re-emitted every airborne tick -- and `advance` does not consult the body, the goal
## or the route while AIRBORNE. There is no steering input to forget to ignore. A test
## moves the goal mid-flight and asserts the emitted velocity is unchanged.
##
## SECTION 40.5 IS THE OPPOSITE HALF: while PREPARING, the flight is re-validated every
## tick and the leap is abandoned if it stops being clear. That window is the only chance
## -- a wind-up is a moment in which the player can mine the wall the alien was about to
## sail past, and once airborne there is no correction available at any price.
##
## THE OPPORTUNISTIC GRAB BELONGS HERE, NOT IN PATHFINDING (section 11.5). It is not a
## change of trajectory -- the alien cannot make one -- it is a decision to stop early on
## a trajectory it is already committed to, which is a thing a body can do and a route
## cannot express.

enum Phase {
	IDLE,
	## Section 11.2.1's launch preparation, and section 40.5's abort window.
	PREPARING,
	## Section 11.1's straight line. Nothing may alter the velocity from here.
	AIRBORNE,
}

var _phase: Phase = Phase.IDLE
var _candidate: NavLeapCandidate = null
## Fixed at launch. THE reason Invariant 4 holds.
var _velocity: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0


## Starts a wind-up. Does not launch: section 11.2.1 wants a valid launch pose held for
## `leap_preparation_time` first, which is also section 40.5's chance to change its mind.
func begin(candidate: NavLeapCandidate) -> void:
	_candidate = candidate
	_phase = Phase.PREPARING
	_elapsed = 0.0
	_velocity = Vector3.ZERO


## Drops the leap. Legal while PREPARING and a bug while AIRBORNE, so it says so.
func abort() -> void:
	if _phase == Phase.AIRBORNE:
		push_error("LeapController.abort() while airborne; Invariant 4 forbids redirection")
		return
	_phase = Phase.IDLE
	_candidate = null
	_elapsed = 0.0


func is_airborne() -> bool:
	return _phase == Phase.AIRBORNE


func is_busy() -> bool:
	return _phase != Phase.IDLE


func phase() -> Phase:
	return _phase


func candidate() -> NavLeapCandidate:
	return _candidate


func debug_state() -> Dictionary:
	return {
		"phase": phase_name(_phase),
		"elapsed": _elapsed,
		"velocity": _velocity,
		"candidate": _candidate.to_dictionary() if _candidate != null else {},
	}


static func phase_name(value: Phase) -> String:
	match value:
		Phase.IDLE:
			return "idle"
		Phase.PREPARING:
			return "preparing"
		Phase.AIRBORNE:
			return "airborne"
	return "unknown"


## One tick of a leap. Null when there is no leap in progress.
func advance(
	body: NavBodyState, delta: float, probe: NavigationProbe, config: NavigationConfig
) -> NavMotionCommand:
	if _phase == Phase.IDLE or _candidate == null:
		return null
	if _phase == Phase.PREPARING:
		return _wind_up(body, delta, probe, config)
	return _fly(body, config)


## Section 11.5, Scenario I. A grabbable surface within reach of the flight, that is
## actually worth taking.
##
## "USEFUL" IS PART OF THE SPEC'S WORDING AND IT DOES THE WORK. A wall the alien is
## skimming is always grabbable, and grabbing every one turns a 20 m leap into a 3 m hop.
##
## USEFUL MEANS CLOSER TO THE GOAL THAN THE PLANNED LANDING IS -- not closer than the body
## is right now. The obvious form of that test compares against the body's own position,
## and it can essentially never fire: a grab surface beside the flight path is by
## definition off to one side, so with the goal straight ahead every candidate is very
## slightly FURTHER than carrying on. Comparing against the destination instead asks the
## question section 11.5 is actually about -- has something better than where I was going
## come within reach?
func opportunistic_grab(
	body: NavBodyState, goal: Vector3, probe: NavigationProbe, config: NavigationConfig
) -> NavSurfaceSample:
	var profile: LocomotionProfile = config.locomotion_profile
	if not is_airborne() or _candidate == null or profile.leap_grab_ray_count <= 0:
		return null
	var planned: float = _candidate.landing_point.distance_to(goal)
	var best: NavSurfaceSample = null
	for heading: Vector3 in _grab_headings(_velocity, profile.leap_grab_ray_count):
		var found: NavSurfaceSample = probe.surface_along(
			body.position, heading, profile.leap_grab_reach, config.world_mask
		)
		if not found.hit:
			continue
		if found.point.distance_to(goal) >= planned:
			continue
		if best == null or found.distance < best.distance:
			best = found
	return best


# ----- internals -----


func _wind_up(
	body: NavBodyState, delta: float, probe: NavigationProbe, config: NavigationConfig
) -> NavMotionCommand:
	var profile: LocomotionProfile = config.locomotion_profile
	# Section 40.5, every tick of the wind-up. The world is allowed to change underneath a
	# leap that has not left the ground, and the alien is allowed to notice.
	var clear: bool = probe.shape_sweep_clear(
		config.clearance_profile.normal_body(),
		body.position,
		_candidate.landing_point,
		config.world_mask
	)
	if not clear:
		_candidate.reject(NavLeapCandidate.Rejection.BLOCKED_FLIGHT)
		abort()
		return NavMotionCommand.stalled(
			NavLocomotion.Mode.LEAP, NavMotionCommand.Abort.LEAP_INVALIDATED
		)

	_elapsed += delta
	if _elapsed >= profile.leap_preparation_time:
		_velocity = _candidate.velocity_at(profile.leap_speed)
		_phase = Phase.AIRBORNE
		_elapsed = 0.0

	var command := NavMotionCommand.make(
		NavLocomotion.Mode.LEAP, _candidate.direction, 0.0, body.position
	)
	command.preparing_leap = _phase == Phase.PREPARING
	command.leap_velocity = _velocity
	command.preferred_forward = _candidate.direction
	return command


## Airborne. NOTHING HERE READS THE GOAL OR THE ROUTE -- see the class docstring.
func _fly(body: NavBodyState, config: NavigationConfig) -> NavMotionCommand:
	var profile: LocomotionProfile = config.locomotion_profile
	var command := NavMotionCommand.make(
		NavLocomotion.Mode.LEAP, _candidate.direction, profile.leap_speed, body.position
	)
	command.leap_velocity = _velocity
	command.preferred_forward = _candidate.direction
	if body.position.distance_to(_candidate.landing_point) <= profile.leap_arrival_distance:
		# Arrived. The facade forces a replan, because a body 20 m along its own route has
		# a follower index that means nothing any more -- and section 18 forbids fixing
		# that by re-picking the nearest anchor.
		_phase = Phase.IDLE
	return command


## Called by the planner when a grab is taken mid-flight. Ends the leap where the body is
## rather than where it was going.
func land_early() -> void:
	_phase = Phase.IDLE


## Directions to look for a grab: around the flight axis, not along it. A surface dead
## ahead is the destination, and one dead behind has already been passed.
static func _grab_headings(velocity: Vector3, count: int) -> Array[Vector3]:
	var headings: Array[Vector3] = []
	if velocity.is_zero_approx() or count <= 0:
		return headings
	var forward: Vector3 = velocity.normalized()
	var side: Vector3 = forward.cross(Vector3.UP)
	if side.is_zero_approx():
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	for index: int in count:
		headings.append(side.rotated(forward, TAU * float(index) / float(count)))
	return headings
