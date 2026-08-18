extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 9: how much one completed inspection is allowed to learn (navigation.md
## sections 29, 30, 40.6).
##
## THE BUG THIS SUITE EXISTS FOR IS BEHAVIOURAL AND NOT AN ASSERTION FAILURE ANYWHERE.
## `_observe_one` plants a suspicion every `node_separation` of unbelieved free space and
## each one is a section 29 stop, so a relearn that covers a `relearn_radius` BALL leaves
## the alien stopping six times to investigate one 20 m tunnel -- correctly, by every rule
## the knowledge suite checks, and looking exactly like a creature that cannot remember
## what it was looking at ten seconds ago.
##
## The fix is that one continuous section is one thing to investigate, and "continuous"
## means through world EDGES. Section 13.2 validates those with swept shapes, so following
## them says "the body can get from here to there at this size"; clustering the suspicion
## points by distance instead would join two of them a metre apart through a wall.


func test_a_ball_relearn_still_learns_only_the_ball() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_region(world, Vector3.ZERO, _config.relearn_radius, 0.0)
	assert_eq(knowledge.node_state(1), NavKnowledgeState.State.KNOWN, "4 m is inside a 6 m ball")
	assert_eq(
		knowledge.node_state(2),
		NavKnowledgeState.State.UNKNOWN,
		"learn_region is the radius primitive and stays one"
	)


func test_one_inspection_resolves_the_whole_connected_section() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	var update: NavKnowledgeUpdate = knowledge.learn_connected_region(
		world, Vector3.ZERO, _config, 0.0
	)
	assert_eq(
		knowledge.project(_config).node_count(),
		6,
		"one continuous passage is one thing to investigate, not one per relearn_radius"
	)
	assert_false(update.truncated, "20 m is well inside the default reach")


func test_the_far_end_was_looked_down_rather_than_walked() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(knowledge.node_state(1), NavKnowledgeState.State.KNOWN, "inside the seed ball")
	assert_eq(
		knowledge.node_state(5),
		NavKnowledgeState.State.PARTIALLY_EXPLORED,
		"the alien saw down the passage from its mouth; it has not been there"
	)
	assert_eq(
		knowledge.edge_state(4, 5),
		NavKnowledgeState.State.PARTIALLY_EXPLORED,
		"an edge is no better known than the nodes it joins"
	)


func test_the_flood_stops_at_what_was_already_believed() -> void:
	var world: NavGraph = _passage(7)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_node(world.node_at(3), 0.0, NavKnowledgeState.State.KNOWN)

	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(
		knowledge.node_state(4),
		NavKnowledgeState.State.UNKNOWN,
		"the flood follows UNKNOWN geometry; a belief in the way is where it ends"
	)


func test_an_existing_memory_is_not_downgraded_by_a_glimpse() -> void:
	var world: NavGraph = _passage(7)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_node(world.node_at(3), 0.0, NavKnowledgeState.State.KNOWN)

	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(
		knowledge.node_state(3),
		NavKnowledgeState.State.KNOWN,
		"having been somewhere is not unlearned by looking at it from further away"
	)


func test_walking_the_section_later_upgrades_what_was_glimpsed() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(knowledge.node_state(5), NavKnowledgeState.State.PARTIALLY_EXPLORED)

	knowledge.learn_connected_region(world, world.node_at(5).position, _config, 1.0)
	assert_eq(
		knowledge.node_state(5),
		NavKnowledgeState.State.KNOWN,
		"the guard against downgrades must not also block the upgrade"
	)
	assert_eq(knowledge.edge_state(4, 5), NavKnowledgeState.State.KNOWN)


func test_a_stale_memory_is_a_wall_and_not_a_doorway() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	knowledge.learn_node(world.node_at(2), 0.0, NavKnowledgeState.State.STALE)

	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(
		knowledge.node_state(4),
		NavKnowledgeState.State.UNKNOWN,
		"age() turns every memory STALE eventually; a flood through STALE reveals the cave"
	)


func test_suspicions_along_the_whole_section_are_cleared() -> void:
	var world: NavGraph = _passage(6)
	var knowledge: NavKnowledgeGraph = _knowledge()
	for at: Vector3 in [Vector3.ZERO, Vector3(6.0, 0.0, 0.0), Vector3(12.0, 0.0, 0.0)]:
		knowledge.observe_geometry_batch([_free_at(at)], _config)
	assert_eq(knowledge.suspected_openings().size(), 3, "fixture needs suspicions to clear")

	knowledge.learn_connected_region(world, Vector3.ZERO, _config, 0.0)
	assert_eq(
		knowledge.suspected_openings().size(),
		0,
		"a suspicion beside believed geometry is a stop the alien makes for nothing"
	)


func test_the_node_budget_bounds_one_inspection() -> void:
	var world: NavGraph = _passage(10)
	var knowledge: NavKnowledgeGraph = _knowledge()
	_config.relearn_max_nodes = 4

	var update: NavKnowledgeUpdate = knowledge.learn_connected_region(
		world, Vector3.ZERO, _config, 0.0
	)
	assert_eq(knowledge.project(_config).node_count(), 4, "section 32 gets a say in this")
	assert_true(update.truncated, "a bound that is hit silently reads as 'that was all of it'")


func test_the_reach_bounds_one_inspection() -> void:
	var world: NavGraph = _passage(10)
	var knowledge: NavKnowledgeGraph = _knowledge()
	_config.relearn_connected_radius = 10.0

	var update: NavKnowledgeUpdate = knowledge.learn_connected_region(
		world, Vector3.ZERO, _config, 0.0
	)
	assert_eq(knowledge.node_state(2), NavKnowledgeState.State.PARTIALLY_EXPLORED, "8 m, inside")
	assert_eq(knowledge.node_state(3), NavKnowledgeState.State.UNKNOWN, "12 m, outside")
	assert_true(update.truncated)


# ----- fixtures -----


## A straight run of `count` nodes 4 m apart along +X, each joined to the next. Node ids
## are the indices, so a test can name the far end without looking it up.
func _passage(count: int) -> NavGraph:
	var positions: Array = []
	var pairs: Array = []
	for step: int in count:
		positions.append(Vector3(step * 4.0, 0.0, 0.0))
		if step > 0:
			pairs.append([step - 1, step])
	return _hand_graph(positions, pairs)


func _knowledge() -> NavKnowledgeGraph:
	return NavKnowledgeGraph.new()
