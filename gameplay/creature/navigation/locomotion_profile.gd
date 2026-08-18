class_name LocomotionProfile
extends Resource

## Every number the four locomotion modes steer by (navigation.md sections 8-11, 21-23).
##
## SPLIT OUT OF NavigationConfig RATHER THAN ADDED TO IT, for the reason ClearanceProfile
## was: the config is already the one place a navigation number may live, and phases 3-6
## add more fields than phases 1-2 contained in total. One Resource holding both the graph
## bake and the crawl steering weights is a file nobody can find anything in, and it is
## the file gdlint's 1000-line cap would stop first.
##
## THE COST MODEL AND THE CONTROLLERS MUST AGREE, and this is the file where they can
## stop agreeing. `NavigationConfig.normal_speed` is what A* charges for a NORMAL_VOLUME
## edge; `crawl_max_speed` and `tunnel_max_speed` are what the body actually achieves. If
## a controller is slower than the routing model believes, every route is chosen against
## a travel time the alien cannot deliver, and it is not wrong anywhere -- it is just
## consistently wrong about which way is quicker. `NavigationConfig.invariant_failures()`
## asserts the ordering rather than trusting it.
##
## A bare `LocomotionProfile.new()` is fully usable, so tests and a freshly dropped
## CreatureNavigation both run without a .tres.

# ----- surface crawl (sections 8, 21, 22, 23) -----

@export_group("Surface crawl")
## Top crawl speed. Must not exceed NavigationConfig.normal_speed -- see the class note.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m/s") var crawl_max_speed: float = 5.0
@export_range(0.1, 60.0, 0.1, "or_greater", "suffix:m/s/s") var crawl_acceleration: float = 8.0
## Section 22's turn radius. Larger means wider, more sweeping arcs.
##
## This is a CONSTRAINT, not a preference. `SurfaceCrawlController` clamps the chosen
## direction to the angle this permits at the current speed, so a route demanding a
## sharper turn is executed as an arc rather than as a pivot. Set it to near zero and the
## alien turns on the spot, which is the octopus-versus-tank distinction section 8.3 draws.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var crawl_turn_radius: float = 2.5
## How far the crawler looks for something to hold on to (section 8.2's "tentacle reach").
##
## ALSO THE DEFINITION OF UNSUPPORTED OPEN SPACE. A body with no surface within this
## distance is not crawling, whatever the route says, and Invariant 3 says it may only be
## there via a leap. `can_skip_to(SURFACE_CRAWL)` refuses any shortcut with a sample this
## far from everything, which is the check that keeps smoothing honest.
##
## IT HAS TO CLEAR THE BODY'S OWN RADIUS, WITH ROOM TO SPARE, and the first value tried
## did not. A body holding a flat wall sits at least `normal_clearance()` -- 1.25 m at the
## shipped ClearanceProfile -- from it, because anything closer is a collision. At 2.2 m
## that left barely a metre of usable band, and an alien that drifted a little off its
## floor reported itself unsupported and stopped. 3.5 m gives 1.25 m to 3.5 m, which is a
## creature holding a wall rather than one balanced on it.
##
## The full 3.5 m is only reached along the six axes the fan always probes; the Fibonacci
## fill between them reaches a little less perpendicular to any given surface. See
## `NavSurfaceField.fan_directions` -- an earlier fan omitted the axes entirely and lost a
## tenth of this number in the one direction that mattered.
@export_range(0.2, 12.0, 0.1, "or_greater", "suffix:m") var crawl_surface_reach: float = 3.5
## Directions scored per tick (section 21). This is the crawler's whole per-frame cost:
## one probe ray each, plus a swept cast for the best `crawl_validated_count` of them.
@export_range(3, 33, 2) var crawl_candidate_count: int = 9
## Total spread of the candidate fan, centred on current heading. A full 360 wastes rays
## behind the body; too narrow and the alien cannot round a corner without stopping.
@export_range(20.0, 350.0, 5.0, "suffix:deg") var crawl_candidate_arc_degrees: float = 120.0
## Spread of the second fan, tried once when every shortlisted candidate in the first has
## been refused.
##
## THE ARC ABOVE IS AN OPTIMISATION AND THIS IS ITS ESCAPE HATCH. 120 degrees is the right
## place to spend nine rays while the way ahead is open, and it is exactly wrong at the one
## moment the alien is boxed in: the direction out of a dead end is usually behind. Before
## this existed the crawler refused the tick, the planner stalled, and the alien stopped in
## front of an outcrop it could have walked around. Costs nothing on a tick that succeeds.
@export_range(20.0, 360.0, 5.0, "suffix:deg") var crawl_escape_arc_degrees: float = 360.0
## How far ahead a candidate direction is evaluated.
@export_range(0.1, 8.0, 0.1, "or_greater", "suffix:m") var crawl_step_distance: float = 1.2
## How many top-scoring candidates pay for a swept collision cast. Scoring is cheap and
## casting is not, so only the shortlist is proven.
@export_range(1, 12, 1) var crawl_validated_count: int = 3
## Fraction of top speed the body keeps when the direction it wants is at right angles to
## the one it can currently achieve.
##
## Section 22's "available turning distance", bought rather than assumed. At 1.0 the
## crawler travels at full speed while turning two degrees a tick and overshoots every
## corner; near 0 it stops dead to turn, which reads as a machine rather than an animal.
@export_range(0.05, 1.0, 0.01) var crawl_cornering_floor: float = 0.25
## Score below which a candidate is not worth taking. A tick where nothing clears this is
## section 8.2's "cannot reach the next surface" -- the planner considers a leap instead.
@export_range(-10.0, 10.0, 0.05) var crawl_minimum_score: float = 0.0
## Rays in the fan `NavSurfaceField` takes around the body, for enclosure and centering.
##
## SIX AXES PLUS FOUR FILL. The first six are always the principal axes -- see
## `NavSurfaceField.fan_directions` for why omitting them silently shortens
## `crawl_surface_reach` by a tenth in exactly the direction that matters most -- and the
## remainder spread over the sphere to catch surfaces the axes miss. Below six this is
## clamped, because the axes are not optional.
@export_range(6, 26, 1) var crawl_surface_ray_count: int = 10
## Section 23. How fast body forward and up may rotate toward their targets, in radians
## per second. Continuity, not snapping: an alien whose orientation teleports to match
## each new surface reads as a bug even when the position is perfect.
@export_range(0.1, 30.0, 0.1, "or_greater") var orientation_slew_rate: float = 3.0

@export_group("Crawl steering weights")
## The six terms of section 21's score, which the spec writes as
## `goal_alignment + surface_quality + clearance_score + orientation_continuity
##  - turning_penalty - collision_penalty`.
## The first four are rewards and the last two are penalties; all six are stored positive
## and the sign is applied in `SurfaceCrawlController.score`, so a negative weight here
## always means "inverted", never "this one happens to be a penalty".
@export_range(0.0, 5.0, 0.05) var weight_goal_alignment: float = 1.0
@export_range(0.0, 5.0, 0.05) var weight_surface_quality: float = 0.8
@export_range(0.0, 5.0, 0.05) var weight_clearance: float = 0.35
@export_range(0.0, 5.0, 0.05) var weight_orientation_continuity: float = 0.45
@export_range(0.0, 5.0, 0.05) var weight_turning_penalty: float = 0.9
## Deliberately the largest. A candidate that would collide is not a slightly worse
## option, and a collision penalty comparable to the goal reward produces an alien that
## walks into a wall because the target is on the other side of it.
@export_range(0.0, 10.0, 0.05) var weight_collision_penalty: float = 2.0

# ----- tunnel swim (section 9) -----

@export_group("Tunnel swim")
## How far the enclosure fan looks. Terrain beyond this does not count as enclosing.
@export_range(0.5, 20.0, 0.1, "or_greater", "suffix:m") var tunnel_enclosure_reach: float = 3.0
## Fraction of the fan that must hit terrain before the body starts swimming.
##
## SECTION 9.3 SAYS THIS IS DECIDED BY LOCAL GEOMETRY, NOT BY A FLAG, and this pair of
## numbers is that decision. A 4 m tunnel with a 6-ray axis fan encloses 4 of 6 = 0.667,
## comfortably over.
@export_range(0.0, 1.0, 0.01) var tunnel_enter_enclosure: float = 0.60
## Fraction at or below which the body goes back to crawling.
##
## STRICTLY BELOW THE ENTER THRESHOLD, AND THAT GAP IS THE POINT. One threshold makes the
## mode flicker every frame at a tunnel mouth, where the reading oscillates around it.
@export_range(0.0, 1.0, 0.01) var tunnel_exit_enclosure: float = 0.40
## How hard the medial term pulls toward the middle, against forward progress
## (section 9.2). At 0 the alien hugs whichever wall it started on; above ~1.5 it
## corkscrews down the tunnel rather than travelling along it.
@export_range(0.0, 3.0, 0.05) var tunnel_centering_weight: float = 0.6
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m/s") var tunnel_max_speed: float = 6.0
## Minimum time in a mode before another may be selected.
##
## The hysteresis pair above is not enough on its own: at a mouth where the reading
## straddles ONE threshold, two thresholds still flicker. This is what actually stops it.
@export_range(0.0, 3.0, 0.05, "suffix:s") var mode_dwell_time: float = 0.35

# ----- local avoidance and adhesion (sections 8.1, 9.2, 21) -----

@export_group("Local avoidance")
## Everything `locomotion/avoidance/` steers by, in one sub-resource beside the code that
## reads it. See `AvoidanceProfile` for why these four are not fields here any more.
@export var avoidance: AvoidanceProfile = AvoidanceProfile.new()

# ----- slip recovery (Invariant 3) -----

@export_group("Recovery")
## How far the recovery fan looks when the ordinary one has found nothing at all.
##
## NOT AN AVOIDANCE NUMBER, DESPITE HAVING SHARED A GROUP HEADING WITH THEM. Avoidance
## biases a body that is somewhere legal; this belongs to `NavLocalPlanner._reacquire`,
## which is the escape from somewhere the body may not be at all.
##
## LONG, AND ONLY EVER PAID FOR ON A TICK THAT ALREADY FAILED. A body with no surface
## within `crawl_surface_reach` has slipped (Invariant 3: the only legal unsupported state
## is airborne), and it needs to know which way home from wherever it ended up -- which in
## the demo cave's largest room is 19 m. A longer default fan would charge every ordinary
## tick for an answer only a slipped body needs.
@export_range(1.0, 200.0, 1.0, "or_greater", "suffix:m") var recovery_reach: float = 24.0

# ----- wiggle (sections 10, 40.2) -----

@export_group("Wiggle")
## Seconds spent compressing before entering a tight passage, and again on the way out.
##
## PAID TWICE PER SQUEEZE, WHICH IS WHAT NavigationConfig.squeeze_transition_penalty IS
## CHARGING FOR. Routing believes a squeeze costs that flat penalty; if the controller
## takes longer than the routing model paid, A* keeps choosing squeezes that are not
## actually cheaper. The config asserts `squeeze_transition_penalty >= 2 * this`.
@export_range(0.0, 5.0, 0.05, "suffix:s") var squeeze_transition_time: float = 0.6
## How far past a tight passage the body stays compressed before expanding. Expanding on
## the exact metre the passage ends puts the normal body half inside the crevice wall.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m") var wiggle_exit_margin: float = 0.5
## Section 40.2. Window over which progress is measured before calling it grinding.
@export_range(0.1, 10.0, 0.05, "suffix:s") var grind_window: float = 1.5
## Metres of progress that must happen within `grind_window`, or the traversal aborts.
##
## Section 40.2: "do not merely push against collision indefinitely". Without this the
## alien presses into a crevice it cannot enter for as long as the route says to, which
## is both the least believable failure in the system and the hardest to notice in a log.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m") var grind_progress_threshold: float = 0.35

# ----- leap (section 11) -----

@export_group("Leap")
## Launch speed. Zero gravity, so this is also the whole flight speed (section 11.1).
@export_range(0.5, 40.0, 0.1, "or_greater", "suffix:m/s") var leap_speed: float = 9.0
## Time spent anchoring and aiming before launch. Section 40.5 re-validates the flight
## every tick of this, and aborts rather than launching into geometry that has changed.
@export_range(0.0, 5.0, 0.05, "suffix:s") var leap_preparation_time: float = 0.8
## Time spent catching and re-attaching at the far end.
@export_range(0.0, 5.0, 0.05, "suffix:s") var leap_grab_time: float = 0.6
## Section 11.4's tuning knob: flat seconds added to every leap's cost.
##
## THE ONLY REASON THE ALIEN DOES NOT LEAP CONSTANTLY. With the shipped speeds a leap is
## faster than a crawl over almost any distance, so without a bias the cost comparison
## says "always leap" and section 11.4's "roughly 10 m of crawling saved" never happens.
##
## Solved rather than guessed, against section 43's own two scenarios:
##
##     Scenario D   crawl 30 m = 5.00 s   leap 20 m = 4.52 s   -> leaps
##     Scenario E   crawl 21 m = 3.50 s   leap 18 m = 4.30 s   -> crawls
##
## The admissible window is 0.10 < leap_bias < 1.38. This sits nearer D's edge on purpose:
## a wrong leap is far more visible than a missed one. Both scenarios are asserted in
## NavigationConfig.invariant_failures(), so mistuning this fails the build by name.
@export_range(0.0, 10.0, 0.05, "suffix:s") var leap_bias: float = 0.9
## How many route anchors ahead are considered as leap destinations. Anchors are free
## destinations with a directly comparable crawl distance already known.
@export_range(1, 16, 1) var leap_lookahead_anchors: int = 4
## Extra destinations fanned around the route direction, for leaps to a wall no anchor
## sits on. Zero disables the fan and leaves only the anchors.
@export_range(0, 17, 1) var leap_fan_count: int = 5
@export_range(5.0, 180.0, 5.0, "suffix:deg") var leap_fan_arc_degrees: float = 60.0
## How far a fanned destination may be sought.
##
## NOT A MAXIMUM LEAP DISTANCE. Section 11.1 is explicit that the alien has none, and
## Scenario H requires distance alone never to reject a leap. This bounds the SEARCH, not
## the flight: a route anchor further away than this is still a legal destination.
@export_range(1.0, 200.0, 1.0, "or_greater", "suffix:m") var leap_max_search_distance: float = 60.0
## How far past the landing point a grabbable surface may be (section 11.2.3).
@export_range(0.1, 10.0, 0.1, "or_greater", "suffix:m") var leap_grab_reach: float = 1.5
## Minimum dot between the launch direction and the surface normal being launched from.
##
## You cannot launch into the wall you are holding. Slightly above zero rather than at it,
## because a launch exactly parallel to the surface grazes it for the whole flight.
@export_range(-1.0, 1.0, 0.01) var leap_min_launch_dot: float = 0.05
## How close to the landing point counts as arrived.
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:m") var leap_arrival_distance: float = 1.0
## Rays cast around the flight axis each tick, looking for section 11.5's opportunistic
## grab. Small: this runs every frame of every flight.
@export_range(0, 12, 1) var leap_grab_ray_count: int = 4


## Section 11.4's leap cost, in seconds. Preparation, flight, grab, bias.
func leap_travel_time(distance: float) -> float:
	return leap_preparation_time + distance / leap_speed + leap_grab_time + leap_bias


## What the same distance costs crawled, for the section 11.4 comparison.
func crawl_travel_time(distance: float) -> float:
	return distance / crawl_max_speed


## Section 22. The largest heading change physically available this tick.
##
## Arc geometry, not a fudge factor: a body moving at `speed` for `delta` covers
## `speed * delta` along a circle of radius `turn_radius`, which subtends
## `speed * delta / turn_radius` radians. A stationary body is unconstrained, which is
## correct -- turn radius is a consequence of momentum, and there is none at rest.
static func max_turn_angle(speed: float, delta: float, turn_radius: float) -> float:
	if turn_radius <= 0.0 or speed <= 0.0 or delta <= 0.0:
		return PI
	return minf(speed * delta / turn_radius, PI)


func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if crawl_max_speed <= 0.0:
		failures.append("crawl_max_speed must be positive")
	if crawl_acceleration <= 0.0:
		failures.append("crawl_acceleration must be positive")
	if crawl_turn_radius <= 0.0:
		failures.append("crawl_turn_radius must be positive")
	if crawl_surface_reach <= 0.0:
		failures.append("crawl_surface_reach must be positive")
	if crawl_step_distance > crawl_surface_reach:
		# A step longer than the reach lands the body where nothing was ever probed.
		var spans: Array = [crawl_step_distance, crawl_surface_reach]
		failures.append("crawl_step_distance %.2f exceeds crawl_surface_reach %.2f" % spans)
	if crawl_candidate_count < 1:
		failures.append("crawl_candidate_count must be at least 1")
	if crawl_validated_count > crawl_candidate_count:
		failures.append("crawl_validated_count exceeds crawl_candidate_count")
	if crawl_surface_ray_count < 6:
		# The six principal axes are always probed; fewer than six is a request the fan
		# cannot honour, and the shortfall would show up as a shortened reach.
		failures.append("crawl_surface_ray_count must be at least 6")
	if crawl_cornering_floor <= 0.0:
		failures.append("crawl_cornering_floor must be positive, or a turn stops the body")
	if crawl_escape_arc_degrees < crawl_candidate_arc_degrees:
		# A narrower escape than the fan it rescues cannot contain a direction the first
		# pass had not already scored and refused.
		var arcs: Array = [crawl_escape_arc_degrees, crawl_candidate_arc_degrees]
		failures.append(
			"crawl_escape_arc_degrees %.0f is below crawl_candidate_arc_degrees %.0f" % arcs
		)
	if avoidance == null:
		# Every avoidance call site dereferences it, so a null here is a crash on the first
		# tick of the first mode rather than a number that is merely wrong.
		failures.append("avoidance profile is null")
	else:
		failures.append_array(avoidance.invariant_failures())
		if avoidance.hold_distance > crawl_surface_reach - crawl_step_distance:
			# A body at the hold distance must still be able to take a full step without
			# leaving reach, or adhesion permits the very drift it exists to prevent. Checked
			# here rather than in AvoidanceProfile because it is the only place that can see
			# the reach and the step as well as the hold.
			var holds: Array = [avoidance.hold_distance, crawl_surface_reach, crawl_step_distance]
			(
				failures
				. append(
					(
						"avoidance.hold_distance %.2f leaves no room inside crawl_surface_reach %.2f for a %.2f step"
						% holds
					)
				)
			)
	if recovery_reach <= crawl_surface_reach:
		# A recovery fan no longer than the ordinary one re-asks the question that just
		# came back empty.
		var reaches: Array = [recovery_reach, crawl_surface_reach]
		failures.append("recovery_reach %.2f does not exceed crawl_surface_reach %.2f" % reaches)
	if orientation_slew_rate <= 0.0:
		failures.append("orientation_slew_rate must be positive")
	if tunnel_enclosure_reach <= 0.0:
		failures.append("tunnel_enclosure_reach must be positive")
	if tunnel_exit_enclosure >= tunnel_enter_enclosure:
		# One threshold is not hysteresis, and the mode flickers at every tunnel mouth.
		var gates: Array = [tunnel_exit_enclosure, tunnel_enter_enclosure]
		failures.append("tunnel_exit_enclosure %.2f is not below enter %.2f" % gates)
	if tunnel_max_speed <= 0.0:
		failures.append("tunnel_max_speed must be positive")
	if mode_dwell_time < 0.0:
		failures.append("mode_dwell_time must not be negative")
	if squeeze_transition_time < 0.0:
		failures.append("squeeze_transition_time must not be negative")
	if grind_window <= 0.0:
		failures.append("grind_window must be positive")
	if leap_speed <= 0.0:
		failures.append("leap_speed must be positive")
	if leap_preparation_time < 0.0:
		failures.append("leap_preparation_time must not be negative")
	if leap_grab_time < 0.0:
		failures.append("leap_grab_time must not be negative")
	if leap_bias < 0.0:
		failures.append("leap_bias must not be negative")
	if leap_lookahead_anchors < 1:
		failures.append("leap_lookahead_anchors must be at least 1")
	if leap_grab_reach <= 0.0:
		failures.append("leap_grab_reach must be positive")
	if leap_max_search_distance <= 0.0:
		failures.append("leap_max_search_distance must be positive")
	return failures
