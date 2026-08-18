extends GutTest

## Shared fixture for the suites that need a graph.
##
## Not collected as a test script itself -- GUT's default prefix is `test_`, and this
## file deliberately does not have it.
##
## Everything here runs with no scene tree, no physics server and no voxel extension:
## the builder is driven synchronously against FakeNavigationProbe's analytic boxes.
## That is what keeps the suite fast enough to run on every push, and it is why the
## runtime verifier exists separately -- these tests prove the builder does the right
## thing with the answers it is given, and cannot prove that real Jolt gives those
## answers.

const FakeProbe := preload("res://gameplay/creature/navigation/tests/fake_navigation_probe.gd")

## A corridor wide enough for the normal body, at the shipped ClearanceProfile.
const WIDE_CORRIDOR: float = 6.0
## Wide enough for the squeezed body (1.5 m across) and not the normal one (2.5 m).
const TIGHT_CORRIDOR: float = 2.0
## Too small for either.
const IMPASSABLE_CORRIDOR: float = 1.0
## Height at which the normal body rests above a floor whose top face is y = 0.
##
## ABOVE ITS OWN CLEARANCE RADIUS, which is 1.25 m at the shipped ClearanceProfile. A body
## centred any lower is in collision with the floor, so the swept cast that validates a
## crawl step correctly refuses it -- correctly, and for a reason no crawl test is trying
## to demonstrate.
const FLOOR_STANDOFF: float = 1.6

var _config: NavigationConfig = null
var _probe: RefCounted = null


func before_each() -> void:
	_config = NavigationConfig.new()
	_probe = FakeProbe.new()


## A single hollow room, and the region that covers it.
func _open_room(size: Vector3 = Vector3(20.0, 8.0, 20.0)) -> AABB:
	var interior := AABB(Vector3.ZERO, size)
	_probe.add_room(interior)
	return interior


## Two rooms with one square corridor between them, and the region that covers both.
##
## The corridor width is the whole experiment: 6 m passes the normal body, 2 m passes
## only the squeezed one, 1 m passes neither. Everything section 13.2 classifies is a
## consequence of this one number, which is what makes the three edge-validation cases
## a single parameter apart.
##
## Centred on (y=4, z=6) so the 2 m lattice threads it whatever the width -- see
## NavigationSandboxGeometry for why that matters.
func _corridor_cave(corridor: float) -> AABB:
	var interior := AABB(Vector3.ZERO, Vector3(26.0, 8.0, 12.0))
	_probe.add_room(interior)

	var half: float = corridor * 0.5
	var low: float = 4.0 - half
	var high: float = 4.0 + half
	var near: float = 6.0 - half
	var far: float = 6.0 + half
	_probe.add_solid(AABB(Vector3(10.0, 0.0, 0.0), Vector3(6.0, low, 12.0)))
	_probe.add_solid(AABB(Vector3(10.0, high, 0.0), Vector3(6.0, 8.0 - high, 12.0)))
	_probe.add_solid(AABB(Vector3(10.0, low, 0.0), Vector3(6.0, corridor, near)))
	_probe.add_solid(AABB(Vector3(10.0, low, far), Vector3(6.0, corridor, 12.0 - far)))
	return interior


## The opening `_corridor_cave` left in the divider.
func _corridor_volume(corridor: float) -> AABB:
	var half: float = corridor * 0.5
	return AABB(Vector3(10.0, 4.0 - half, 6.0 - half), Vector3(6.0, corridor, corridor))


## Every edge whose straight line passes through `volume`.
func _edges_through(graph: NavGraph, volume: AABB) -> Array:
	var found: Array = []
	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for sample: int in 33:
			if volume.has_point(from.lerp(to, float(sample) / 32.0)):
				found.append(edge)
				break
	return found


func _nodes_in(graph: NavGraph, volume: AABB) -> Array:
	var found: Array = []
	for id: Variant in graph.node_ids():
		if volume.has_point(graph.node_at(id).position):
			found.append(id)
	return found


func _edge_types(edges: Array) -> Array:
	var types: Array = []
	for edge: NavEdge in edges:
		types.append(edge.type)
	return types


## Bakes `region` to completion and returns the graph.
func _bake(region: AABB) -> NavGraph:
	var builder := NavGraphBuilder.new()
	builder.begin(region, _config, _probe)
	assert_eq(
		builder.failures.size(), 0, "the fixture config should be valid: %s" % builder.failures
	)
	return builder.build_now()


## Floods `region` from `seeds` to completion and returns the graph, or null if the flood
## refused. The counterpart of `_bake`, deliberately NOT asserting on failures -- one of the
## flood cases is about a refusal.
func _flood(region: AABB, seeds: Array) -> NavGraph:
	return _flood_builder(region, seeds).graph


func _flood_builder(region: AABB, seeds: Array) -> NavGraphBuilder:
	var builder := NavGraphBuilder.new()
	builder.begin_flood(region, PackedVector3Array(seeds), _config, _probe)
	builder.build_now()
	return builder


func _builder_for(region: AABB) -> NavGraphBuilder:
	var builder := NavGraphBuilder.new()
	builder.begin(region, _config, _probe)
	builder.build_now()
	return builder


func _planner() -> RoutePlanner:
	return RoutePlanner.new(_config, _probe)


func _follower() -> RouteFollower:
	var follower := RouteFollower.new(_config, _probe)
	follower.surface = NavSurfaceField.new()
	return follower


## A body state at `at`, facing `forward`, with UP as its reference orientation.
func _body_state(at: Vector3, forward: Vector3 = Vector3.FORWARD) -> NavBodyState:
	return NavBodyState.make(at, forward, Vector3.UP)


## Perception's report about one cell, for the suites that feed knowledge.
##
## `GeometryObservation.position` is the region's CENTRE, so an observation made "at" a
## point actually lands half a metre off it on each axis. That is perception's contract
## rather than a fixture quirk, and the knowledge suites are written against it.
func _free_at(at: Vector3) -> GeometryObservation:
	return GeometryObservation.make(
		GeometryObservation.ObservationType.FREE, AABB(at, Vector3.ONE), 1.0, 0.0
	)


func _solid_at(at: Vector3) -> GeometryObservation:
	return GeometryObservation.make(
		GeometryObservation.ObservationType.SOLID, AABB(at, Vector3.ONE), 1.0, 0.0
	)


func _clearance_at(at: Vector3, clearance: float) -> GeometryObservation:
	return GeometryObservation.make(
		GeometryObservation.ObservationType.CLEARANCE, AABB(at, Vector3.ONE), 1.0, 0.0, clearance
	)


## A single flat slab with its top face at y = 0, and nothing else.
##
## The crawl fixture. A room would put walls within tentacle reach on several sides at
## once, which is a fine cave and a poor test: every candidate direction then finds a
## surface and the "no surface within reach" branch never runs.
func _flat_floor(size: float = 40.0) -> void:
	_probe.add_solid(AABB(Vector3(-0.5 * size, -4.0, -0.5 * size), Vector3(size, 4.0, size)))


## A surface reading whose fan is exactly the hits given, as (direction, distance) pairs.
##
## HAND-BUILT RATHER THAN PROBED, because the steering functions are what is under test and
## real geometry would make each assertion about the geometry instead. A fan of two exact
## distances is checkable by eye; a fan produced by casting into a room is not.
##
## Normals face back along the probe direction, which is what a flat surface hit square on
## returns, and is the only sensible answer available without real geometry.
func _reading_of(hits: Array, enclosure: float = 0.0) -> NavSurfaceReading:
	var samples: Array[NavSurfaceSample] = []
	var nearest: NavSurfaceSample = null
	for hit: Array in hits:
		var direction: Vector3 = (hit[0] as Vector3).normalized()
		var distance: float = hit[1]
		var sample := NavSurfaceSample.make(direction, direction * distance, -direction, distance)
		samples.append(sample)
		if nearest == null or distance < nearest.distance:
			nearest = sample
	return NavSurfaceReading.make(samples, nearest, enclosure, Vector3.ZERO)


## A graph built by hand, bypassing the builder, so a test can state exactly which
## nodes and edges exist. Positions are node centres; edges are given as index pairs.
func _hand_graph(positions: Array, pairs: Array, clearance: float = 3.0) -> NavGraph:
	var graph := NavGraph.new()
	graph.configure(
		maxf(_config.node_separation, _config.edge_search_radius * 0.5),
		_config.chunk_size,
		_config.best_seconds_per_metre()
	)
	for at: Vector3 in positions:
		graph.add_node(at, clearance)
	for pair: Array in pairs:
		var from: NavNode = graph.node_at(pair[0])
		var to: NavNode = graph.node_at(pair[1])
		var distance: float = from.position.distance_to(to.position)
		graph.add_edge(
			NavEdge.make(
				pair[0],
				pair[1],
				NavEdge.Type.NORMAL_VOLUME,
				distance,
				clearance,
				_config.normal_travel_time(distance)
			)
		)
	return graph
