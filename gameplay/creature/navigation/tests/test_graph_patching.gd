extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 7: local patching after terrain changes (navigation.md sections 24, 25).
##
## INVARIANT 6 IS THE ASSERTION THAT MATTERS. "Subtractive terrain cannot invalidate an
## existing authoritative navigation edge" -- so a patch may add and may improve, and may
## never take anything away. The failure mode if it does is a route that vanishes while
## the alien is halfway along it, which reads as a pathfinding bug and is nothing of the
## kind.
##
## SECTION 24.3 IS THE OTHER ONE. Runtime nodes must land where bake-time nodes would, so
## a cave that has been mined ten times still has the graph a single bake would have
## produced. That is checked here as a property -- every node sits on the lattice -- rather
## than by comparing two bakes, because the property is what section 24.3 actually asks
## for.


func _patcher() -> NavGraphPatcher:
	return NavGraphPatcher.new()


## Runs a queued patch to completion. Bounded so a bug cannot hang the suite.
func _patch_until_done(patcher: NavGraphPatcher, graph: NavGraph) -> NavPatchResult:
	for _step: int in 4000:
		var result: NavPatchResult = patcher.step(graph, 256, _config, _probe)
		if result != null:
			return result
		if not patcher.has_work():
			return null
	return null


## A two-chamber cave joined by a corridor of `bore` metres.
func _two_chambers(bore: float) -> AABB:
	var region := _corridor_cave(bore)
	return region


# ----- section 24.3: patched nodes land on the bake lattice -----


func test_every_patched_node_sits_on_the_candidate_lattice() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var before: int = graph.node_count()

	var patcher: NavGraphPatcher = _patcher()
	patcher.mark_dirty(region, _config)
	_patch_until_done(patcher, graph)

	var pitch: float = _config.candidate_spacing
	for id: Variant in graph.node_ids():
		if int(id) < before:
			continue
		var at: Vector3 = graph.node_at(id).position
		for axis: int in 3:
			assert_almost_eq(
				fposmod(at[axis], pitch),
				0.0,
				0.001,
				"section 24.3: a patch may only ever insert lattice points, never a dig centre"
			)


func test_patching_does_not_renumber_existing_nodes() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var kept: Dictionary = {}
	for id: Variant in graph.node_ids():
		kept[int(id)] = graph.node_at(id).position

	var patcher: NavGraphPatcher = _patcher()
	patcher.mark_dirty(region, _config)
	_patch_until_done(patcher, graph)

	for id: Variant in kept:
		assert_true(graph.has_node(id), "node %d disappeared" % id)
		assert_eq(
			graph.node_at(id).position,
			kept[id],
			"section 27 keys the alien's memory by node id; renumbering erases it"
		)


# ----- Invariant 6 -----


func test_a_patch_never_removes_an_edge() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var before: Array = []
	for edge: NavEdge in graph.all_edges():
		before.append(NavAStar.key_for(edge.from_id, edge.to_id))

	var patcher: NavGraphPatcher = _patcher()
	patcher.mark_dirty(region, _config)
	_patch_until_done(patcher, graph)

	for key: Vector2i in before:
		assert_not_null(
			graph.edge_between(key.x, key.y),
			"mining is subtractive, so edge %s cannot have become false" % key
		)


func test_an_edge_may_not_be_downgraded_to_a_squeeze() -> void:
	var graph: NavGraph = _hand_graph([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)], [[0, 1]])
	assert_false(
		graph.upgrade_edge(0, 1, NavEdge.Type.WIGGLE, 99.0),
		"Invariant 6 is a property of the API, not a rule the caller has to remember"
	)
	assert_eq(graph.edge_between(0, 1).type, NavEdge.Type.NORMAL_VOLUME)


func test_an_edge_may_be_upgraded_out_of_a_squeeze() -> void:
	var graph: NavGraph = _hand_graph([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)], [[0, 1]])
	graph.edge_between(0, 1).type = NavEdge.Type.WIGGLE
	graph.edge_between(0, 1).base_cost = 40.0
	assert_true(graph.upgrade_edge(0, 1, NavEdge.Type.NORMAL_VOLUME, 1.0))
	assert_eq(
		graph.edge_between(0, 1).type,
		NavEdge.Type.NORMAL_VOLUME,
		"section 43 Scenario F: a widened crevice stops being a squeeze"
	)
	assert_almost_eq(graph.edge_between(0, 1).base_cost, 1.0, 0.001)


# ----- section 25 -----


func test_only_the_patched_chunk_has_its_revision_bumped() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var patcher: NavGraphPatcher = _patcher()
	var dig := AABB(Vector3(2.0, 2.0, 2.0), Vector3(2.0, 2.0, 2.0))
	patcher.mark_dirty(dig, _config)
	var result: NavPatchResult = _patch_until_done(patcher, graph)

	assert_not_null(result, "the patch never completed")
	assert_eq(graph.revisions.revision_of(result.chunk), 1)
	assert_eq(
		graph.revisions.revision_of(result.chunk + Vector3i(9, 9, 9)),
		0,
		"a chunk nothing happened in must not look stale"
	)


func test_the_graph_revision_follows_the_highest_chunk() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var patcher: NavGraphPatcher = _patcher()
	patcher.mark_dirty(AABB(Vector3(2.0, 2.0, 2.0), Vector3(2.0, 2.0, 2.0)), _config)
	_patch_until_done(patcher, graph)
	assert_eq(graph.terrain_revision, graph.revisions.highest())
	assert_gt(graph.terrain_revision, 0)


func test_an_untouched_graph_reports_revision_zero() -> void:
	assert_eq(NavChunkRevisions.new().revision_of(Vector3i.ZERO), 0)
	assert_eq(NavChunkRevisions.new().highest(), 0)


# ----- Scenario G: a player-only passage stays impassable -----


func test_patching_a_slot_too_small_for_the_alien_creates_no_edge() -> void:
	var region: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var patcher: NavGraphPatcher = _patcher()
	patcher.mark_dirty(region, _config)
	_patch_until_done(patcher, graph)

	assert_eq(
		_edges_through(graph, _corridor_volume(IMPASSABLE_CORRIDOR)).size(),
		0,
		"Scenario G: re-running the builder locally must not invent what a bake refused"
	)


# ----- the frame budget -----


## COST SCALES WITH THE PATCHED REGION, NOT WITH THE CAVE. That is the property section
## 24.2 is really asking for, and it is the one that stays true as the cave grows.
##
## Comparing a patch against the original bake is tempting and wrong at this scale: a
## dirty region is grown by `edge_search_radius` before it is queued -- new nodes have to
## be able to see the graph around them -- so an 8 m margin around a 2 m dig is an 18 m
## box, which in a test cave this size is larger than the cave. The comparison below is
## between two patches instead, so the margin cancels out.
func test_patch_cost_scales_with_the_region_rather_than_the_cave() -> void:
	var region: AABB = _two_chambers(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)

	_probe.sweep_calls = 0
	var small: NavGraphPatcher = _patcher()
	small.mark_dirty(AABB(Vector3(2.0, 2.0, 2.0), Vector3(1.0, 1.0, 1.0)), _config)
	_patch_until_done(small, graph)
	var small_sweeps: int = _probe.sweep_calls

	_probe.sweep_calls = 0
	var large: NavGraphPatcher = _patcher()
	large.mark_dirty(region, _config)
	_patch_until_done(large, graph)

	assert_lt(
		small_sweeps,
		_probe.sweep_calls,
		"a patch that costs the same whatever it covers is not local at all"
	)


func test_no_work_queued_means_no_work_done() -> void:
	var graph: NavGraph = _bake(_two_chambers(WIDE_CORRIDOR))
	var patcher: NavGraphPatcher = _patcher()
	assert_false(patcher.has_work())
	assert_null(patcher.step(graph, 256, _config, _probe))
