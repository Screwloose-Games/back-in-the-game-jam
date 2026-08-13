class_name NavLeapPlanner
extends RefCounted

## Finds and prices zero-gravity leaps (navigation.md section 11).
##
## QUERIED DYNAMICALLY, NEVER BAKED (section 11.3). LEAP is deliberately absent from
## `NavEdge.Type`, and a GUT test enforces that. Baking leap edges is O(n^2) permanent
## connections that go stale the moment terrain changes, and the alternative -- asking, at
## the moment of use, whether a straight line happens to work right now -- costs a handful
## of casts and is never wrong.
##
## THE COST COMPARISON IS THE WHOLE DECISION (section 11.4). There is no "leap if the gap
## is big" rule anywhere in this module; there is a leap cost, a crawl cost, and whichever
## is smaller. That is what lets section 43's Scenario D (30 m crawl, 20 m leap) and
## Scenario E (21 m crawl, 18 m leap) come out differently without either being a case.
##
## THE CRAWL SIDE IS PRICED AT `normal_speed`, NOT AT `crawl_max_speed`, and that is
## deliberate. The distance being compared is measured ALONG ROUTE ANCHORS, and those are
## graph edges A* already priced at `normal_speed`; charging anything else would compare a
## leap against a number the router never used. It is also the comparison
## `NavigationConfig.invariant_failures()` asserts, so the build-time check and the runtime
## decision are the same arithmetic.
##
## REJECTION IS ORDERED CHEAPEST-FIRST: launch pose (no query), cost (no query), flight
## (two queries), grab (one query). Most candidates die before anything is cast.

## Every candidate considered on the last call, accepted and rejected, for section 39.
var last_candidates: Array[NavLeapCandidate] = []


## Section 11.2's four requirements, in order.
##
## `crawl_distance` is what reaching the same place costs on foot, and `remaining_after`
## is what is still left to crawl once the leap lands -- zero for a leap onto a route
## anchor, positive for one onto a wall partway there. Passing INF for `crawl_distance`
## asks "is this leap possible at all", which is what `can_skip_to` wants and what the
## planner deliberately does not.
func evaluate(
	origin: Vector3,
	launch_normal: Vector3,
	attached: bool,
	landing: Vector3,
	crawl_distance: float,
	remaining_after: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavLeapCandidate:
	var profile: LocomotionProfile = config.locomotion_profile
	var candidate := NavLeapCandidate.make(origin, landing)
	if candidate.direction.is_zero_approx():
		return candidate.reject(NavLeapCandidate.Rejection.NO_LAUNCH_POSE)

	# 1. Section 11.2.1. You cannot push off a surface you are not holding, and you cannot
	# push off INTO it -- a launch angled into the wall grazes it for the whole flight.
	if not attached or candidate.direction.dot(launch_normal) < profile.leap_min_launch_dot:
		return candidate.reject(NavLeapCandidate.Rejection.NO_LAUNCH_POSE)

	candidate.flight_time = candidate.distance / profile.leap_speed
	candidate.leap_cost = (
		profile.leap_travel_time(candidate.distance) + config.normal_travel_time(remaining_after)
	)
	candidate.crawl_cost = config.normal_travel_time(crawl_distance)
	# 2. Section 11.4, before any cast: most leaps are possible and not worth it.
	if candidate.leap_cost >= candidate.crawl_cost:
		return candidate.reject(NavLeapCandidate.Rejection.TOO_EXPENSIVE)

	# 3. Section 11.2.2. A SWEPT SHAPE, because a ray threads the alien through a crack.
	# Note there is no distance limit anywhere above or below: section 11.1 gives the alien
	# no maximum leap, and Scenario H requires distance alone never to reject one.
	var body: Shape3D = config.clearance_profile.normal_body()
	if not probe.shape_sweep_clear(body, origin, landing, config.world_mask):
		return candidate.reject(NavLeapCandidate.Rejection.BLOCKED_FLIGHT)

	# 4. Section 11.2.3. Something to catch at the far end, facing back at the alien.
	var grab: NavSurfaceSample = probe.surface_along(
		landing, candidate.direction, profile.leap_grab_reach, config.world_mask
	)
	if not grab.hit or grab.normal.dot(candidate.direction) > 0.0:
		return candidate.reject(NavLeapCandidate.Rejection.NO_GRAB)
	candidate.landing_normal = grab.normal
	return candidate.accept()


## The best leap available from here, or null. Section 11.3's dynamic query.
func best_leap(
	body: NavBodyState,
	follower: RouteFollower,
	reading: NavSurfaceReading,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavLeapCandidate:
	last_candidates = []
	if follower == null or not follower.has_route():
		return null
	var profile: LocomotionProfile = config.locomotion_profile
	var anchors: PackedVector3Array = follower.route.anchors
	var furthest: int = mini(follower.index + profile.leap_lookahead_anchors, anchors.size() - 1)

	var best: NavLeapCandidate = _best_over_anchors(
		body, follower, reading, furthest, probe, config
	)
	if best == null:
		best = _best_over_fan(body, follower, reading, furthest, probe, config)
	return best


# ----- internals -----


## Route anchors are the cheap destinations: each already has a crawl distance measured
## along the route, which is precisely what section 11.4 wants to compare against.
func _best_over_anchors(
	body: NavBodyState,
	follower: RouteFollower,
	reading: NavSurfaceReading,
	furthest: int,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavLeapCandidate:
	var best: NavLeapCandidate = null
	for target: int in range(follower.index, furthest + 1):
		var anchor: Vector3 = follower.route.anchors[target]
		var candidate: NavLeapCandidate = evaluate(
			body.position,
			reading.dominant_normal,
			reading.has_surface(),
			anchor,
			follower.distance_to_anchor(body.position, target),
			0.0,
			probe,
			config
		)
		candidate.target_anchor_index = target
		last_candidates.append(candidate)
		if candidate.accepted and (best == null or candidate.leap_cost < best.leap_cost):
			best = candidate
	return best


## Walls no anchor happens to sit on. Only reached when no anchor leap was worth taking,
## because this costs one ray per direction and anchors cost none.
##
## The destination is pulled off the wall by the body's own radius -- a landing point ON a
## surface is a landing point inside it, and the flight sweep would reject every one.
func _best_over_fan(
	body: NavBodyState,
	follower: RouteFollower,
	reading: NavSurfaceReading,
	furthest: int,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavLeapCandidate:
	var profile: LocomotionProfile = config.locomotion_profile
	if profile.leap_fan_count <= 0 or not reading.has_surface():
		return null
	var goal: Vector3 = follower.route.anchors[furthest]
	var crawl: float = follower.distance_to_anchor(body.position, furthest)
	var standoff: float = config.clearance_profile.normal_clearance()

	var best: NavLeapCandidate = null
	for heading: Vector3 in _fan_headings(goal - body.position, profile):
		var wall: NavSurfaceSample = probe.surface_along(
			body.position, heading, profile.leap_max_search_distance, config.world_mask
		)
		if not wall.hit:
			continue
		var landing: Vector3 = wall.point + wall.normal * standoff
		var candidate: NavLeapCandidate = evaluate(
			body.position,
			reading.dominant_normal,
			true,
			landing,
			crawl,
			landing.distance_to(goal),
			probe,
			config
		)
		last_candidates.append(candidate)
		if candidate.accepted and (best == null or candidate.leap_cost < best.leap_cost):
			best = candidate
	return best


static func _fan_headings(toward: Vector3, profile: LocomotionProfile) -> Array[Vector3]:
	var headings: Array[Vector3] = []
	if toward.is_zero_approx():
		return headings
	var centre: Vector3 = toward.normalized()
	var axis: Vector3 = centre.cross(Vector3.UP)
	if axis.is_zero_approx():
		axis = centre.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var count: int = profile.leap_fan_count
	var arc: float = deg_to_rad(profile.leap_fan_arc_degrees)
	for index: int in count:
		var offset: float = 0.0
		if count > 1:
			offset = arc * (float(index) / float(count - 1) - 0.5)
		headings.append(centre.rotated(axis, offset))
	return headings
