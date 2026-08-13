class_name NavAStar
extends AStar3D

## AStar3D taught to search in SECONDS instead of metres (navigation.md sections 14, 15).
##
## Section 14 opens by rejecting the obvious implementation: "do not use clearance as
## the only AStar3D.weight_scale". Weight scales multiply a euclidean distance, so they
## can express "this node is uncomfortable" but cannot express "this edge costs two
## seconds of squeezing plus a slow crawl" -- which is the entire reason a 3 m crevice
## has to lose to a 12 m detour. Overriding the two cost virtuals is what lets the
## stored per-edge cost be the real one.
##
## THE HEURISTIC MUST BE IN THE SAME UNIT AS THE COST, and it must never overestimate.
## Both mistakes are silent: A* still returns a path, it just is not the cheapest one,
## and nothing anywhere reports a problem. `_estimate_cost` therefore converts the
## straight-line distance at the FASTEST speed in the model, which is the cheapest any
## real route could possibly be.
##
## Deliberately holds its own cost table rather than a reference back to NavGraph.
## AStar3D is a RefCounted, NavGraph is a RefCounted, and a graph holding a searcher
## holding the graph is a reference cycle that never frees -- one leaked cave per bake.

## Seconds per metre used by the heuristic. Set from
## NavigationConfig.best_seconds_per_metre().
var seconds_per_metre: float = 0.0

## Vector2i(min_id, max_id) -> seconds. Written by NavGraph as edges are added.
var edge_costs: Dictionary = {}


## Undirected key for an edge, so both traversal directions read one entry.
static func key_for(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func _compute_cost(from_id: int, to_id: int) -> float:
	var cost: Variant = edge_costs.get(key_for(from_id, to_id))
	if cost == null:
		# Only reachable if something connected two points in AStar3D without going
		# through NavGraph.add_edge. Fall back to the heuristic rather than 0.0: a
		# free edge would make A* prefer precisely the connection nobody validated.
		return _estimate_cost(from_id, to_id)
	return float(cost)


func _estimate_cost(from_id: int, to_id: int) -> float:
	var span: float = get_point_position(from_id).distance_to(get_point_position(to_id))
	return span * seconds_per_metre
