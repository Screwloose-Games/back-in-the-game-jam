class_name TunnelSwimController
extends RefCounted

## Moves the body down the middle of an enclosed space (navigation.md section 9).
##
## THE MODE EXISTS BECAUSE A CRAWLER IN A TUNNEL LOOKS WRONG. Section 9.1 draws the
## picture: surrounded on all sides, the alien should travel along the axis rather than
## pick a wall and hug it. A surface crawler in a 4 m pipe is not broken -- it reaches the
## far end -- it just spends the whole trip pressed against one side for no reason a
## player can read.
##
## CONFINEMENT IS MEASURED, NOT FLAGGED (section 9.3). There is no tunnel volume, no
## marker, no authored hint anywhere in this module; there is a fan of rays and a
## fraction. That is what lets a passage the player mined five seconds ago be swum down
## without anything being told about it.
##
## THE TWO THRESHOLDS ARE THE HYSTERESIS, AND THEY ARE NOT OPTIONAL. At a tunnel mouth the
## enclosure reading crosses any single threshold several times a second as the body
## moves, and a mode that follows it flickers between crawl and swim every frame. Even two
## thresholds are not quite enough -- `NavLocalPlanner` adds a dwell timer on top, because
## a reading can straddle one of the two.


## Where to head: forward progress, plus a push toward the middle (section 9.2).
##
## SECTION 9.2 IS EXPLICIT THAT NEITHER TERM WINS OUTRIGHT -- the local objective is "high
## local clearance PLUS forward progress", not one and then the other. Dropping the medial
## term gives a crawler that has stopped touching anything; dropping the progress term
## gives an alien that centres itself perfectly and never arrives.
##
## `strength` scales the section 21 avoidance correction, so a caller refused by the swept
## cast can ask again more firmly rather than giving up on the mode.
static func desired_direction(
	toward: Vector3, reading: NavSurfaceReading, profile: LocomotionProfile, strength: float = 1.0
) -> Vector3:
	var progress: Vector3 = toward
	if not progress.is_zero_approx():
		progress = progress.normalized()
	var blended: Vector3 = (
		progress + reading.medial * profile.tunnel_centering_weight + exit_pull(reading, profile)
	)
	if blended.is_zero_approx():
		# Perfectly opposed, which means the only way on is the way the walls are pushing
		# back from. Progress wins: centring is a preference, arriving is the job.
		return progress
	# MEDIAL CENTRES; THIS DECLINES TO DRIVE INTO A WALL, AND THEY ARE NOT THE SAME THING.
	# `medial` is direction-agnostic -- it pushes away from every nearby surface equally and
	# has no opinion whatever about the one the body is actually angling at. In a straight
	# bore the two agree and it never showed; at a bend the swimmer stayed beautifully
	# centred while driving its shoulder into the outside wall, and the only recovery was
	# the swept cast refusing the tick.
	return NavAvoidance.steer_clear(blended.normalized(), reading, profile.avoid_margin, strength)


## Section 8.1's adhesion, but only while leaving.
##
## CENTRE WHILE ENCLOSED, REACH FOR A WALL WHILE LEAVING. Adhesion and centring are
## directly opposed, and deep in a tunnel centring is the entire point of the mode -- so
## this is zero there and rises only as the body's enclosure falls toward the crawl
## handover. Without it the swimmer delivers the body to surface crawl in mid-air: at the
## demo cave's swim-tunnel mouth the medial term lifts the body to the middle of a 6 m bore
## and then hands it to a crawler standing in a room whose floor is 5 m below and ceiling 5
## m above, which is outside tentacle reach in every direction. That is the exact pose the
## creature was found frozen in.
static func exit_pull(reading: NavSurfaceReading, profile: LocomotionProfile) -> Vector3:
	if profile.tunnel_enter_enclosure <= 0.0:
		return Vector3.ZERO
	var leaving: float = clampf(1.0 - reading.enclosure / profile.tunnel_enter_enclosure, 0.0, 1.0)
	if leaving <= 0.0:
		return Vector3.ZERO
	var pull: Vector3 = NavAvoidance.adhesion(
		reading, profile.crawl_hold_distance, profile.crawl_adhesion_gain, 1.0
	)
	return pull * leaving


## Section 9.3. Which of crawl and swim this reading argues for, given the mode already
## held -- so the answer depends on history, which is what makes it hysteresis rather
## than a threshold.
static func mode_for(
	reading: NavSurfaceReading, current: NavLocomotion.Mode, profile: LocomotionProfile
) -> NavLocomotion.Mode:
	if current == NavLocomotion.Mode.TUNNEL_SWIM:
		if reading.enclosure <= profile.tunnel_exit_enclosure:
			return NavLocomotion.Mode.SURFACE_CRAWL
		return NavLocomotion.Mode.TUNNEL_SWIM
	if reading.enclosure >= profile.tunnel_enter_enclosure:
		return NavLocomotion.Mode.TUNNEL_SWIM
	return NavLocomotion.Mode.SURFACE_CRAWL


## The impure entry point. Null when every avoidance strength is blocked, which hands the
## decision back to the planner rather than guessing.
##
## THE MODE WITH NO ALTERNATIVES NOW GETS THREE. This used to compose one direction, cast
## it once, and return null on a refusal -- and the comment said that was fine because
## `medial` already was the avoidance behaviour. It was not: centring is direction-agnostic,
## so a swimmer angling at a bend was refused by the cast with nothing else to offer, and
## the tick fell through to a crawler that in a tunnel mouth may have no surface at all.
## Each retry pushes `steer_clear` harder, so the attempts are genuinely different
## directions rather than the same one asked again.
func steer(
	body: NavBodyState,
	toward: Vector3,
	reading: NavSurfaceReading,
	_delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	var profile: LocomotionProfile = config.locomotion_profile
	var shape: Shape3D = config.clearance_profile.normal_body()
	if body.squeezed:
		shape = config.clearance_profile.squeezed_body()

	var direction := Vector3.ZERO
	var cleared: bool = false
	for attempt: int in maxi(profile.tunnel_avoid_attempts, 1):
		direction = desired_direction(
			toward - body.position, reading, profile, 1.0 + float(attempt)
		)
		if direction.is_zero_approx():
			return null
		var step: Vector3 = body.position + direction * profile.crawl_step_distance
		if probe.shape_sweep_clear(shape, body.position, step, config.world_mask):
			cleared = true
			break
	if not cleared:
		return null

	var command := NavMotionCommand.make(
		NavLocomotion.Mode.TUNNEL_SWIM, direction, profile.tunnel_max_speed, body.position
	)
	command.preferred_surface_normal = reading.dominant_normal
	command.clearance = reading.nearest_distance()
	# Facing follows travel, and up follows the tunnel rather than the nearest wall: an
	# unsupported body has no surface to be oriented by, which is the whole difference
	# between this mode and surface crawl.
	command.preferred_forward = direction
	command.preferred_up = _up_across(direction, body.up)
	return command


## An up vector perpendicular to travel, drifted from the body's current one rather than
## rebuilt, so a swimmer does not spin about its own axis while going straight.
static func _up_across(direction: Vector3, current_up: Vector3) -> Vector3:
	var across: Vector3 = current_up - direction * current_up.dot(direction)
	if across.is_zero_approx():
		across = direction.cross(Vector3.UP)
	if across.is_zero_approx():
		across = direction.cross(Vector3.RIGHT)
	return across.normalized()
