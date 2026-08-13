class_name NavLocalPlanner
extends RefCounted

## Decides how the body executes the next piece of the route (navigation.md section 20).
##
## THE HALF OF THE SYSTEM THE GRAPH DELIBERATELY DOES NOT DO. Sections 2.2 and 2.3 split
## routing from locomotion: A* answers "what is connected", and this answers "so what does
## the body do this frame". Section 13.3 puts the crawl-versus-swim choice here rather
## than in the edge type for exactly that reason -- a NORMAL_VOLUME edge is a claim about
## clearance, not an instruction about posture.
##
## IT CONSUMES `current_anchor()` AS A DIRECTION, NOT A WAYPOINT (section 2.2, Invariant
## 1). Decimation keeps the MOST OPEN candidate in each neighbourhood, so in a chamber the
## anchor sits near the middle of empty space while the alien would sensibly crawl a wall
## six metres away. Steering to arrive at anchors produces an alien that visits the centre
## of every room on its way through.
##
## MODE SELECTION IS ORDERED AND DETERMINISTIC, and the order is the design. Later phases
## insert branches above the ones here -- airborne first (Invariant 4 forbids
## reconsidering a leap), then squeeze, then leap, then enclosure -- so a mode that must
## not be interrupted is checked before any mode that could interrupt it.
##
## THE DWELL TIMER IS NOT BELT AND BRACES. Section 9.3's two enclosure thresholds stop the
## mode following a reading that crosses ONE of them; they do nothing when the reading
## straddles a threshold, which is what happens at every tunnel mouth as the body moves.
## Without a minimum residence the alien changes posture several times a second while
## making perfectly good progress.

var surface: NavSurfaceField = null
var crawler: SurfaceCrawlController = null
var swimmer: TunnelSwimController = null
var wiggler: WiggleController = null
var leaper: NavLeapPlanner = null
var flight: LeapController = null

var _mode: NavLocomotion.Mode = NavLocomotion.Mode.SURFACE_CRAWL
## Seconds in the current mode. Starts at INF so the very first tick may choose freely --
## otherwise the alien spends `mode_dwell_time` crawling down a tunnel it started inside.
var _dwell: float = INF
var _reading: NavSurfaceReading = null
## Set on the tick a leap ends. Section 31 lists "locomotion transition requires
## reconsideration" as a replan trigger, and a body 20 m along its own route is the
## clearest case there is -- the follower's monotonic index now refers to a journey that
## did not happen. Replanning resets it legitimately; re-picking the nearest anchor, which
## is the other way to fix it, is what sections 18 and 40.1 forbid.
var _landed: bool = false


func _init() -> void:
	# Built here rather than injected, so a planner created with .new() is usable. The
	# fields stay public because a test that wants a scripted crawler can still swap one.
	surface = NavSurfaceField.new()
	crawler = SurfaceCrawlController.new()
	swimmer = TunnelSwimController.new()
	wiggler = WiggleController.new()
	leaper = NavLeapPlanner.new()
	flight = LeapController.new()


## Section 20's entry point. Never returns null: a tick with nothing to do is a stall,
## which carries a reason the behaviour layer can act on.
func plan_next_motion(
	body: NavBodyState,
	follower: RouteFollower,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	_dwell += delta
	_landed = false

	# AIRBORNE IS CHECKED BEFORE ANYTHING ELSE, AND BEFORE THE SURFACE FAN IS EVEN TAKEN.
	# Invariant 4 forbids redirecting a leap, so a tick that could reconsider one is a tick
	# that could break it. Sampling geometry first would also spend ten rays per frame of
	# flight on a reading nothing airborne is allowed to act on.
	if flight.is_airborne():
		return _plan_airborne(body, follower, delta, probe, config)

	_reading = surface.sample(body.position, probe, config.locomotion_profile, config.world_mask)
	var toward: Vector3 = body.position
	if follower != null and follower.has_route():
		toward = follower.current_anchor()
	if flight.is_busy():
		return _continue_wind_up(body, delta, probe, config)
	return _plan_supported(body, follower, toward, delta, probe, config)


## Invariant 3, as a predicate: the ONLY legal unsupported state is airborne.
##
## Section 11 is where an alien is allowed to be in open space, and it is the only place.
## Anything else with nothing within tentacle reach is a body that has slipped -- off a
## ceiling it was holding, out of a tunnel mouth it was leaving, or simply on velocity that
## outlasted the steer that made it -- and what follows is an escape, not a mode.
##
## WRITTEN ONCE SO IT CANNOT DRIFT. The distinction between escaping an illegal pose and
## travelling through open space is the whole of Invariant 3, and it is exactly the kind of
## thing that gets softened by a later refactor into "well, we move while unsupported
## anyway". `test_only_airborne_may_be_unsupported` asserts this function, so softening it
## fails the suite by name.
static func is_slipped(reading: NavSurfaceReading, airborne: bool) -> bool:
	if airborne or reading == null:
		return false
	return not reading.has_surface()


func mode() -> NavLocomotion.Mode:
	return _mode


## Whether a leap finished on this tick. Read by the facade as a section 31 replan trigger.
func has_landed() -> bool:
	return _landed


func is_airborne() -> bool:
	return flight.is_airborne()


## The fan taken this tick, for the section 39 overlay and for the facade's body state.
func last_reading() -> NavSurfaceReading:
	return _reading


## Forces the next tick to reconsider the mode regardless of dwell. Used when something
## outside locomotion has changed the situation enough that continuity is not a virtue --
## a replan, a fresh route, a body that has just been put somewhere else.
func reset_mode() -> void:
	_mode = NavLocomotion.Mode.SURFACE_CRAWL
	_dwell = INF


func debug_state() -> Dictionary:
	return {
		"mode": NavLocomotion.mode_name(_mode),
		"dwell": _dwell,
		"landed": _landed,
		"reading": _reading.to_dictionary() if _reading != null else {},
		"flight": flight.debug_state(),
		"wiggle": wiggler.debug_state(),
	}


# ----- internals -----


## Wiggle, then crawl and swim. Leap is inserted ahead of all three in phase 6.
##
## WIGGLE IS CHECKED FIRST AND BYPASSES THE DWELL TIMER, because it is not a preference.
## Crawl and swim are two reasonable ways to cross the same space and the timer stops the
## alien dithering between them; a body that does not fit is not dithering, and making it
## wait out a dwell period before compressing would have it press into a crevice it cannot
## enter for a third of a second, every time.
func _plan_supported(
	body: NavBodyState,
	follower: RouteFollower,
	toward: Vector3,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	var squeezed: NavMotionCommand = wiggler.steer(body, toward, delta, probe, config)
	if squeezed != null:
		_enter(NavLocomotion.Mode.WIGGLE)
		return squeezed
	# Section 11.4, checked after the squeeze and before the walk: an alien wedged in a
	# crevice has no launch pose, and one that could crawl there might still be quicker
	# through the air.
	var jump: NavLeapCandidate = leaper.best_leap(body, follower, _reading, probe, config)
	if jump != null:
		flight.begin(jump)
		_enter(NavLocomotion.Mode.LEAP)
		return _continue_wind_up(body, delta, probe, config)
	if _mode == NavLocomotion.Mode.WIGGLE:
		# Decompressed and out. Leaving is physical too, so it does not wait either.
		_enter(
			TunnelSwimController.mode_for(
				_reading, NavLocomotion.Mode.SURFACE_CRAWL, config.locomotion_profile
			)
		)
	_select_mode(config.locomotion_profile)
	return _travel(body, toward, delta, probe, config)


## Swim, crawl, swim again, recover, stall -- and the second swim is the interesting one.
##
## SECTION 8.2 SAYS A CRAWLER THAT RUNS OUT OF SURFACE MUST CONSIDER SOMETHING ELSE, and
## until now the only something else was a leap. At the mouth of a passage that is exactly
## wrong: the alien is holding the wall beside the bore, every step along that wall puts its
## step point in front of the opening where there is nothing within tentacle reach, and the
## honest answer is not to jump but to swim in.
##
## Section 9.3's enclosure thresholds cannot select that on their own, and the demo cave
## shows why in one number. `tunnel_enclosure_reach` is 3 m and the swim tunnel's bore is
## 6 m, so a body on the axis measures its walls at exactly the reach limit: 0.50 enclosure
## well inside the tunnel and 0.20 at the mouth, against an enter threshold of 0.60. The
## body was found stalled at (17, 7, 9) -- one metre too high to fit the bore, holding the
## rock above it, with a COMPLETE route two metres from an anchor inside the tunnel.
##
## THIS IS NOT A NEW LICENCE TO CROSS OPEN SPACE. It is the existing mode used one step
## before its threshold would have chosen it, and `TunnelSwimController` validates every
## step with a swept cast exactly as before -- so Invariant 3 is no weaker than it was when
## the same controller ran two metres further in.
func _travel(
	body: NavBodyState,
	toward: Vector3,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	var swimming: bool = _mode == NavLocomotion.Mode.TUNNEL_SWIM
	if swimming:
		var swum: NavMotionCommand = swimmer.steer(body, toward, _reading, delta, probe, config)
		if swum != null:
			return swum
	# Crawl is the fallback as well as a mode in its own right: it is the only controller
	# that scores alternatives, so it is the one with something to say when the obvious
	# heading is blocked.
	var crawled: NavMotionCommand = crawler.steer(body, toward, _reading, delta, probe, config)
	if crawled != null:
		return crawled
	if not swimming:
		var out: NavMotionCommand = swimmer.steer(body, toward, _reading, delta, probe, config)
		if out != null:
			_enter(NavLocomotion.Mode.TUNNEL_SWIM)
			return out
	var freed: NavMotionCommand = _recover(body, probe, config)
	if freed != null:
		return freed
	# Section 8.2 with nothing left at all. The facade turns this into a section 30
	# inspection request rather than letting the alien press on into open space.
	#
	# THE TWO REASONS ARE DIFFERENT SITUATIONS AND USED TO SHARE A NAME. "Nothing to hold"
	# is a claim about the cave; "held, and boxed in" is a claim about this pose. Reporting
	# the second as the first sent the facade to raise a GEOMETRY_MISMATCH about a wall the
	# alien could see and was merely wedged against, and put `no_surface` on screen with the
	# HUD reporting a surface 1.6 m away two lines below.
	var why: NavMotionCommand.Abort = NavMotionCommand.Abort.NO_SURFACE
	if _reading.has_surface():
		why = NavMotionCommand.Abort.BLOCKED
	return NavMotionCommand.stalled(_mode, why)


## Escapes a pose the body should not be in. Null when it is in a legal one.
##
## THE TWO WAYS TO BE SOMEWHERE NO MODE CAN PLAN FROM ARE TOO CLOSE AND TOO FAR, and both
## are terminal without this. Neither is traversal, so neither touches Invariant 3: the
## alien is not moving THROUGH anywhere, it is getting back to somewhere it is allowed to
## be. That distinction is load-bearing and `is_slipped` is where it is written down.
func _recover(
	body: NavBodyState, probe: NavigationProbe, config: NavigationConfig
) -> NavMotionCommand:
	if _reading == null:
		return null
	if is_slipped(_reading, flight.is_airborne()):
		return _reacquire(body, probe, config)
	if not _reading.has_surface():
		return null
	if _reading.nearest_distance() >= config.clearance_profile.normal_clearance():
		return null
	return _back_off(body, config)


## Too close. Backs the body out of a pose no cast can be made from.
##
## EVERY MODE ABOVE VALIDATES ITS STEP WITH A SWEPT CAST, AND EVERY SWEPT CAST BEGINS WITH
## AN ORIGIN OVERLAP TEST. So a body closer to terrain than its own planning envelope has
## no legal move in any direction: crawl rejects all nine candidates, swim rejects its one,
## and the alien stalls -- forever, because stalling does not move it out of the pose that
## caused the stall. It only takes one frame of physics resolving a contact slightly
## tighter than navigation plans for, and the alien is finished for the rest of the run.
##
## Observed in the demo prototype, whose collider was a hair smaller than
## `normal_clearance()`: the creature parked 1.20 m from a ceiling planned against at
## 1.25 m and never moved again, holding a COMPLETE route the whole time.
##
## THIS ONE IS DELIBERATELY NOT VALIDATED, and it is the only unswept motion in the module.
## There is nothing to validate with -- that is the situation. It is safe because it moves
## directly AWAY from the nearest surfaces, which is the one direction that cannot make the
## overlap worse, and `NavSurfaceReading.medial` is exactly that vector and has already
## been paid for.
func _back_off(body: NavBodyState, config: NavigationConfig) -> NavMotionCommand:
	var away: Vector3 = _reading.medial
	if away.is_zero_approx():
		away = _reading.dominant_normal
	if away.is_zero_approx():
		return null
	# At wiggle speed. This is a body working itself free of a wall, not a body travelling,
	# and `wiggle_speed` is already the module's number for "moving carefully".
	var command := NavMotionCommand.make(_mode, away, config.wiggle_speed, body.position)
	command.preferred_surface_normal = _reading.dominant_normal
	command.clearance = _reading.nearest_distance()
	command.recovering = true
	return command


## Too far. Finds the nearest surface at any distance and goes back to it.
##
## THE OTHER TERMINAL POSE, AND THE ONE THAT ACTUALLY SHIPPED. With nothing inside
## `crawl_surface_reach` the crawler refuses on its first line, the planner stalls
## NO_SURFACE, a stall is zero speed, and zero speed cannot move the body out of the pose
## that caused the stall. Found in the demo cave at (15.9, 5.4, 6.6): floating mid-room,
## 1.9 m from its next anchor, holding a COMPLETE route, with all ten rays missing -- the
## nearest rock 4.6 m away and the fan reaching 3.5.
##
## VALIDATED, UNLIKE `_back_off`, AND THERE IS NO EXCUSE FOR IT NOT TO BE. That one cannot
## cast because the body overlaps something at the origin; this one is in open space, where
## casts work perfectly. An unvalidated lunge at a distant surface is how a recovery becomes
## the next bug.
##
## Wiggle speed for the same reason: this is a body picking its way back to contact, not a
## body travelling, and section 10.2's number is already the module's word for careful.
func _reacquire(
	body: NavBodyState, probe: NavigationProbe, config: NavigationConfig
) -> NavMotionCommand:
	var profile: LocomotionProfile = config.locomotion_profile
	var found: NavSurfaceSample = surface.reacquire(
		body.position, probe, profile, config.world_mask
	)
	if found == null:
		# Genuinely unbounded space, which in a cave means the bake region has been left
		# entirely. There is no surface to go back to and nothing useful to invent.
		return null
	var step: Vector3 = body.position + found.direction * profile.crawl_step_distance
	var shape: Shape3D = config.clearance_profile.normal_body()
	if body.squeezed:
		shape = config.clearance_profile.squeezed_body()
	if not probe.shape_sweep_clear(shape, body.position, step, config.world_mask):
		return null
	var command := NavMotionCommand.make(_mode, found.direction, config.wiggle_speed, body.position)
	command.preferred_surface_normal = found.normal
	command.preferred_up = found.normal
	command.clearance = found.distance
	command.recovering = true
	return command


## In flight. The only branch that does not sample geometry, and the only one that hands
## the tick straight to a controller without a decision of its own -- which is Invariant 4
## written as control flow rather than as a comment.
##
## Section 11.5's opportunistic grab is the one thing that may end a flight early, and it
## is not a redirection: the trajectory is unchanged, the alien simply stops sooner along
## it because something useful came within reach.
func _plan_airborne(
	body: NavBodyState,
	follower: RouteFollower,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	var command: NavMotionCommand = flight.advance(body, delta, probe, config)
	var goal: Vector3 = body.position
	if follower != null and follower.has_route():
		goal = follower.route.target_position
	var grab: NavSurfaceSample = flight.opportunistic_grab(body, goal, probe, config)
	if grab != null:
		flight.land_early()
	if not flight.is_airborne():
		# Landed, by arrival or by grab. The follower's index refers to a route the body
		# is now somewhere else along, and section 18 forbids fixing that by re-picking the
		# nearest anchor -- so the facade replans instead.
		_landed = true
		_enter(NavLocomotion.Mode.SURFACE_CRAWL)
	return command


## A wind-up tick. Section 40.5 may abandon the leap from in here, in which case the mode
## falls back and the next tick plans from scratch.
func _continue_wind_up(
	body: NavBodyState, delta: float, probe: NavigationProbe, config: NavigationConfig
) -> NavMotionCommand:
	var command: NavMotionCommand = flight.advance(body, delta, probe, config)
	if command == null:
		_enter(NavLocomotion.Mode.SURFACE_CRAWL)
		return NavMotionCommand.stalled(_mode, NavMotionCommand.Abort.LEAP_INVALIDATED)
	if command.abort == NavMotionCommand.Abort.LEAP_INVALIDATED:
		_enter(NavLocomotion.Mode.SURFACE_CRAWL)
	return command


func _select_mode(profile: LocomotionProfile) -> void:
	var wanted: NavLocomotion.Mode = TunnelSwimController.mode_for(_reading, _mode, profile)
	if wanted == _mode:
		return
	if _dwell < profile.mode_dwell_time:
		return
	_enter(wanted)


## Change mode and restart the dwell clock. Used for the transitions that are not subject
## to it as well, so there is one place the clock is touched.
func _enter(next: NavLocomotion.Mode) -> void:
	if next == _mode:
		return
	_mode = next
	_dwell = 0.0
