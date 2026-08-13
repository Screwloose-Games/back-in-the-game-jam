extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## NavGraphBuilder.begin_flood: section 12.1's candidate set reached by REACHABILITY.
##
## The flood exists because `shape_fits` and `clearance_at` are overlap tests and a concave
## trimesh has no interior, so the section 12.1 sweep prefers rock on any real level. These
## cases are about the enumeration and nothing else -- decimation, edge validation and cost
## are `test_graph_builder.gd` and `test_edge_validation.gd`, and the flood is required not
## to touch any of them.
##
## THE FIRST CASE IS THE LOAD-BEARING ONE. Over a single connected pocket of air the flood
## and the sweep must produce the SAME GRAPH, because the only thing that differs is which
## cells get visited. Every other case here is about a cell the two legitimately disagree
## about.

## Where FakeNavigationProbe's `_open_room` default has its most open air.
const ROOM_SEED := Vector3(10.0, 4.0, 10.0)


func _flood_patcher() -> NavGraphPatcher:
	var patcher := NavGraphPatcher.new()
	patcher.use_flood = true
	return patcher


## Runs a queued patch to completion. Bounded so a bug cannot hang the suite.
func _patch_until_done(patcher: NavGraphPatcher, graph: NavGraph) -> NavPatchResult:
	for _step: int in 4000:
		var result: NavPatchResult = patcher.step(graph, 256, _config, _probe)
		if result != null:
			return result
		if not patcher.has_work():
			return null
	return null


func _positions(graph: NavGraph) -> Array:
	var found: Array = []
	for id: Variant in graph.node_ids():
		found.append(graph.node_at(id).position)
	found.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			if a.x != b.x:
				return a.x < b.x
			if a.y != b.y:
				return a.y < b.y
			return a.z < b.z
	)
	return found


## THE EQUIVALENCE PROPERTY, and the strongest single assertion about the flood.
##
## One room is one connected pocket of air, so every candidate the sweep finds is reachable
## from any seed inside it. Identical graphs is therefore not a coincidence to be tolerated
## but the definition of the flood being correct: it changes which cells are LOOKED at, and
## nothing about which ones qualify.
func test_a_flood_and_a_sweep_of_one_room_agree_exactly() -> void:
	var room: AABB = _open_room()
	var swept: NavGraph = _bake(room)
	var flooded: NavGraph = _flood(room, [ROOM_SEED])

	assert_gt(swept.node_count(), 0, "the fixture room should produce nodes at all")
	assert_eq(flooded.node_count(), swept.node_count(), "flood and sweep node counts")
	assert_eq(_positions(flooded), _positions(swept), "flood and sweep node positions")


## Air the flood cannot reach is air that does not exist, and that is the point rather than
## a limitation. A sealed cavity's nodes were never routable; under the sweep they were an
## isolated component nothing could ever attach to.
func test_a_sealed_cavity_is_sampled_by_the_sweep_and_not_by_the_flood() -> void:
	var region := AABB(Vector3.ZERO, Vector3(28.0, 8.0, 20.0))
	_probe.add_room(region)
	# A hollow shell floating inside the big room: 4 m of air behind 2 m of solid on every
	# side. Exactly one lattice point lands in it, at (14, 4, 10).
	var cavity := AABB(Vector3(12.0, 2.0, 8.0), Vector3(4.0, 4.0, 4.0))
	_probe.add_room(cavity)

	var swept: NavGraph = _bake(region)
	var flooded: NavGraph = _flood(region, [Vector3(2.0, 4.0, 2.0)])

	assert_eq(_nodes_in(swept, cavity).size(), 1, "the sweep samples the sealed cavity")
	assert_eq(_nodes_in(flooded, cavity).size(), 0, "the flood cannot reach the sealed cavity")
	assert_gt(flooded.node_count(), 0, "the room around the cavity is still baked")


## Section 43 Scenario G, at unit scale, and the reason `flood_passage_radius` is a separate
## number from the body envelope.
##
## A 1 m corridor has 0.5 m of clearance: the 0.25 m passage probe crosses it and the
## squeezed body does not. So the flood must reach the far chamber and leave no node IN the
## corridor, and section 13.2 must then refuse every edge across it. A flood gated on
## candidacy would never reach the far chamber at all -- which passes the edge assertion for
## entirely the wrong reason, and is what
## `verify_navigation_runtime._check_chamber_c_isolated` exists to catch.
func test_the_flood_crosses_a_corridor_no_body_fits_through() -> void:
	var region: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var far_chamber := AABB(Vector3(16.0, 0.0, 0.0), Vector3(10.0, 8.0, 12.0))
	var slot: AABB = _corridor_volume(IMPASSABLE_CORRIDOR)

	var flooded: NavGraph = _flood(region, [Vector3(4.0, 4.0, 4.0)])

	assert_gt(
		_nodes_in(flooded, far_chamber).size(),
		0,
		"the far chamber must be sampled, or the edge assertion below proves nothing"
	)
	assert_eq(_nodes_in(flooded, slot).size(), 0, "the corridor itself holds no node")
	assert_eq(_edges_through(flooded, slot).size(), 0, "no edge may cross a 1 m corridor")


## Refusing loudly. A caller who seeded the wrong point and a cave with no air produce the
## same empty graph, so the distinction has to reach `failures` -- which is the one thing
## both CreatureNavigation.bake and NavGraphPatcher._start_next already log.
func test_a_seed_buried_in_rock_is_reported_rather_than_ignored() -> void:
	# Deep inside the divider's lower slab, and far enough in that none of the eight lattice
	# corners `_seed_one` falls back to is in air either.
	var region: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var builder: NavGraphBuilder = _flood_builder(region, [Vector3(13.0, 1.0, 5.0)])

	assert_eq(builder.seeds_resolved, 0, "a seed inside the divider must not resolve")
	assert_eq(builder.seeds_rejected, 1, "and must be counted as rejected")
	assert_gt(builder.failures.size(), 0, "a flood that reached nothing must say so")
	assert_eq(builder.graph.node_count(), 0, "and must not bake a partial graph")


## Section 32's budget must not change the answer. The flood carries a frontier, a
## measurement cache and a neighbour index across `step()` calls, and any of the three
## resuming wrongly shows up here rather than in a shipped cave.
func test_stepping_a_flood_by_a_small_budget_gives_the_same_graph() -> void:
	var room: AABB = _open_room()
	var whole: NavGraph = _flood(room, [ROOM_SEED])

	var stepped := NavGraphBuilder.new()
	stepped.begin_flood(room, PackedVector3Array([ROOM_SEED]), _config, _probe)
	assert_eq(stepped.failures.size(), 0, "the fixture should flood: %s" % stepped.failures)
	var guard: int = 0
	while not stepped.step(3):
		guard += 1
		assert_lt(guard, 200000, "a budgeted flood should terminate")

	assert_eq(_positions(stepped.graph), _positions(whole), "budgeted and unbudgeted flood")


## Section 43 Scenario F, flooded: the player mines into space the bake never reached.
##
## THE SEED IS THE WHOLE TEST. There are no existing nodes inside the cavity to seed from --
## that is what "never reached" means -- so the only thing the patcher knows is air is the
## material that just stopped being rock. Seeding from the GROWN region's centre instead
## would put the seed 8 m out from the hole, routinely still in stone, and the patch would
## silently find nothing while reporting success.
func test_a_flood_patch_reaches_a_pocket_the_bake_could_not() -> void:
	var region := AABB(Vector3.ZERO, Vector3(28.0, 8.0, 20.0))
	_probe.add_room(region)
	var cavity := AABB(Vector3(12.0, 2.0, 8.0), Vector3(4.0, 4.0, 4.0))
	var shell_at: int = _probe.solids.size()
	_probe.add_room(cavity)

	var graph: NavGraph = _flood(region, [Vector3(2.0, 4.0, 2.0)])
	assert_eq(_nodes_in(graph, cavity).size(), 0, "the sealed cavity starts unreachable")

	# `add_room` emits floor, ceiling, -x, +x, -z, +z. Mine the -x wall out.
	var mined: AABB = _probe.solids[shell_at + 2]
	_probe.solids.remove_at(shell_at + 2)

	var patcher: NavGraphPatcher = _flood_patcher()
	patcher.mark_dirty(mined, _config)
	_patch_until_done(patcher, graph)

	assert_eq(_nodes_in(graph, cavity).size(), 1, "the patch must find the opened cavity")


## Invariant 6, from the flood's side. Mining is subtractive, so a patch may add and may
## improve and may never take anything away -- and the property has to survive the sampler
## being swapped, because a flood that reaches less than last time is exactly how it would
## be broken.
func test_a_flood_patch_only_ever_adds() -> void:
	var region: AABB = _corridor_cave(WIDE_CORRIDOR)
	var graph: NavGraph = _flood(region, [Vector3(4.0, 4.0, 4.0)])
	var nodes_before: int = graph.node_count()
	var edges_before: int = graph.all_edges().size()
	assert_gt(edges_before, 0, "the fixture should bake edges to preserve")

	var patcher: NavGraphPatcher = _flood_patcher()
	patcher.mark_dirty(_corridor_volume(WIDE_CORRIDOR), _config)
	_patch_until_done(patcher, graph)

	assert_gte(graph.node_count(), nodes_before, "a patch never removes a node")
	assert_gte(graph.all_edges().size(), edges_before, "a patch never removes an edge")


## The flood must not inherit the sweep's truncation flag, which counts the region's VOLUME.
## A level-sized region trips it on volume alone, so every bake would push the "part of the
## region was not covered" warning while the flood happily visited every cell there was.
func test_a_flood_over_a_huge_region_does_not_report_itself_truncated() -> void:
	_open_room()
	# Ten million lattice points by volume, twenty times MAX_LATTICE_SAMPLES -- and about a
	# thousand cells of actual air.
	var region := AABB(Vector3(-200.0, -200.0, -200.0), Vector3(400.0, 400.0, 400.0))
	var builder: NavGraphBuilder = _flood_builder(region, [ROOM_SEED])

	assert_false(builder.truncated, "a flood is bounded by the air it finds, not by volume")
	assert_gt(builder.graph.node_count(), 0, "and still bakes the room")
