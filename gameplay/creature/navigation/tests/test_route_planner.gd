extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Sections 16, 17 and 40.3-40.4.
##
## SECTION 16 IS THE REASON RoutePlanner EXISTS. Without it the class would be one call
## to AStar3D.get_id_path. The spec is blunt about why that is not enough: "do not
## simply call astar.get_closest_point() and trust that result. The nearest graph node
## may lie through terrain." In a cave that is not an edge case -- it is what happens
## every time the alien stands against a wall with a chamber behind it. The nearest node
## by distance is three metres away through solid rock, and a route that attaches to it
## is wrong from its first waypoint, silently, with a plausible-looking path on screen.


func test_attachment_skips_a_near_node_it_cannot_reach() -> void:
	var graph: NavGraph = _hand_graph(
		[Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), Vector3(9.0, 0.0, 0.0)], [[1, 2]]
	)
	# The nearest node by distance, and the one on the other side of the wall.
	_probe.unreachable_nodes = [Vector3(1.0, 0.0, 0.0)]

	var attached: Dictionary = _planner().attach(Vector3.ZERO, graph)
	assert_true(attached["ok"], "nothing attached at all")
	assert_eq(
		graph.node_at(attached["id"]).position,
		Vector3(5.0, 0.0, 0.0),
		"attachment took the nearest node rather than the nearest REACHABLE one"
	)


func test_attachment_reports_which_body_reached_the_graph() -> void:
	# A corridor the squeezed body clears and the normal one does not, between the query
	# point and the only node.
	_probe.add_room(AABB(Vector3(-4.0, -4.0, -4.0), Vector3(20.0, 8.0, 8.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, -4.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, 1.0), Vector3(2.0, 8.0, 3.0)))
	_probe.add_solid(AABB(Vector3(4.0, -4.0, -4.0), Vector3(2.0, 3.0, 8.0)))
	_probe.add_solid(AABB(Vector3(4.0, 1.0, -4.0), Vector3(2.0, 3.0, 8.0)))
	var graph: NavGraph = _hand_graph([Vector3(9.0, 0.0, 0.0)], [])

	var attached: Dictionary = _planner().attach(Vector3.ZERO, graph)
	assert_true(attached["ok"], "the squeezed body should reach through a 2 m gap")
	assert_eq(
		attached["type"],
		NavEdge.Type.WIGGLE,
		"an attachment that needed the squeezed body must say so, or the follower approaches uncompressed"
	)


func test_attachment_records_what_it_rejected() -> void:
	var graph: NavGraph = _hand_graph([Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)], [[0, 1]])
	_probe.unreachable_nodes = [Vector3(1.0, 0.0, 0.0)]

	var planner: RoutePlanner = _planner()
	planner.plan(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), graph)
	# Section 39 wants the rejected candidates drawable. A route that attaches to a far
	# node looks like a bug until the nearer ones it tried are on screen in red.
	assert_true(
		planner.last_attachment_attempts.size() >= 2,
		"the overlay cannot show why a near node was skipped if nothing recorded it"
	)


func test_a_complete_route_runs_from_the_body_to_the_true_target() -> void:
	var graph: NavGraph = _hand_graph(
		[Vector3(2.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)], [[0, 1], [1, 2]]
	)
	var start := Vector3(-1.0, 0.0, 0.0)
	var target := Vector3(13.0, 0.0, 0.0)

	var route: NavRoute = _planner().plan(start, target, graph)
	assert_eq(route.status, NavRoute.Status.COMPLETE)
	assert_eq(route.anchors[0], start, "anchor 0 should be where the body actually is")
	assert_eq(route.anchors[-1], target, "a complete route should reach the requested point")
	assert_eq(
		route.segments.size(),
		route.anchors.size() - 1,
		"every consecutive anchor pair needs a segment, including the two attachment hops"
	)


## Section 40.4: "return a useful partial route toward the destination where possible".
## An alien that stops dead because the player stepped behind a wall reads as broken.
func test_an_unreachable_target_yields_a_partial_route_toward_it() -> void:
	var graph: NavGraph = _hand_graph(
		[
			Vector3(2.0, 0.0, 0.0),
			Vector3(6.0, 0.0, 0.0),
			# A second component: no edge joins it to the first.
			Vector3(40.0, 0.0, 0.0)
		],
		[[0, 1]]
	)

	var route: NavRoute = _planner().plan(Vector3.ZERO, Vector3(41.0, 0.0, 0.0), graph)
	assert_eq(route.status, NavRoute.Status.PARTIAL)
	assert_true(route.anchors.size() >= 2, "a partial route should still be worth following")
	assert_eq(
		route.anchors[-1],
		Vector3(6.0, 0.0, 0.0),
		"a partial route should stop at the reachable node CLOSEST to the goal"
	)
	assert_eq(
		route.target_position,
		Vector3(41.0, 0.0, 0.0),
		"the caller still needs to know where it asked to go"
	)


func test_an_unattachable_start_is_unreachable() -> void:
	var graph: NavGraph = _hand_graph([Vector3(2.0, 0.0, 0.0)], [])
	_probe.unreachable_nodes = [Vector3(2.0, 0.0, 0.0)]

	var route: NavRoute = _planner().plan(Vector3.ZERO, Vector3(2.0, 0.0, 0.0), graph)
	assert_eq(
		route.status,
		NavRoute.Status.UNREACHABLE,
		"with nowhere to set off from there is no route, partial or otherwise"
	)
	assert_false(route.is_usable())


func test_an_empty_graph_is_unreachable_rather_than_a_crash() -> void:
	var graph := NavGraph.new()
	graph.configure(4.0, 16.0, 0.1)

	var route: NavRoute = _planner().plan(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), graph)
	assert_eq(route.status, NavRoute.Status.UNREACHABLE)


func test_segments_carry_the_edge_type_forward() -> void:
	var graph := NavGraph.new()
	graph.configure(6.0, _config.chunk_size, _config.best_seconds_per_metre())
	var a: int = graph.add_node(Vector3(2.0, 0.0, 0.0), 3.0)
	var b: int = graph.add_node(Vector3(6.0, 0.0, 0.0), 1.0)
	graph.add_edge(
		NavEdge.make(a, b, NavEdge.Type.WIGGLE, 4.0, 1.0, _config.wiggle_travel_time(4.0))
	)

	var route: NavRoute = _planner().plan(Vector3.ZERO, Vector3(8.0, 0.0, 0.0), graph)
	assert_true(
		route.requires_squeeze(),
		"a route over a WIGGLE edge must advertise the squeeze, or the body arrives uncompressed"
	)
