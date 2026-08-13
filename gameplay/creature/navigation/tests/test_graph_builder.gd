extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Sections 12.1 and 12.2: the candidate lattice and clearance-priority decimation.
##
## The decimation ORDER is the part worth protecting. Sorting candidates by clearance
## descending before the greedy accept is what makes the survivors cluster at tunnel
## centres and chamber centres -- a rough medial skeleton. Accept them in lattice order
## instead and every count below is identical while the graph becomes an arbitrary grid
## sample hugging whichever wall the scan reached first. `test_decimation_keeps_the_most_open_candidate`
## is the only thing here that can tell those two apart.


func test_no_node_is_tighter_than_the_squeezed_body() -> void:
	var graph: NavGraph = _bake(_open_room())
	var floor_clearance: float = _config.clearance_profile.min_traversal_clearance()

	assert_true(graph.node_count() > 0, "an open room produced no nodes")
	for id: Variant in graph.node_ids():
		var node: NavNode = graph.node_at(id)
		assert_true(
			node.clearance >= floor_clearance,
			(
				"node at %s has clearance %.2f, below the %.2f the squeezed body needs"
				% [node.position, node.clearance, floor_clearance]
			)
		)


func test_no_node_is_inside_terrain() -> void:
	var graph: NavGraph = _bake(_open_room())
	for id: Variant in graph.node_ids():
		var at: Vector3 = graph.node_at(id).position
		assert_true(_probe.free_distance(at) > 0.0, "node at %s is inside solid terrain" % at)


func test_decimation_enforces_node_separation() -> void:
	var graph: NavGraph = _bake(_open_room())
	var ids: Array = graph.node_ids()

	for outer: int in ids.size():
		for inner: int in range(outer + 1, ids.size()):
			var a: Vector3 = graph.node_at(ids[outer]).position
			var b: Vector3 = graph.node_at(ids[inner]).position
			assert_true(
				a.distance_to(b) >= _config.node_separation - 0.001,
				(
					"nodes at %s and %s are %.2f apart, inside node_separation"
					% [a, b, a.distance_to(b)]
				)
			)


## THE ONE TEST THAT CAN TELL SECTION 12.2 FROM A PLAIN GRID SAMPLE.
##
## Every candidate that survived the clearance floor but did not become a node must
## have been rejected by an accepted node that is AT LEAST AS OPEN as it is. That is
## exactly what sorting by clearance descending guarantees, and exactly what accepting
## in lattice order does not.
func test_decimation_keeps_the_most_open_candidate() -> void:
	var region: AABB = _open_room()
	var graph: NavGraph = _bake(region)
	var profile: ClearanceProfile = _config.clearance_profile
	var uncovered: int = 0
	var outranked: int = 0

	for point: Vector3 in _lattice_points(region):
		var clearance: float = _probe.clearance_at(
			point, _config.world_mask, _config.clearance_ceiling, _config.clearance_steps
		)
		if clearance < profile.min_traversal_clearance():
			continue
		var nearby: PackedInt32Array = graph.find_nearby_nodes(point, _config.node_separation)
		if nearby.is_empty():
			uncovered += 1
			continue
		var best: float = 0.0
		for id: int in nearby:
			best = maxf(best, graph.node_at(id).clearance)
		if best < clearance - 0.001:
			outranked += 1

	assert_eq(
		uncovered, 0, "%d traversable candidates have no node within node_separation" % uncovered
	)
	assert_eq(
		outranked,
		0,
		(
			"%d candidates were rejected by nodes MORE CRAMPED than themselves; decimation is not sorting by clearance"
			% outranked
		)
	)


func test_bake_is_deterministic() -> void:
	var region: AABB = _corridor_cave(WIDE_CORRIDOR)
	var first: NavGraph = _bake(region)
	var second: NavGraph = _bake(region)

	assert_eq(first.node_count(), second.node_count(), "two bakes disagree on node count")
	assert_eq(first.edge_count(), second.edge_count(), "two bakes disagree on edge count")
	for id: Variant in first.node_ids():
		assert_eq(
			first.node_at(id).position,
			second.node_at(id).position,
			"node %d moved between two bakes of identical terrain" % id
		)


## Section 32's frame budget must not change the answer, only when it arrives. A bake
## spread over many small steps and a bake done in one go are the same graph.
func test_stepping_by_a_small_budget_gives_the_same_graph() -> void:
	var region: AABB = _corridor_cave(WIDE_CORRIDOR)
	var whole: NavGraph = _bake(region)

	var stepped := NavGraphBuilder.new()
	stepped.begin(region, _config, _probe)
	var guard: int = 0
	while not stepped.step(3) and guard < 100000:
		guard += 1
	assert_true(guard < 100000, "a 3-query budget never finished the bake")

	assert_eq(stepped.graph.node_count(), whole.node_count(), "budgeted bake found different nodes")
	assert_eq(stepped.graph.edge_count(), whole.edge_count(), "budgeted bake found different edges")


func test_a_region_larger_than_the_lattice_cap_reports_truncation() -> void:
	_probe.add_room(AABB(Vector3.ZERO, Vector3(40.0, 40.0, 40.0)))
	var huge := AABB(Vector3.ZERO, Vector3(4000.0, 4000.0, 4000.0))
	var builder := NavGraphBuilder.new()
	builder.begin(huge, _config, _probe)

	assert_true(
		builder.truncated,
		"a region needing more than MAX_LATTICE_SAMPLES points must say so rather than silently cover part of the cave"
	)


func test_an_invalid_config_refuses_to_bake() -> void:
	# Section 32's budget is not the only way to waste a frame. A zero world mask makes
	# every cast report clear, so the bake would connect every node through solid rock.
	_config.world_mask = 0
	var builder := NavGraphBuilder.new()
	builder.begin(_open_room(), _config, _probe)

	assert_true(builder.failures.size() > 0, "a zero world_mask should refuse to bake")
	assert_eq(builder.stage, NavGraphBuilder.Stage.IDLE, "a refused bake must not start sampling")


func test_an_unbound_probe_refuses_to_bake() -> void:
	var builder := NavGraphBuilder.new()
	builder.begin(_open_room(), _config, NavigationProbe.new())

	assert_true(builder.failures.size() > 0, "an unbound probe should refuse to bake")


# ----- helpers -----


## The same lattice the builder walks: world-space multiples of candidate_spacing, not
## offsets from the region corner. See NavGraphBuilder._plan_lattice for why.
func _lattice_points(region: AABB) -> Array:
	var spacing: float = _config.candidate_spacing
	var points: Array = []
	var start := Vector3(
		ceilf(region.position.x / spacing) * spacing,
		ceilf(region.position.y / spacing) * spacing,
		ceilf(region.position.z / spacing) * spacing
	)
	var at: Vector3 = start
	while at.x <= region.end.x:
		at.y = start.y
		while at.y <= region.end.y:
			at.z = start.z
			while at.z <= region.end.z:
				points.append(at)
				at.z += spacing
			at.y += spacing
		at.x += spacing
	return points
