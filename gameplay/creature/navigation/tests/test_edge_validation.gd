extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Section 13.2's classification, which is the whole of Invariant 5.
##
## Three cases, one parameter apart: a corridor the normal body clears, one only the
## squeezed body clears, and one neither clears. The third is the important one -- a
## player-only tunnel excludes the alien because no edge is ever validated through it,
## not because anything anywhere is flagged.
##
## THE FAILURE MODE THESE GUARD AGAINST IS SILENT. An edge wrongly classified
## NORMAL_VOLUME does not crash, does not warn, and does not fail any behavioural test;
## it produces an alien that reaches places it should not, and that reads as the
## creature working better than expected.


func test_wide_corridor_carries_the_normal_body() -> void:
	var region: AABB = _corridor_cave(WIDE_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var through: Array = _edges_through(graph, _corridor_volume(WIDE_CORRIDOR))

	assert_true(through.size() > 0, "no edge crosses a 6 m corridor")
	assert_has(
		_edge_types(through),
		NavEdge.Type.NORMAL_VOLUME,
		"a 6 m corridor should carry the normal body"
	)


func test_tight_corridor_is_wiggle_only() -> void:
	var region: AABB = _corridor_cave(TIGHT_CORRIDOR)
	var graph: NavGraph = _bake(region)
	var through: Array = _edges_through(graph, _corridor_volume(TIGHT_CORRIDOR))
	var types: Array = _edge_types(through)

	assert_true(through.size() > 0, "no edge crosses a 2 m corridor; the squeezed body fits")
	assert_has(types, NavEdge.Type.WIGGLE, "a 2 m corridor should classify as WIGGLE")
	# The half that a "does a wiggle edge exist" check would miss entirely.
	assert_does_not_have(
		types,
		NavEdge.Type.NORMAL_VOLUME,
		"the normal body is 2.5 m across and must not clear a 2 m corridor"
	)


## Scenarios C and G. The alien cannot follow the player through its own escape route.
func test_impassable_corridor_produces_no_edge_at_all() -> void:
	var region: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var graph: NavGraph = _bake(region)

	assert_eq(
		_edges_through(graph, _corridor_volume(IMPASSABLE_CORRIDOR)).size(),
		0,
		"a 1 m slot is narrower than the squeezed body and must carry nothing"
	)


## Section 13.2 again, from the other direction: the rooms are genuinely separated,
## not merely un-edged across the slot. An edge could route around the divider if the
## room had a way around, and the count check above would still pass.
func test_impassable_corridor_leaves_two_components() -> void:
	var region: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var graph: NavGraph = _bake(region)

	var west: Array = _nodes_in(graph, AABB(Vector3.ZERO, Vector3(10.0, 8.0, 12.0)))
	var east: Array = _nodes_in(graph, AABB(Vector3(16.0, 0.0, 0.0), Vector3(10.0, 8.0, 12.0)))
	assert_true(west.size() > 0, "the west room has no nodes")
	assert_true(east.size() > 0, "the east room has no nodes; the check below proves nothing")

	var reachable: Dictionary = graph.reachable_from(west[0])
	var leaked: int = 0
	for id: Variant in east:
		if reachable.has(id):
			leaked += 1
	assert_eq(leaked, 0, "%d east-room nodes are reachable through a 1 m slot" % leaked)


## Section 13.3: leaps are queried by the local planner at the moment of use, never
## baked. A LEAP edge type does not exist, and this is the assertion that notices if
## someone adds one and starts emitting it.
func test_only_two_edge_types_exist() -> void:
	var region: AABB = _corridor_cave(TIGHT_CORRIDOR)
	var graph: NavGraph = _bake(region)

	assert_eq(NavEdge.Type.size(), 2, "sections 11.3 and 13.3 allow exactly two baked types")
	for edge: NavEdge in graph.all_edges():
		assert_true(
			edge.type == NavEdge.Type.NORMAL_VOLUME or edge.type == NavEdge.Type.WIGGLE,
			"unexpected baked edge type %d" % edge.type
		)
