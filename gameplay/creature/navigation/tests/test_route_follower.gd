extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Sections 18, 19 and 40.1.
##
## THE MONOTONIC INDEX IS THE POINT OF THIS CLASS. Section 40.1 lists waypoint
## oscillation as a failure to handle explicitly, and section 18 says why: "never move
## backward to a previous graph waypoint because of nearest-point changes". The
## tempting implementation -- each frame, head for the nearest unvisited anchor --
## deadlocks the moment a route doubles back on itself, which cave routes do
## constantly. The alien reaches anchor 5, anchor 2 is now nearer, it turns round,
## anchor 5 is nearer again, and it paces between them forever while every individual
## decision looks correct and nothing errors.

const STRAIGHT_ANCHORS := [
	Vector3.ZERO,
	Vector3(4.0, 0.0, 0.0),
	Vector3(8.0, 0.0, 0.0),
	Vector3(12.0, 0.0, 0.0),
	Vector3(16.0, 0.0, 0.0),
]


func test_the_index_starts_at_the_first_thing_to_move_toward() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	# Anchor 0 is where the body already is; heading for it would be a no-op frame.
	assert_eq(follower.index, 1)
	assert_eq(follower.current_anchor(), STRAIGHT_ANCHORS[1])


func test_arriving_advances_the_index() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	# Smoothing is what would otherwise collapse this route in one step.
	_block_every_shortcut()

	follower.advance(STRAIGHT_ANCHORS[1])
	assert_eq(follower.index, 2, "standing on anchor 1 should target anchor 2")


## Section 40.1, stated as a property rather than as a scenario: no sequence of body
## positions may ever lower the index.
func test_the_index_never_regresses() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	_block_every_shortcut()

	var adversarial: Array = [
		STRAIGHT_ANCHORS[1],
		STRAIGHT_ANCHORS[2],
		STRAIGHT_ANCHORS[3],
		# Back to the start, which is what a doubled-back route or a knockback looks
		# like from here.
		STRAIGHT_ANCHORS[0],
		Vector3(-40.0, 0.0, 0.0),
		STRAIGHT_ANCHORS[1],
	]
	var highest: int = follower.index
	for at: Vector3 in adversarial:
		follower.advance(at)
		assert_gte(follower.index, highest, "the index went backward at body position %s" % at)
		highest = follower.index


func test_only_a_new_route_resets_the_index() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	_block_every_shortcut()
	_walk(follower, [STRAIGHT_ANCHORS[1], STRAIGHT_ANCHORS[2]])
	assert_gt(follower.index, 1)

	follower.set_route(_straight_route())
	assert_eq(follower.index, 1, "section 40.1's 'unless a full replan occurs'")
	assert_eq(follower.skipped_anchors.size(), 0, "the old route's skipped anchors leaked")


func test_smoothing_collapses_anchors_it_can_reach() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	# Nothing in the way: the whole straight line is one clear sweep.
	_probe.add_room(AABB(Vector3(-8.0, -8.0, -8.0), Vector3(40.0, 16.0, 16.0)))

	follower.advance(STRAIGHT_ANCHORS[0])
	assert_gt(follower.index, 1, "an unobstructed straight route should collapse")
	assert_gt(follower.skipped_anchors.size(), 0, "section 39 wants the collapsed anchors drawable")


func test_smoothing_never_reaches_past_the_lookahead() -> void:
	_config.smoothing_lookahead = 2
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	_probe.add_room(AABB(Vector3(-8.0, -8.0, -8.0), Vector3(40.0, 16.0, 16.0)))

	follower.advance(STRAIGHT_ANCHORS[0])
	assert_lte(follower.index, 3, "a lookahead of 2 from index 1 must not pass anchor 3")


## Section 19's four modes, each refusing when its own requirement is unmet -- a
## permissive default here is an alien drifting across open space, which Invariant 3
## forbids and which no behavioural test would catch.
##
## The middle of a 40 x 16 x 16 room is 8 m from every wall, so a shortcut across it has
## nothing within tentacle reach anywhere along its length: unsupported open space by
## section 19's definition, however clear the sweep is.
func test_modes_refuse_when_their_requirements_are_unmet() -> void:
	var follower: RouteFollower = _follower()
	_probe.add_room(AABB(Vector3(-8.0, -8.0, -8.0), Vector3(40.0, 16.0, 16.0)))
	var from := Vector3.ZERO
	var to := Vector3(8.0, 0.0, 0.0)

	assert_false(
		follower.can_skip_to(from, to, NavLocomotion.Mode.SURFACE_CRAWL),
		"nothing is within reach along this line; section 19 calls that unsupported space"
	)
	assert_false(
		follower.can_skip_to(from, to, NavLocomotion.Mode.LEAP),
		"leap needs the Phase 6 planner; it must not say yes without one"
	)
	assert_true(
		follower.can_skip_to(from, to, NavLocomotion.Mode.TUNNEL_SWIM),
		"an unobstructed sweep should be skippable at normal body size"
	)


## The other half of the same claim: surface crawl is a real check now, not a refusal
## wearing a check's name. Without this, `can_skip_to` could return false unconditionally
## and every assertion above would still pass.
func test_surface_crawl_permits_a_shortcut_that_stays_on_a_wall() -> void:
	var follower: RouteFollower = _follower()
	_flat_floor()
	var from := Vector3(0.0, FLOOR_STANDOFF, 0.0)
	var to := Vector3(8.0, FLOOR_STANDOFF, 0.0)

	assert_true(
		follower.can_skip_to(from, to, NavLocomotion.Mode.SURFACE_CRAWL),
		"a metre above a continuous floor is exactly what a crawler can shortcut along"
	)


func test_surface_crawl_refuses_a_shortcut_that_leaves_the_wall_partway() -> void:
	var follower: RouteFollower = _follower()
	# A floor that stops at x = 0. The far half of this shortcut is over nothing.
	_probe.add_solid(AABB(Vector3(-20.0, -4.0, -20.0), Vector3(20.0, 4.0, 40.0)))

	assert_true(
		follower.can_skip_to(
			Vector3(-8.0, FLOOR_STANDOFF, 0.0),
			Vector3(-2.0, FLOOR_STANDOFF, 0.0),
			NavLocomotion.Mode.SURFACE_CRAWL
		),
		"the supported half is skippable"
	)
	assert_false(
		follower.can_skip_to(
			Vector3(-8.0, FLOOR_STANDOFF, 0.0),
			Vector3(12.0, FLOOR_STANDOFF, 0.0),
			NavLocomotion.Mode.SURFACE_CRAWL
		),
		"crossing the edge of the floor is a leap, and smoothing may not author one"
	)


func test_wiggle_and_tunnel_swim_use_different_bodies() -> void:
	var follower: RouteFollower = _follower()
	# A 2 m gap: the squeezed body (1.5 m) fits, the normal body (2.5 m) does not.
	_probe.add_room(AABB(Vector3(-4.0, -4.0, -4.0), Vector3(20.0, 8.0, 8.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, -4.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, 1.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, -4.0), Vector3(2.0, 3.0, 8.0)))
	_probe.add_solid(AABB(Vector3(4.0, 1.0, -4.0), Vector3(2.0, 3.0, 8.0)))

	var from := Vector3.ZERO
	var to := Vector3(10.0, 0.0, 0.0)
	assert_false(
		follower.can_skip_to(from, to, NavLocomotion.Mode.TUNNEL_SWIM),
		"the normal body does not fit a 2 m gap"
	)
	assert_true(follower.can_skip_to(from, to, NavLocomotion.Mode.WIGGLE), "the squeezed body does")


## Section 19's shortcut rule, stated where it bites: a collapse that swallows a wiggle
## segment has to be executable AS A WIGGLE for its whole length. Validating it with the
## normal body instead hands the locomotion layer a line through a crevice it does not
## fit.
func test_a_shortcut_spanning_a_wiggle_segment_is_checked_as_a_wiggle() -> void:
	var follower: RouteFollower = _follower()
	# Open everywhere except a 2 m gap partway along the route.
	_probe.add_room(AABB(Vector3(-4.0, -4.0, -4.0), Vector3(24.0, 8.0, 8.0)))
	_probe.add_solid(AABB(Vector3(8.0, -4.0, -4.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(8.0, -4.0, 1.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(8.0, -4.0, -4.0), Vector3(2.0, 3.0, 8.0)))
	_probe.add_solid(AABB(Vector3(8.0, 1.0, -4.0), Vector3(2.0, 3.0, 8.0)))

	var route := NavRoute.new()
	route.status = NavRoute.Status.COMPLETE
	route.anchors = PackedVector3Array(
		[Vector3.ZERO, Vector3(6.0, 0.0, 0.0), Vector3(12.0, 0.0, 0.0), Vector3(16.0, 0.0, 0.0)]
	)
	route.segments = [
		NavRouteSegment.make(route.anchors[0], route.anchors[1], NavEdge.Type.NORMAL_VOLUME),
		NavRouteSegment.make(route.anchors[1], route.anchors[2], NavEdge.Type.WIGGLE),
		NavRouteSegment.make(route.anchors[2], route.anchors[3], NavEdge.Type.NORMAL_VOLUME),
	]
	follower.set_route(route)

	follower.advance(Vector3.ZERO)
	# The collapse is legal only because the squeezed body clears the gap. Had the mode
	# been taken from the destination segment (NORMAL_VOLUME) the sweep would have used
	# the normal body and refused.
	assert_gt(follower.index, 1, "the shortcut through the gap should have been taken")


func test_is_finished_needs_the_last_anchor_not_just_the_last_index() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	_block_every_shortcut()

	_walk(follower, [STRAIGHT_ANCHORS[1], STRAIGHT_ANCHORS[2], STRAIGHT_ANCHORS[3]])
	assert_false(follower.is_finished(STRAIGHT_ANCHORS[3]), "there is still an anchor to reach")
	assert_true(follower.is_finished(STRAIGHT_ANCHORS[4]))


## ADVANCEMENT REQUIRES ARRIVING, NOT MERELY BEING PAST AN ANCHOR, and that is the
## design rather than an omission. Section 18 forbids re-picking the nearest waypoint,
## so a body that is displaced down the route cannot skip ahead by being closer to a
## later anchor -- it either smooths past (which needs a clear sweep) or it replans.
## `_walk` is therefore how a follower is actually driven, one arrival at a time.
func test_being_past_an_anchor_is_not_arriving_at_it() -> void:
	var follower: RouteFollower = _follower()
	follower.set_route(_straight_route())
	_block_every_shortcut()

	follower.advance(STRAIGHT_ANCHORS[3])
	assert_eq(
		follower.index,
		1,
		"a body teleported down the route must not silently claim the anchors it skipped"
	)


func test_no_route_is_finished_and_harmless() -> void:
	var follower: RouteFollower = _follower()
	assert_false(follower.has_route())
	assert_true(follower.is_finished(Vector3.ZERO))
	follower.advance(Vector3.ZERO)
	assert_eq(follower.current_anchor(), Vector3.ZERO)


# ----- helpers -----


func _straight_route() -> NavRoute:
	var route := NavRoute.new()
	route.status = NavRoute.Status.COMPLETE
	route.anchors = PackedVector3Array(STRAIGHT_ANCHORS)
	route.target_position = STRAIGHT_ANCHORS[-1]
	for step: int in STRAIGHT_ANCHORS.size() - 1:
		route.segments.append(
			NavRouteSegment.make(
				STRAIGHT_ANCHORS[step], STRAIGHT_ANCHORS[step + 1], NavEdge.Type.NORMAL_VOLUME
			)
		)
	return route


## Makes every anchor unreachable by shortcut, so a test can watch the index advance one
## step at a time. Without it an unobstructed straight route collapses to its end on the
## first advance() and there is nothing left to observe.
func _block_every_shortcut() -> void:
	_probe.unreachable_nodes = STRAIGHT_ANCHORS.duplicate()


## Drives the follower the way a body actually would: arriving at each anchor in turn.
func _walk(follower: RouteFollower, stops: Array) -> void:
	for at: Vector3 in stops:
		follower.advance(at)
