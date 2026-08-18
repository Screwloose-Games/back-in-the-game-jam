extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 8: the alien's own map (navigation.md sections 27, 28, Invariants 8 and 9).
##
## INVARIANT 8 IS THE ONE WORTH BREAKING A BUILD OVER: "updating the world graph does not
## automatically update alien knowledge". Every other assertion here fails loudly if it
## goes wrong. That one fails by the alien simply becoming better informed -- it routes
## through the passage the player just mined, immediately, and looks like a working
## navigation system to anyone who is not specifically checking.


func _knowledge() -> NavKnowledgeGraph:
	return NavKnowledgeGraph.new()


func _two_chamber_graph() -> NavGraph:
	return _bake(_corridor_cave(WIDE_CORRIDOR))


# ----- Invariant 8 -----


func test_patching_the_world_leaves_belief_untouched() -> void:
	var region: AABB = _corridor_cave(WIDE_CORRIDOR)
	var world: NavGraph = _bake(region)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var before: Dictionary = knowledge.debug_state()

	var patcher := NavGraphPatcher.new()
	patcher.mark_dirty(region, _config)
	for _step: int in 4000:
		if patcher.step(world, 256, _config, _probe) != null:
			break
		if not patcher.has_work():
			break

	assert_eq(
		knowledge.debug_state(),
		before,
		"the world changed and the alien was not told; section 28 says it must not notice"
	)


func test_a_believed_graph_and_a_world_graph_are_the_same_type() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	assert_true(
		is_instance_of(knowledge.project(_config), NavGraph),
		"Invariant 9's whole mechanism: route/ cannot tell the difference"
	)


func test_projection_preserves_world_node_ids() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var believed: NavGraph = knowledge.project(_config)
	for id: Variant in world.node_ids():
		assert_true(
			believed.has_node(id),
			"section 27 keys memory by world node id; a renumbered projection breaks routes"
		)
		assert_eq(believed.node_at(id).position, world.node_at(id).position)


func test_a_route_can_be_planned_against_belief_alone() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var believed: NavGraph = knowledge.project(_config)
	var route: NavRoute = _planner().plan(Vector3(2.0, 2.0, 2.0), Vector3(2.0, 2.0, 18.0), believed)
	assert_ne(route.status, NavRoute.Status.UNREACHABLE, "not one line of route/ changed")


# ----- section 40.6 -----


func test_a_suspected_opening_is_not_routable() -> void:
	var knowledge: NavKnowledgeGraph = _knowledge()
	var update: NavKnowledgeUpdate = knowledge.observe_geometry_batch(
		[_free_at(Vector3(30.0, 0.0, 0.0))], _config
	)
	assert_eq(update.suspected_openings.size(), 1, "free space where nothing was believed")
	assert_eq(
		knowledge.project(_config).node_count(),
		0,
		"section 40.6: a discovered opening must not become routable on the spot"
	)


func test_suspected_is_not_a_routable_state() -> void:
	assert_false(NavKnowledgeState.is_routable(NavKnowledgeState.State.SUSPECTED))
	assert_false(NavKnowledgeState.is_routable(NavKnowledgeState.State.UNKNOWN))
	assert_false(NavKnowledgeState.is_routable(NavKnowledgeState.State.INVALID))
	assert_true(NavKnowledgeState.is_routable(NavKnowledgeState.State.KNOWN))
	assert_true(
		NavKnowledgeState.is_routable(NavKnowledgeState.State.STALE),
		"Scenario J: a doubted route is expensive, not forbidden"
	)


func test_the_same_opening_is_only_suspected_once() -> void:
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.observe_geometry_batch([_free_at(Vector3(30.0, 0.0, 0.0))], _config)
	var again: NavKnowledgeUpdate = knowledge.observe_geometry_batch(
		[_free_at(Vector3(30.5, 0.0, 0.0))], _config
	)
	assert_eq(again.suspected_openings.size(), 0, "one opening, not one per observation")


# ----- section 29's mismatch detection -----


func test_solid_where_passage_was_believed_is_a_contradiction() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var somewhere: Vector3 = world.node_at(world.node_ids()[0]).position

	var update: NavKnowledgeUpdate = knowledge.observe_geometry_batch(
		[_solid_at(somewhere)], _config
	)
	assert_eq(update.contradictions.size(), 1)
	assert_eq(
		knowledge.node_state(world.node_ids()[0]),
		NavKnowledgeState.State.STALE,
		"section 29 wants this inspected, not silently deleted -- STALE, never INVALID"
	)


func test_a_contradiction_casts_doubt_on_the_edges_as_well() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var first: int = world.node_ids()[0]
	var neighbours: PackedInt32Array = world.get_neighbors(first)
	assert_gt(neighbours.size(), 0, "fixture needs a connected node")

	knowledge.observe_geometry_batch([_solid_at(world.node_at(first).position)], _config)
	assert_eq(
		knowledge.edge_state(first, neighbours[0]),
		NavKnowledgeState.State.STALE,
		"a distrusted node joined by trusted edges routes straight through the doubt"
	)


func test_a_clearance_report_too_tight_for_the_alien_reads_as_solid() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var somewhere: Vector3 = world.node_at(world.node_ids()[0]).position
	var update: NavKnowledgeUpdate = knowledge.observe_geometry_batch(
		[_clearance_at(somewhere, 0.1)], _config
	)
	assert_eq(update.contradictions.size(), 1, "0.1 m is not passable by any alien body")


# ----- Scenario J: stale is expensive, not forbidden -----


func test_a_stale_edge_costs_more_but_still_exists() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var edge: NavEdge = world.all_edges()[0]
	var honest: float = knowledge.project(_config).edge_between(edge.from_id, edge.to_id).base_cost

	knowledge.observe_geometry_batch([_solid_at(world.node_at(edge.from_id).position)], _config)
	var doubted: NavEdge = knowledge.project(_config).edge_between(edge.from_id, edge.to_id)
	assert_not_null(doubted, "an alien that refuses everything it doubts never moves again")
	assert_gt(doubted.base_cost, honest, "but it should prefer a way it is sure of")


func test_a_questionable_edge_is_penalised_without_being_removed() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var edge: NavEdge = world.all_edges()[0]
	var honest: float = knowledge.project(_config).edge_between(edge.from_id, edge.to_id).base_cost

	knowledge.mark_edge_questionable(edge.from_id, edge.to_id, 1.0, _config)
	var doubted: NavEdge = knowledge.project(_config).edge_between(edge.from_id, edge.to_id)
	assert_not_null(doubted, "section 40.2 is a preference, not a deletion")
	assert_gt(doubted.base_cost, honest)


# ----- caching -----


func test_the_projection_is_cached_until_something_changes() -> void:
	var world: NavGraph = _two_chamber_graph()
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_all(world, 0.0)
	var first: NavGraph = knowledge.project(_config)
	assert_same(first, knowledge.project(_config), "section 32: event driven, not per frame")

	knowledge.mark_edge_questionable(
		world.all_edges()[0].from_id, world.all_edges()[0].to_id, 1.0, _config
	)
	assert_not_same(first, knowledge.project(_config), "a stale cache is a stale alien")
