class_name RouteFollower
extends RefCounted

## Consumes a route one anchor at a time (navigation.md sections 18, 19, 40.1).
##
## THE INDEX ONLY EVER GOES UP. Section 40.1 makes waypoint oscillation an explicit
## failure to handle, and section 18 says why: "never move backward to a previous graph
## waypoint because of nearest-point changes". The tempting implementation -- each
## frame, target the nearest unvisited anchor -- deadlocks the moment a route doubles
## back on itself, which routes through caves do constantly. The alien reaches anchor
## 5, anchor 2 is now nearer, it turns around, anchor 5 is nearer again, and it paces
## between them forever while every individual decision looks correct. Only
## `set_route()` moves the index backward.
##
## SMOOTHING IS LOCOMOTION-AWARE, NOT A VISIBILITY TEST (section 19). Collapsing
## A -> B -> C -> D into A -> D is only legal if the mode that will execute it can
## actually execute it, and "there is nothing in the way" is not that question. A
## straight line across an open chamber is unobstructed and is still not something a
## surface crawler can do (Invariant 3).
##
## WHAT `can_skip_to` CAN AND CANNOT CHECK TODAY:
##
##   WIGGLE          fully checked -- the compressed body sweeps the shortcut
##   TUNNEL_SWIM     body clearance checked; section 19's "navigable enclosed volume"
##                   and "suitable medial route" are Phase 4 and are NOT checked
##   SURFACE_CRAWL   body clearance AND continuous surface along the whole shortcut.
##                   A single sample with nothing within tentacle reach is section 19's
##                   "unsupported open-space section" and refuses the collapse, which is
##                   what keeps smoothing from quietly authoring a leap (Invariant 3).
##   LEAP            launch pose, swept flight and a grabbable endpoint, via the leap
##                   planner. Deliberately NOT whether the leap is worth taking -- that
##                   is section 11.4's cost comparison and belongs to the local planner.
##
## The two unchecked tunnel-swim requirements are not a hole this class opened. Baked
## NORMAL_VOLUME edges already connect nodes straight across open chambers on exactly
## the same evidence -- a clear swept cast -- because sections 2.2 and 13.3 put the
## crawl-versus-swim choice in the local planner rather than the graph. Smoothing is
## therefore no more permissive than the route it is smoothing.

var config: NavigationConfig = null
var probe: NavigationProbe = null
## Surface sampler, for section 19's surface-crawl check. Push-assigned by the facade
## alongside `config` and `probe`; null simply makes SURFACE_CRAWL refuse, which is the
## phase 1-2 behaviour and a safe thing for it to degrade to.
var surface: NavSurfaceField = null
## Leap planner, for section 19's leap check. Push-assigned by the facade alongside the
## rest; null makes LEAP refuse, which is the phase 1-5 behaviour and safe to degrade to.
var leaper: NavLeapPlanner = null
var route: NavRoute = null
## Which anchor the body is currently moving toward. Starts at 1: anchor 0 is where the
## body already is.
var index: int = 1
## Anchor indices that smoothing collapsed past, for the section 39 overlay. A route
## that visibly skips three anchors is working; one that skips none while the alien
## takes a visible dog-leg is a `can_skip_to` bug, and only the overlay tells them apart.
var skipped_anchors := PackedInt32Array()


func _init(navigation_config: NavigationConfig = null, navigation_probe: NavigationProbe = null):
	config = navigation_config
	probe = navigation_probe


## THE ONLY THING THAT MOVES THE INDEX BACKWARD, per section 40.1's "unless a full
## replan occurs".
func set_route(new_route: NavRoute) -> void:
	route = new_route
	index = 1
	skipped_anchors = PackedInt32Array()


func has_route() -> bool:
	return route != null and route.is_usable()


## Where the body should head right now. Sections 2.2 and 15 again: an ANCHOR, not a
## position the centre of mass has to pass through.
func current_anchor() -> Vector3:
	if not has_route():
		return Vector3.ZERO
	return route.anchors[mini(index, route.anchors.size() - 1)]


## The type of the hop currently being executed, so the locomotion layer knows whether
## the body needs to be compressed before it gets there.
func current_segment() -> NavRouteSegment:
	if not has_route() or route.segments.is_empty():
		return null
	return route.segments[clampi(index - 1, 0, route.segments.size() - 1)]


func is_finished(position: Vector3) -> bool:
	if not has_route():
		return true
	var last: int = route.anchors.size() - 1
	if index < last:
		return false
	return position.distance_to(route.anchors[last]) <= config.waypoint_arrival_distance


## Advances the index for a body now at `position`. Never regresses.
func advance(position: Vector3) -> void:
	if not has_route() or config == null:
		return
	var last: int = route.anchors.size() - 1

	while (
		index < last
		and position.distance_to(route.anchors[index]) <= config.waypoint_arrival_distance
	):
		index += 1

	# Furthest-first, so the biggest legal collapse wins rather than the first legal one.
	var limit: int = mini(index + config.smoothing_lookahead, last)
	for candidate: int in range(limit, index, -1):
		if can_skip_to(position, route.anchors[candidate], _mode_between(index, candidate)):
			for collapsed: int in range(index, candidate):
				skipped_anchors.append(collapsed)
			index = candidate
			break


## Section 19. See the class docstring for which modes are checkable in phases 1-2.
func can_skip_to(from: Vector3, target: Vector3, mode: NavLocomotion.Mode) -> bool:
	if config == null or probe == null:
		return false
	var profile: ClearanceProfile = config.clearance_profile
	match mode:
		NavLocomotion.Mode.WIGGLE:
			return probe.shape_sweep_clear(profile.squeezed_body(), from, target, config.world_mask)
		NavLocomotion.Mode.TUNNEL_SWIM:
			return probe.shape_sweep_clear(profile.normal_body(), from, target, config.world_mask)
		NavLocomotion.Mode.SURFACE_CRAWL:
			return _crawl_can_skip_to(from, target, profile)
		NavLocomotion.Mode.LEAP:
			return _leap_can_skip_to(from, target)
	return false


## Section 19's leap rules: a valid launch, a collision-free straight flight and a
## grabbable endpoint.
##
## DELIBERATELY SILENT ON WHETHER THE LEAP IS WORTH TAKING. Section 19 asks whether a
## shortcut is EXECUTABLE; section 11.4's cost comparison is the local planner's decision
## and belongs there. Passing INF as the crawl distance says exactly that -- any leap beats
## an infinitely long walk, so only the physical requirements can reject here.
##
## In open space with nothing to launch from and nothing to catch, this refuses, which is
## what keeps Invariant 3 intact when smoothing asks.
func _leap_can_skip_to(from: Vector3, target: Vector3) -> bool:
	if leaper == null or surface == null:
		return false
	var reading: NavSurfaceReading = surface.sample(
		from, probe, config.locomotion_profile, config.world_mask
	)
	var candidate: NavLeapCandidate = leaper.evaluate(
		from, reading.dominant_normal, reading.has_surface(), target, INF, 0.0, probe, config
	)
	return candidate.accepted


## Distance from `position` to the anchor at `to_index`, measured ALONG THE ROUTE.
##
## Section 11.4 compares a leap against the crawl it replaces, and the crawl is the route,
## not the straight line. Measuring the straight line would compare a leap against itself
## and conclude that leaping saves nothing, which is how a leap system ships and is never
## seen.
func distance_to_anchor(position: Vector3, to_index: int) -> float:
	if not has_route():
		return 0.0
	var target: int = clampi(to_index, 0, route.anchors.size() - 1)
	if target <= index:
		return position.distance_to(route.anchors[target])
	var total: float = position.distance_to(route.anchors[index])
	for step: int in range(index, target):
		total += route.anchors[step].distance_to(route.anchors[step + 1])
	return total


## The graph edge the body is currently traversing, or (-1, -1).
##
## Section 40.2 needs it: when a squeeze grinds to a halt, the thing to doubt is the EDGE
## the alien was trying to use, not the position it stopped at. Returns (-1, -1) for the
## first hop, which is an attachment from the body to the graph rather than a graph edge,
## and for any route the planner produced without node ids.
func current_edge_ids() -> Vector2i:
	if not has_route():
		return Vector2i(-1, -1)
	var ids: PackedInt32Array = route.node_ids
	if index < 1 or index >= ids.size():
		return Vector2i(-1, -1)
	return Vector2i(ids[index - 1], ids[index])


## Section 19's surface-crawl rules: body clearance, AND continuous usable surface with
## no unsupported open-space section.
##
## THE SECOND HALF IS THE WHOLE POINT. A straight line across a chamber passes the swept
## cast trivially -- there is nothing in the way, which is exactly why it is a bad
## shortcut for something that has to hold on the entire time. Checking only clearance
## here would let smoothing collapse a wall-hugging route into a glide across open space,
## and the alien would simply start moving better while breaking Invariant 3.
func _crawl_can_skip_to(from: Vector3, target: Vector3, profile: ClearanceProfile) -> bool:
	if surface == null:
		return false
	if not probe.shape_sweep_clear(profile.normal_body(), from, target, config.world_mask):
		return false
	return surface.continuous_surface_between(from, target, probe, config)


## Straight-line distance still to cover along the remaining anchors. An estimate for
## the behaviour layer, not a cost -- costs are in seconds and live on NavRoute.
func distance_remaining(position: Vector3) -> float:
	if not has_route():
		return 0.0
	var total: float = position.distance_to(current_anchor())
	for step: int in range(index, route.anchors.size() - 1):
		total += route.anchors[step].distance_to(route.anchors[step + 1])
	return total


# ----- internals -----


## The most restrictive mode across every hop a shortcut would swallow.
##
## MOST RESTRICTIVE, NOT THE MODE AT EITHER END. A shortcut spanning a wiggle segment
## and two normal ones has to be executable as a wiggle for its whole length; checking
## only the destination hop validates the shortcut with the normal body and then hands
## the locomotion layer a line through a crevice the normal body does not fit.
func _mode_between(from_index: int, to_index: int) -> NavLocomotion.Mode:
	var first: int = maxi(from_index - 1, 0)
	var last: int = mini(to_index - 1, route.segments.size() - 1)
	for step: int in range(first, last + 1):
		if route.segments[step].requires_squeeze():
			return NavLocomotion.Mode.WIGGLE
	return NavLocomotion.Mode.TUNNEL_SWIM
