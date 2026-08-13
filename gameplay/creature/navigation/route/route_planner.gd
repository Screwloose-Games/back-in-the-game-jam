class_name RoutePlanner
extends RefCounted

## Turns two world positions into a route (navigation.md sections 16, 17).
##
## KNOWS NOTHING ABOUT WHERE THE GRAPH CAME FROM. It is handed a NavGraph and never
## names a builder, terrain or voxels. That is the whole mechanism behind Invariant 9:
## when Spatial Memory lands and the alien plans against what it BELIEVES rather than
## against reality, the only thing that changes is which NavGraph instance arrives
## here. `verify_navigation_static.gd` enforces it.
##
## SECTION 16 IS THE REASON THIS CLASS EXISTS AT ALL. Without it the whole file would
## be one call to `AStar3D.get_id_path`. The spec is blunt about why that is not
## enough: "do not simply call astar.get_closest_point() and trust that result. The
## nearest graph node may lie through terrain." In a cave that is not an edge case --
## it is what happens every time the alien stands next to a wall with a chamber on the
## other side of it. The nearest node by distance is three metres away through solid
## rock, and a route that begins by attaching to it is wrong from its first waypoint,
## silently, with a perfectly plausible-looking path drawn on the overlay.

var config: NavigationConfig = null
var probe: NavigationProbe = null
## Attachment candidates considered by the last plan(), as [position, accepted]. Read
## by the section 39 overlay, which needs to show the REJECTED ones -- a route that
## attaches to a far node looks like a bug until you can see the three nearer nodes it
## tried and the walls in the way.
var last_attachment_attempts: Array = []


func _init(navigation_config: NavigationConfig = null, navigation_probe: NavigationProbe = null):
	config = navigation_config
	probe = navigation_probe


## Section 17's `request_route`. Synchronous: section 15 notes the graph is small enough
## that the search cost is insignificant next to the local geometry work, and measuring
## agrees -- A* over a thousand nodes is microseconds. Only the BAKE is frame-budgeted.
func plan(start: Vector3, target: Vector3, graph: NavGraph) -> NavRoute:
	last_attachment_attempts = []
	if config == null or probe == null or graph == null or graph.node_count() == 0:
		return NavRoute.unreachable(target)

	var start_attach: Dictionary = attach(start, graph)
	# Section 40.3 applies to both ends, but only the START being unattachable makes the
	# query meaningless -- there is nowhere to set off from. An unattachable target is a
	# partial route, not a failure.
	if not start_attach["ok"]:
		return NavRoute.unreachable(target)
	var start_id: int = start_attach["id"]

	var goal_attach: Dictionary = attach(target, graph)
	if goal_attach["ok"]:
		var ids: PackedInt32Array = graph.find_path_ids(start_id, goal_attach["id"])
		if ids.size() > 0:
			return _assemble(
				start, target, graph, ids, start_attach["type"], goal_attach["type"], true
			)

	# Either the target could not attach, or it attached to a node in a component this
	# one cannot reach. Both mean the same thing to the caller and both get section
	# 40.4's answer.
	return _partial(start, target, graph, start_id, start_attach["type"])


## Section 16: several nearby candidates, shape-cast to each, nearest feasible wins.
##
## Returns {ok, id, type}. `type` is which body the cast cleared with, so the
## attachment hop carries the same NORMAL_VOLUME / WIGGLE distinction as a baked edge
## and the follower knows whether reaching the graph needs a squeeze.
##
## Nearest FEASIBLE, not nearest normal-volume-feasible. A closer node reachable only
## by squeezing beats a distant one reachable normally, because attachment is about
## joining the graph at all; the route search downstream is what compares costs.
##
## Public because it is the single most testable claim in section 16 -- "the nearest
## graph node may lie through terrain" -- and asserting it through `plan()` means
## asserting it through A* as well.
func attach(point: Vector3, graph: NavGraph) -> Dictionary:
	var nearby: PackedInt32Array = graph.find_nearby_nodes(point, config.endpoint_search_radius)
	var profile: ClearanceProfile = config.clearance_profile
	var mask: int = config.world_mask
	var considered: int = 0

	for id: int in nearby:
		if considered >= config.endpoint_candidate_count:
			break
		considered += 1
		var node: NavNode = graph.node_at(id)
		var accepted: bool = false
		var attach_type: NavEdge.Type = NavEdge.Type.NORMAL_VOLUME
		if probe.shape_sweep_clear(profile.normal_body(), point, node.position, mask):
			accepted = true
		elif probe.shape_sweep_clear(profile.squeezed_body(), point, node.position, mask):
			accepted = true
			attach_type = NavEdge.Type.WIGGLE
		last_attachment_attempts.append([node.position, accepted])
		if accepted:
			return {"ok": true, "id": id, "type": attach_type}

	return {"ok": false, "id": -1, "type": NavEdge.Type.NORMAL_VOLUME}


## Every feasible attachment, nearest first, rather than only the first (section 35).
##
## THIS IS WHERE SECTION 35'S ALTERNATIVES COME FROM, and it is a better source than the
## usual one. Re-running A* with the chosen route's edges penalised needs mutable edge
## weights and produces routes that differ only in the middle; attaching at genuinely
## different nodes produces routes that leave by different openings, which is what section
## 35's worked example -- one wide tunnel, one tight one -- actually looks like in a cave.
func attach_all(point: Vector3, graph: NavGraph) -> PackedInt32Array:
	var found := PackedInt32Array()
	var nearby: PackedInt32Array = graph.find_nearby_nodes(point, config.endpoint_search_radius)
	var profile: ClearanceProfile = config.clearance_profile
	var mask: int = config.world_mask
	var considered: int = 0

	for id: int in nearby:
		if considered >= config.endpoint_candidate_count:
			break
		considered += 1
		var at: Vector3 = graph.node_at(id).position
		if probe.shape_sweep_clear(profile.normal_body(), point, at, mask):
			found.append(id)
		elif probe.shape_sweep_clear(profile.squeezed_body(), point, at, mask):
			found.append(id)
	return found


# ----- internals -----


## Section 40.4. The reachable node closest to the goal, which is a different question
## from "the node A* stopped at" -- A* stops nowhere when there is no path.
func _partial(
	start: Vector3, target: Vector3, graph: NavGraph, start_id: int, start_type: NavEdge.Type
) -> NavRoute:
	var reachable: Dictionary = graph.reachable_from(start_id)
	var best_id: int = start_id
	var best_distance: float = graph.node_at(start_id).position.distance_squared_to(target)
	for id: Variant in reachable:
		var offset: float = graph.node_at(id).position.distance_squared_to(target)
		if offset < best_distance:
			best_distance = offset
			best_id = id

	var ids := PackedInt32Array([start_id])
	if best_id != start_id:
		ids = graph.find_path_ids(start_id, best_id)
		if ids.size() == 0:
			ids = PackedInt32Array([start_id])
	return _assemble(start, target, graph, ids, start_type, NavEdge.Type.NORMAL_VOLUME, false)


## Builds the polyline and its per-hop segments from a node id path.
func _assemble(
	start: Vector3,
	target: Vector3,
	graph: NavGraph,
	ids: PackedInt32Array,
	start_type: NavEdge.Type,
	goal_type: NavEdge.Type,
	complete: bool
) -> NavRoute:
	var route := NavRoute.new()
	route.target_position = target
	route.status = NavRoute.Status.COMPLETE if complete else NavRoute.Status.PARTIAL
	route.node_ids = ids

	route.anchors.append(start)
	var previous: Vector3 = start
	var previous_id: int = -1
	for id: int in ids:
		var node: NavNode = graph.node_at(id)
		# The first hop is the attachment cast, which has no baked edge behind it; every
		# later hop is a validated graph edge and carries that edge's type and cost.
		var hop_type: NavEdge.Type = start_type
		if previous_id >= 0:
			var edge: NavEdge = graph.edge_between(previous_id, id)
			if edge != null:
				hop_type = edge.type
				route.cost += edge.base_cost
		route.anchors.append(node.position)
		route.segments.append(NavRouteSegment.make(previous, node.position, hop_type))
		previous = node.position
		previous_id = id

	# Only a complete route reaches the real target. A partial one stops at the last
	# node it can get to, and appending the goal anyway would draw a line straight
	# through whatever is blocking it.
	if complete:
		route.anchors.append(target)
		route.segments.append(NavRouteSegment.make(previous, target, goal_type))
	return route
