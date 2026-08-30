extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## NavigationConfig.candidate_recentre: section 9's medial step, as one retry per candidate.
##
## THE DEFECT THESE EXIST FOR IS A PHASE ERROR, NOT A SIZE ERROR. Section 12.1 samples at
## absolute world multiples of `candidate_spacing`, and a cell survives only where the
## squeezed body fits AT THAT POINT -- so a bore leaves a usable band `width - 2 *
## min_traversal_clearance` across, and a bore whose axis lands between two lattice planes
## gets no nodes at all however comfortably the alien would fit down the middle of it. For a
## bore running along an axis the error is constant down its whole length, so the passage
## vanishes entirely and nothing reports it: the bake succeeds and the counts look plausible.
##
## `_offset_bore` is that geometry at test scale, and the first two cases are a matched pair
## -- the same cave, refused without re-centring and recovered with it. The rest are the
## bounds: re-centring must never rescue a passage the body genuinely does not fit, because
## that is Invariant 5, and it must land in the same place for the flood and for the sweep,
## because that is what test_graph_flood.gd's equivalence property means.

## Where `_offset_bore` puts its axis, on both cross-section axes.
##
## FIVE, AGAINST A PITCH OF TWO. Deliberately an odd multiple of half the pitch, so the
## nearest lattice planes are a full metre away on either side and no rounding decides the
## outcome. `navigation_test_case._corridor_cave` centres its opening ON the lattice for the
## opposite reason, and its comment says so.
const BORE_AXIS: float = 5.0
## Wide enough for the normal body down the middle, narrow enough that its 0.75 m band
## clears no lattice plane. At the default profile the axis has 1.5 m of clearance and the
## nearest lattice plane 0.5 m, against a 0.75 m gate.
const OPEN_BORE: float = 3.0
## Too tight for the squeezed body anywhere, including on its own axis.
const TIGHT_BORE: float = 1.4
const BORE_LENGTH: float = 20.0
const BORE_TALL: float = 10.0


## A square bore along X through solid rock, centred `at` on both cross-section axes.
##
## Bounded by `add_room` rather than left open, for the reason that method exists: the void
## outside a fixture's boxes has unlimited clearance, so an unbounded bore would be a bore
## through rock surrounded by the best candidates in the region.
func _offset_bore(width: float, at: float = BORE_AXIS) -> AABB:
	var region := AABB(Vector3.ZERO, Vector3(BORE_LENGTH, BORE_TALL, BORE_TALL))
	_probe.add_room(region)
	var half: float = width * 0.5
	var low: float = at - half
	var high: float = at + half
	_probe.add_solid(AABB(Vector3.ZERO, Vector3(BORE_LENGTH, low, BORE_TALL)))
	_probe.add_solid(
		AABB(Vector3(0.0, high, 0.0), Vector3(BORE_LENGTH, BORE_TALL - high, BORE_TALL))
	)
	_probe.add_solid(AABB(Vector3(0.0, low, 0.0), Vector3(BORE_LENGTH, width, low)))
	_probe.add_solid(AABB(Vector3(0.0, low, high), Vector3(BORE_LENGTH, width, BORE_TALL - high)))
	return region


## How far the worst node sits from the bore axis, ACROSS the bore rather than along it.
func _worst_axis_offset(graph: NavGraph, at: float = BORE_AXIS) -> float:
	var worst: float = 0.0
	for id: Variant in graph.node_ids():
		var node: Vector3 = graph.node_at(id).position
		worst = maxf(worst, maxf(absf(node.y - at), absf(node.z - at)))
	return worst


## THE REGRESSION, STATED AS THE BUG IT WAS. Without the retry this cave has no graph.
func test_a_bore_between_lattice_planes_is_lost_without_recentring() -> void:
	_config.candidate_recentre = false
	var graph: NavGraph = _bake(_offset_bore(OPEN_BORE))

	assert_eq(
		graph.node_count(),
		0,
		(
			"a 3 m bore the normal body fits down should sample as no cave at all, "
			+ "because every lattice plane misses its 0.75 m band"
		)
	)


## The same cave, recovered. Nodes AND edges, because a row of nodes nothing connects is the
## other way this could look fixed while the alien still cannot cross.
func test_recentring_recovers_a_bore_between_lattice_planes() -> void:
	var graph: NavGraph = _bake(_offset_bore(OPEN_BORE))

	assert_gt(graph.node_count(), 1, "the bore should sample as a run of nodes")
	assert_gt(graph.edge_count(), 0, "and they should connect along it")
	for edge: NavEdge in graph.all_edges():
		assert_eq(
			edge.type,
			NavEdge.Type.NORMAL_VOLUME,
			"a 3 m bore carries the 2.5 m normal body, so nothing here is a squeeze"
		)


## WHERE IT LANDS IS THE WHOLE CONTRACT, and it is what makes the retry independent of the
## region it was baked in. The axis of a bore is a property of the cave; the lattice plane
## nearest to it is a property of whatever AABB somebody passed in. A node on the axis
## therefore reproduces under section 24.2's patch, which re-samples a smaller region.
func test_a_recentred_node_lands_on_the_bore_axis() -> void:
	var graph: NavGraph = _bake(_offset_bore(OPEN_BORE))

	assert_gt(graph.node_count(), 0, "the fixture should produce nodes at all")
	assert_almost_eq(
		_worst_axis_offset(graph),
		0.0,
		0.001,
		"every node should sit on the bore centreline, not one lattice plane off it"
	)


## INVARIANT 5, AND THE REASON THE RETRY IS ALLOWED TO CAST A RAY AT ALL. Re-centring can
## raise a cell's clearance to the true half-width of its passage and not one millimetre
## further, so a bore the body does not fit is still a bore the body does not fit.
func test_recentring_never_rescues_a_bore_the_body_does_not_fit() -> void:
	# Centred ON a lattice plane, so a candidate really is offered and really is refused --
	# off one, the cell would be inside rock and `shape_fits` would have rejected it first,
	# which proves nothing about re-centring.
	var graph: NavGraph = _bake(_offset_bore(TIGHT_BORE, 4.0))

	assert_eq(
		graph.node_count(),
		0,
		"a 1.4 m bore has 0.7 m of clearance on its own axis, under the 0.75 m gate"
	)


## Section 43's Scenario G, with the retry on. The 1 m slot is the calibration case for the
## whole module, and a sampler that quietly widened it would pass every other test here while
## letting the alien through a player-only crack.
func test_recentring_leaves_the_impassable_corridor_sealed() -> void:
	var cave: AABB = _corridor_cave(IMPASSABLE_CORRIDOR)
	var graph: NavGraph = _bake(cave)
	var opening: AABB = _corridor_volume(IMPASSABLE_CORRIDOR)

	assert_eq(_nodes_in(graph, opening), [], "no node may sit inside a 1 m slot")
	assert_eq(_edges_through(graph, opening).size(), 0, "and no edge may cross it")


## test_graph_flood.gd's equivalence property, restated for the cells the retry touches.
##
## The flood and the sweep disagree about which cells are LOOKED at and about nothing else,
## so a centring step applied on one path and not the other would break that for a reason
## having nothing to do with enumeration. Both go through `_offer_candidate`, and this is the
## assertion that keeps them there.
func test_a_flood_and_a_sweep_agree_on_a_recentred_bore() -> void:
	var region: AABB = _offset_bore(OPEN_BORE)
	var swept: NavGraph = _bake(region)
	var flooded: NavGraph = _flood(region, [Vector3(10.0, BORE_AXIS, BORE_AXIS)])

	assert_gt(swept.node_count(), 0, "the fixture should produce nodes at all")
	assert_eq(flooded.node_count(), swept.node_count(), "flood and sweep node counts")
	assert_almost_eq(
		_worst_axis_offset(flooded), 0.0, 0.001, "the flood should centre where the sweep did"
	)


## Same cave, same graph, twice. A retry that read anything but the geometry at the cell --
## a neighbour's cached clearance, say -- would pass every case above and still hand a patch
## a different answer than the bake gave.
func test_recentring_is_deterministic() -> void:
	var region: AABB = _offset_bore(OPEN_BORE)
	var first: NavGraph = _bake(region)
	var second: NavGraph = _bake(region)

	assert_gt(first.node_count(), 0, "the fixture should produce nodes at all")
	assert_eq(second.node_count(), first.node_count(), "node counts across two bakes")
	for id: Variant in first.node_ids():
		assert_eq(
			second.node_at(id).position,
			first.node_at(id).position,
			"node %s should land in the same place both times" % id
		)


## The knob is a knob, and an out-of-range one is refused rather than clamped.
func test_a_recentre_fraction_past_half_a_pitch_is_an_invalid_config() -> void:
	_config.candidate_recentre_fraction = 0.9

	var failures: PackedStringArray = _config.invariant_failures()

	assert_gt(failures.size(), 0, "past half a pitch a node leaves the cell that produced it")
	assert_true(
		"\n".join(failures).contains("candidate_recentre_fraction"),
		"and the failure should name the field: %s" % failures
	)
