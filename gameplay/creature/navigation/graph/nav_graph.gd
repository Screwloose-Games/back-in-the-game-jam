class_name NavGraph
extends RefCounted

## The sparse topology graph (navigation.md sections 15, 26).
##
## IT ANSWERS ONE QUESTION: what navigable areas are connected? (Section 2.2.) It does
## not prescribe physical movement, and Invariant 2 is explicit that "a route is never
## considered physically valid solely because two graph nodes are connected". Every
## edge in here was proved by a swept collision shape at bake time, which is a much
## stronger claim than a navmesh makes -- and it is still not a claim that the body can
## execute the motion today, at its current speed, from its current pose.
##
## DELIBERATELY IGNORANT OF WHERE ITS CONTENTS CAME FROM. Nothing in this class, or in
## `route/`, names a probe, a builder, terrain or voxels. That is what makes section
## 26's `WorldNavigationGraph` and the future Spatial Memory graph the same type: when
## the alien plans against what it believes rather than against reality (Invariant 9),
## the only thing that changes is which NavGraph instance it was handed.
## `verify_navigation_static.gd` enforces the ignorance.
##
## The spatial hash is not an optimisation for later. Decimation asks "is any accepted
## node within 3 m of this candidate?" once per surviving candidate, and connection
## asks for neighbours once per node; both are O(n^2) scans without it, and a 30 m cave
## produces enough candidates for that to be the whole bake.

## Section 25. Bumped by whatever patches the graph, and read for knowledge freshness
## and cache invalidation. Nothing in phases 1-2 writes it except a full rebuild.
var terrain_revision: int = 0
## Section 25's per-chunk counters. A public FIELD rather than four forwarding methods,
## which is what keeps this class under gdlint's public-method cap.
var revisions: NavChunkRevisions = NavChunkRevisions.new()

var _nodes: Dictionary = {}
var _adjacency: Dictionary = {}
var _edges: Dictionary = {}
var _buckets: Dictionary = {}
var _bucket_size: float = 4.0
var _chunk_size: float = 16.0
var _next_id: int = 0
var _astar: NavAStar = null


## Bucket edge length and the heuristic's unit conversion, both from NavigationConfig.
##
## Call before adding anything. Rebucketing an existing graph is not supported because
## nothing needs it: the builder configures a fresh graph, and section 24.2's local
## patching reuses the same settings by construction.
func configure(bucket_size: float, chunk_size: float, seconds_per_metre: float) -> void:
	_bucket_size = maxf(bucket_size, 0.01)
	_chunk_size = maxf(chunk_size, 0.01)
	_astar = NavAStar.new()
	_astar.seconds_per_metre = seconds_per_metre


func add_node(at: Vector3, clearance: float) -> int:
	return add_node_with_id(_next_id, at, clearance)


## Adds a node under a caller-chosen id.
##
## SECTION 27'S PROJECTION NEEDS THIS. A believed graph and the world graph must agree on
## node ids, because `NavRoute.node_ids` names them and knowledge is keyed by them; a
## projection that renumbered would produce routes whose ids mean something different
## depending on which graph made them, which is the kind of bug that only shows up once
## two subsystems compare notes.
##
## `_next_id` is kept above any explicit id, so mixing the two cannot collide.
func add_node_with_id(id: int, at: Vector3, clearance: float) -> int:
	_ensure_astar()
	_next_id = maxi(_next_id, id + 1)
	var node: NavNode = NavNode.make(id, at, clearance, NavNode.chunk_of(at, _chunk_size))
	_nodes[id] = node
	_adjacency[id] = PackedInt32Array()
	_astar.add_point(id, at)

	var bucket: Vector3i = _bucket_of(at)
	var occupants: PackedInt32Array = _buckets.get(bucket, PackedInt32Array())
	occupants.append(id)
	_buckets[bucket] = occupants
	return id


## Records a validated edge. Idempotent on the undirected pair.
func add_edge(edge: NavEdge) -> void:
	if edge == null or not _nodes.has(edge.from_id) or not _nodes.has(edge.to_id):
		return
	var key: Vector2i = NavAStar.key_for(edge.from_id, edge.to_id)
	if _edges.has(key):
		return
	_edges[key] = edge

	var from_neighbors: PackedInt32Array = _adjacency[edge.from_id]
	from_neighbors.append(edge.to_id)
	_adjacency[edge.from_id] = from_neighbors
	var to_neighbors: PackedInt32Array = _adjacency[edge.to_id]
	to_neighbors.append(edge.from_id)
	_adjacency[edge.to_id] = to_neighbors

	_ensure_astar()
	_astar.edge_costs[key] = edge.base_cost
	_astar.connect_points(edge.from_id, edge.to_id, true)


## Rewrites a stored edge's type and cost. UPGRADE ONLY, and the guard is the point.
##
## Section 24.1: mining is subtractive, so a passage can only ever get easier, and
## Invariant 6 says an existing valid edge stays valid. Allowing a downgrade here would
## make that invariant a matter of every caller's care rather than a property of the type
## -- and the failure it protects against is silent, because a route that vanishes mid
## traversal looks like a pathfinding bug rather than a graph edit.
##
## Returns whether anything changed.
func upgrade_edge(a: int, b: int, edge_type: NavEdge.Type, cost: float) -> bool:
	var key: Vector2i = NavAStar.key_for(a, b)
	if not _edges.has(key):
		return false
	var edge: NavEdge = _edges[key]
	if edge_type == NavEdge.Type.WIGGLE and edge.type == NavEdge.Type.NORMAL_VOLUME:
		return false
	if cost >= edge.base_cost and edge_type == edge.type:
		return false
	edge.type = edge_type
	edge.base_cost = cost
	_ensure_astar()
	_astar.edge_costs[key] = cost
	return true


func has_node(id: int) -> bool:
	return _nodes.has(id)


func node_at(id: int) -> NavNode:
	return _nodes.get(id) as NavNode


func get_neighbors(id: int) -> PackedInt32Array:
	return _adjacency.get(id, PackedInt32Array())


func edge_between(a: int, b: int) -> NavEdge:
	return _edges.get(NavAStar.key_for(a, b)) as NavEdge


func node_ids() -> Array:
	return _nodes.keys()


func all_edges() -> Array:
	return _edges.values()


func node_count() -> int:
	return _nodes.size()


func edge_count() -> int:
	return _edges.size()


## Every node within `radius` of `position`, nearest first.
##
## Section 16's first step. Sorted because both callers -- decimation, which wants any
## hit, and endpoint attachment, which wants to shape-cast the closest candidates
## first -- are cheaper when the good answer arrives early.
func find_nearby_nodes(position: Vector3, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	if radius <= 0.0:
		return found
	var radius_squared: float = radius * radius
	var reach: int = int(ceil(radius / _bucket_size))
	var origin: Vector3i = _bucket_of(position)

	var scored: Array = []
	for dx: int in range(-reach, reach + 1):
		for dy: int in range(-reach, reach + 1):
			for dz: int in range(-reach, reach + 1):
				var bucket: Vector3i = origin + Vector3i(dx, dy, dz)
				if not _buckets.has(bucket):
					continue
				for id: int in _buckets[bucket] as PackedInt32Array:
					var offset: float = (_nodes[id] as NavNode).position.distance_squared_to(
						position
					)
					if offset <= radius_squared:
						scored.append([offset, id])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in scored:
		found.append(entry[1])
	return found


## Whether any node sits within `radius`. The section 12.2 decimation test.
##
## Separate from find_nearby_nodes because decimation runs once per surviving candidate
## and does not care which node it hit, only that one exists -- and stopping at the
## first hit skips the sort entirely.
func has_node_within(position: Vector3, radius: float) -> bool:
	if radius <= 0.0:
		return false
	var radius_squared: float = radius * radius
	var reach: int = int(ceil(radius / _bucket_size))
	var origin: Vector3i = _bucket_of(position)
	for dx: int in range(-reach, reach + 1):
		for dy: int in range(-reach, reach + 1):
			for dz: int in range(-reach, reach + 1):
				var bucket: Vector3i = origin + Vector3i(dx, dy, dz)
				if not _buckets.has(bucket):
					continue
				for id: int in _buckets[bucket] as PackedInt32Array:
					if (
						(_nodes[id] as NavNode).position.distance_squared_to(position)
						<= radius_squared
					):
						return true
	return false


## Section 26's coarse route search. Node ids, not positions -- the caller needs the
## edges between them to know which segments are WIGGLE.
##
## AStar3D.get_id_path returns a PackedInt64Array, and GDScript will not narrow one to
## a PackedInt32Array implicitly -- it is a compile error that takes the whole module
## down with it. Copying is the fix rather than widening every id array in the module
## to 64 bits for the sake of one engine signature.
func find_path_ids(start_id: int, end_id: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if not _nodes.has(start_id) or not _nodes.has(end_id):
		return ids
	_ensure_astar()
	for id: int in _astar.get_id_path(start_id, end_id):
		ids.append(id)
	return ids


## Every node reachable from `start_id`, as a set of ids.
##
## Section 40.4: when no complete route exists, the answer is the best REACHABLE place,
## and finding it means knowing what is reachable. A* cannot be asked this -- it
## answers about one destination at a time -- so this is a plain flood over adjacency.
func reachable_from(start_id: int) -> Dictionary:
	var seen: Dictionary = {}
	if not _nodes.has(start_id):
		return seen
	var frontier: Array[int] = [start_id]
	seen[start_id] = true
	while not frontier.is_empty():
		var id: int = frontier.pop_back()
		for neighbor: int in get_neighbors(id):
			if not seen.has(neighbor):
				seen[neighbor] = true
				frontier.append(neighbor)
	return seen


# ----- internals -----


func _bucket_of(at: Vector3) -> Vector3i:
	return Vector3i((at / _bucket_size).floor())


## configure() is the supported entry point, but a graph built by a test that forgot to
## call it should misbehave visibly rather than crash on a null AStar3D.
func _ensure_astar() -> void:
	if _astar == null:
		_astar = NavAStar.new()
