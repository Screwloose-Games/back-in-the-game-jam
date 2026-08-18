class_name NavGraphPatcher
extends RefCounted

## Rebuilds navigation locally after terrain changes (navigation.md section 24).
##
## "DO NOT RE-BAKE THE ENTIRE GRAPH" is section 24.2's instruction, and the reason is not
## only cost. A full rebake renumbers every node, which throws away the alien's knowledge
## (section 27 keys memory by world node id), invalidates every route in flight, and does
## it at the exact moment the player is mining and the alien is chasing.
##
## IT ONLY EVER ADDS. Section 24.1 is emphatic: mining is subtractive, so an existing
## valid edge cannot become physically false -- it can only ever become unnecessary. There
## is no removal operation on this class, and `NavGraph.upgrade_edge` refuses downgrades,
## so Invariant 6 is a property of the API rather than a rule the caller has to remember.
##
## THE TWO REFINEMENTS ARE BOTH ADDITIVE, and both matter for section 43's Scenario F:
## re-sampling clearance keeps costs honest in a chunk that just got roomier, and
## re-testing WIGGLE edges with the normal body is what turns a widened crevice from a
## squeeze the alien still pays 2 s for into an ordinary passage. Without the second, a
## patch adds nodes and no route ever gets better, which looks like the patcher not
## working at all.

## Whether to patch by flooding rather than by sweeping the lattice.
##
## MUST MATCH HOW THE GRAPH WAS BAKED. A patcher that sweeps a graph the bake flooded puts
## two different sampling rules into one graph, and the seam between them -- rock nodes in
## the patched region and none anywhere else -- reads as a patch that half worked.
## NavigationSource sets this from what it did.
var use_flood: bool = false

## Regions waiting to be patched, oldest first. Section 24.2 step 1.
var _dirty: Array[AABB] = []
## The SAME regions, ungrown, popped in lockstep with `_dirty`. See `_patch_seeds`.
var _dirty_raw: Array[AABB] = []
var _builder: NavGraphBuilder = null
var _current: AABB = AABB()
var _current_raw: AABB = AABB()
var _current_chunk: Vector3i = Vector3i.ZERO
var _nodes_before: int = 0


func _init() -> void:
	_builder = NavGraphBuilder.new()


## Section 24.2 step 1. Queues a changed region.
##
## GROWN BY `edge_search_radius` BEFORE QUEUEING. A patch confined to the dig itself
## produces nodes that cannot see the graph around them, because `_connect_one` searches
## outward from each new node and everything within reach has to already exist. Growing
## the region is what lets a new passage connect to the chambers at both ends.
## THE UNGROWN REGION IS KEPT TOO, and that is not bookkeeping. A flood patch needs a seed
## in air, and the only place this class KNOWS is air is the material that just stopped
## being rock. The grown region's centre will not do -- it is `edge_search_radius` bigger
## than the hole on every side, so it is routinely still solid.
func mark_dirty(region: AABB, config: NavigationConfig) -> void:
	var margin: float = config.edge_search_radius
	var grown := region.grow(margin)
	_dirty_raw.append(region)
	_dirty.append(grown)


func has_work() -> bool:
	return not _dirty.is_empty() or _builder.stage != NavGraphBuilder.Stage.IDLE


## Chunks that have been patched, for the section 39 overlay.
func dirty_chunks(graph: NavGraph) -> Array[Vector3i]:
	if graph == null:
		return [] as Array[Vector3i]
	return graph.revisions.touched()


## `nodes_added` counts nodes rather than candidates. The two are not the same number --
## decimation drops most candidates -- and subtracting a graph's node count from a builder's
## candidate count was near-always reporting zero.
func stats(graph: NavGraph = null) -> Dictionary:
	return {
		"queued": _dirty.size(),
		"stage": _builder.stage,
		"nodes_added": 0 if graph == null else maxi(graph.node_count() - _nodes_before, 0),
	}


## Spends up to `budget` probe queries. Returns a result on the tick a region completes,
## and null otherwise -- so a caller can treat "something changed" as an event.
func step(
	graph: NavGraph, budget: int, config: NavigationConfig, probe: NavigationProbe
) -> NavPatchResult:
	if graph == null:
		return null
	if _builder.stage == NavGraphBuilder.Stage.IDLE:
		if _dirty.is_empty():
			return null
		_start_next(graph, config, probe)
		return null
	if not _builder.step(budget):
		return null
	return _finish(graph, config, probe)


# ----- internals -----


func _start_next(graph: NavGraph, config: NavigationConfig, probe: NavigationProbe) -> void:
	_current = _dirty.pop_front()
	_current_raw = _dirty_raw.pop_front()
	_current_chunk = NavNode.chunk_of(_current.get_center(), config.chunk_size)
	_nodes_before = graph.node_count()
	if use_flood:
		_builder.begin_patch_flood(_current, _patch_seeds(graph), config, probe, graph)
	else:
		_builder.begin_patch(_current, config, probe, graph)
	for line: String in _builder.failures:
		push_warning("NavGraphPatcher cannot patch: %s" % line)


## Points inside the region about to be re-sampled that are known to be open.
##
## TWO SOURCES, AND BOTH ARE LOAD-BEARING. Existing nodes are open by definition -- the bake
## proved it -- and they are what any new geometry has to connect to anyway, so a flood that
## could not reach one would have produced an orphan component. But on the FIRST patch in a
## region the bake never reached there are no nodes at all, and then the dig is the only
## seed there is: section 43's Scenario F is the player mining through a wall into space the
## graph has never seen.
##
## THE CENTRE ONLY, NEVER THE CORNERS, and that is a correctness rule rather than economy.
## A flood trusts exactly one thing -- that a seed is in air -- and it CANNOT CHECK. On a
## concave trimesh a cell buried in stone touches no triangle, so it measures as wide open
## and a sweep between two buried cells finds nothing in the way; seed one and the flood
## spreads through the rock from there. A sphere brush's AABB corners are at 1.73 times its
## radius, comfortably outside anything it carved, so seeding them did exactly that: a 2.5 m
## dome mined into the CSG demo cave added 136 nodes instead of one.
##
## So every seed here has to be something this class can stand behind. An existing node was
## proved open by the bake. The raw region's centre is the caller's own claim about what it
## just changed -- see `CreatureNavigation.notify_terrain_changed`, which says the region
## must be centred on the change for exactly this reason.
func _patch_seeds(graph: NavGraph) -> PackedVector3Array:
	var seeds := PackedVector3Array()
	for id: int in graph.find_nearby_nodes(_current.get_center(), _current.size.length() * 0.5):
		var at: Vector3 = graph.node_at(id).position
		if _current.has_point(at):
			seeds.append(at)
	seeds.append(_current_raw.get_center())
	return seeds


func _finish(graph: NavGraph, config: NavigationConfig, probe: NavigationProbe) -> NavPatchResult:
	var revision: int = graph.revisions.bump(_current_chunk)
	graph.terrain_revision = graph.revisions.highest()
	var result := NavPatchResult.make(_current, _current_chunk, revision)
	result.edges_added = _builder.edges_normal + _builder.edges_wiggle
	for id: Variant in graph.node_ids():
		if int(id) >= _nodes_before:
			result.nodes_added.append(int(id))

	if config.refresh_clearance_on_patch:
		result.nodes_refreshed = _refresh_clearance(graph, config, probe)
	if config.upgrade_edges_on_patch:
		result.edges_upgraded = _upgrade_edges(graph, config, probe)

	_builder.stage = NavGraphBuilder.Stage.IDLE
	return result


## Re-measures clearance for pre-existing nodes in the patched region.
##
## Clearance ranks candidates and adds section 14's comfort penalty; it never gates. So
## this changes costs and never connectivity, which is what keeps it on the additive side
## of Invariant 6 even though it can lower a number.
func _refresh_clearance(graph: NavGraph, config: NavigationConfig, probe: NavigationProbe) -> int:
	var touched: int = 0
	for id: int in graph.find_nearby_nodes(_current.get_center(), _current.size.length() * 0.5):
		var node: NavNode = graph.node_at(id)
		if not _current.has_point(node.position):
			continue
		node.clearance = probe.clearance_at(
			node.position, config.world_mask, config.clearance_ceiling, config.clearance_steps
		)
		touched += 1
	return touched


## Section 43 Scenario F's payoff: a crevice the player widened stops being a squeeze.
func _upgrade_edges(graph: NavGraph, config: NavigationConfig, probe: NavigationProbe) -> int:
	var envelope: ClearanceProfile = config.clearance_profile
	var upgraded: int = 0
	for edge: NavEdge in graph.all_edges():
		if edge.type != NavEdge.Type.WIGGLE:
			continue
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		if not _current.has_point(from) and not _current.has_point(to):
			continue
		if not probe.shape_sweep_clear(envelope.normal_body(), from, to, config.world_mask):
			continue
		var travel: float = config.normal_travel_time(edge.distance)
		var cost: float = travel + config.clearance_penalty(travel, edge.min_clearance)
		if graph.upgrade_edge(edge.from_id, edge.to_id, NavEdge.Type.NORMAL_VOLUME, cost):
			upgraded += 1
	return upgraded
