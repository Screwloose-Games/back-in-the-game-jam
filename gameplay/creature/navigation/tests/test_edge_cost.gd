extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Section 14: cost is expected traversal time plus penalties, in SECONDS.
##
## Section 14 opens by rejecting the obvious implementation -- "do not use clearance as
## the only AStar3D.weight_scale" -- because a weight scale multiplies a distance and
## therefore cannot express "two seconds of squeezing". The consequence the whole
## design wants is `test_astar_prefers_a_long_crawl_to_a_short_squeeze`: a 3 m crevice
## has to lose to a 12 m detour, and it has to lose because of arithmetic rather than
## because of a rule that says crevices are bad.
##
## Getting the unit wrong is silent. A* still returns a path; it is just not the
## cheapest one, and nothing anywhere reports a problem.


func test_normal_cost_is_time_not_distance() -> void:
	var slow := NavigationConfig.new()
	slow.normal_speed = 4.0
	var fast := NavigationConfig.new()
	fast.normal_speed = 8.0

	assert_almost_eq(slow.normal_travel_time(12.0), 3.0, 0.001, "12 m at 4 m/s is 3 s")
	assert_almost_eq(
		fast.normal_travel_time(12.0), 1.5, 0.001, "doubling the speed must halve the cost"
	)


func test_wiggle_costs_more_than_normal_over_the_same_distance() -> void:
	var distance: float = 5.0
	assert_gt(
		_config.wiggle_travel_time(distance),
		_config.normal_travel_time(distance),
		"section 10.2 makes wiggle substantially slower"
	)


func test_wiggle_pays_the_squeeze_transition_once() -> void:
	_config.squeeze_transition_penalty = 3.0
	var bare: float = 6.0 / _config.wiggle_speed
	assert_almost_eq(
		_config.wiggle_travel_time(6.0),
		bare + 3.0,
		0.001,
		"compressing and decompressing is a flat cost per wiggle edge"
	)


func test_the_clearance_term_cannot_dominate() -> void:
	var travel: float = 10.0
	# Section 14 allows clearance "a moderate comfort/caution penalty" and no more. At
	# the shipped weight the worst possible penalty is 15% of the trip.
	var worst: float = _config.clearance_penalty(travel, 0.0)
	assert_almost_eq(worst, travel * _config.clearance_penalty_weight, 0.001)
	assert_lt(worst, travel, "the comfort term must never outweigh the journey itself")


func test_comfortable_clearance_carries_no_penalty() -> void:
	assert_almost_eq(
		_config.clearance_penalty(10.0, _config.comfortable_clearance),
		0.0,
		0.001,
		"an edge with room to spare should cost exactly its traversal time"
	)


## THE A* HEURISTIC MUST NEVER OVERESTIMATE, or the search silently stops returning
## cheapest paths. Using the fastest speed in the model is what keeps it admissible.
func test_the_heuristic_uses_the_fastest_speed_in_the_model() -> void:
	var seconds_per_metre: float = _config.best_seconds_per_metre()
	var fastest: float = maxf(_config.normal_speed, _config.wiggle_speed)

	assert_almost_eq(seconds_per_metre, 1.0 / fastest, 0.0001)
	for distance: float in [1.0, 7.5, 40.0]:
		assert_lte(
			distance * seconds_per_metre,
			_config.normal_travel_time(distance),
			"the heuristic overestimates a normal edge and A* stops being admissible"
		)
		assert_lte(
			distance * seconds_per_metre,
			_config.wiggle_travel_time(distance),
			"the heuristic overestimates a wiggle edge and A* stops being admissible"
		)


## Section 14's headline consequence, and Scenario B's cost half.
##
##     0 --- 1        3 m of WIGGLE, straight across
##     |             \
##     2 --- 3 --- 4 --- 1     12 m of NORMAL, the long way round
##
## The alien must take the long way. If it does not, the cost model is comparing
## distances rather than times somewhere.
func test_astar_prefers_a_long_crawl_to_a_short_squeeze() -> void:
	var graph := NavGraph.new()
	graph.configure(6.0, _config.chunk_size, _config.best_seconds_per_metre())
	var start: int = graph.add_node(Vector3.ZERO, 3.0)
	var goal: int = graph.add_node(Vector3(3.0, 0.0, 0.0), 3.0)
	var detour_a: int = graph.add_node(Vector3(0.0, 0.0, 4.0), 3.0)
	var detour_b: int = graph.add_node(Vector3(3.0, 0.0, 4.0), 3.0)

	_link(graph, start, goal, NavEdge.Type.WIGGLE)
	_link(graph, start, detour_a, NavEdge.Type.NORMAL_VOLUME)
	_link(graph, detour_a, detour_b, NavEdge.Type.NORMAL_VOLUME)
	_link(graph, detour_b, goal, NavEdge.Type.NORMAL_VOLUME)

	var path: PackedInt32Array = graph.find_path_ids(start, goal)
	assert_eq(path.size(), 4, "A* took the 3 m squeeze instead of the 11 m crawl: %s" % [path])
	assert_true(path.has(detour_a) and path.has(detour_b), "expected the route round the outside")


## And the other direction, so the test above is not passing because wiggle edges are
## simply never chosen. A squeeze the alien has no alternative to must still be used.
func test_a_wiggle_edge_is_used_when_it_is_the_only_way() -> void:
	var graph := NavGraph.new()
	graph.configure(6.0, _config.chunk_size, _config.best_seconds_per_metre())
	var start: int = graph.add_node(Vector3.ZERO, 3.0)
	var goal: int = graph.add_node(Vector3(3.0, 0.0, 0.0), 1.0)
	_link(graph, start, goal, NavEdge.Type.WIGGLE)

	var path: PackedInt32Array = graph.find_path_ids(start, goal)
	assert_eq(path.size(), 2, "the only route in the graph was not taken")


func _link(graph: NavGraph, from: int, to: int, type: NavEdge.Type) -> void:
	var distance: float = graph.node_at(from).position.distance_to(graph.node_at(to).position)
	var cost: float = (
		_config.wiggle_travel_time(distance)
		if type == NavEdge.Type.WIGGLE
		else _config.normal_travel_time(distance)
	)
	graph.add_edge(NavEdge.make(from, to, type, distance, 1.0, cost))
