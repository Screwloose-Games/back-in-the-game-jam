extends Node

## Headless check that the tunnel system stands up. Run it with:
##
##     godot --headless --path <root> res://prototypes/tunnel_system/tools/verify_tunnel_system.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare. Nodes
## added during SceneTree._initialize() never receive _ready(), so a bare script
## harness prints nothing and exits 0 - which is indistinguishable from a pass.
## The project's main scene is the main menu, so anything that does not name a
## scene boots that instead and this never runs.
##
## [traverse] is the check this file exists for. "The curves share a junction
## constant" is a claim about a data structure; "a player-sized sphere fits along
## every metre of every centreline against the BAKED COLLISION" is a claim about
## the level, and only the second one is what the brief asked for.
##
## [winding] is the check that catches the failure everything else passes. An
## outward-wound shell renders perfectly and is invisible to every raycast, so
## clearance probes report open space in solid rock and every other check here
## agrees the level is fine.

const SCENE_PATH := "res://prototypes/tunnel_system/tunnel_system_prototype.tscn"

## Metres between sphere-fit samples along a centreline.
const TRAVERSE_STEP := 0.5

## Metres between ray-fan stations. Coarser than the sphere fit because fourteen
## rays cost more than one shape query and the bore does not change that fast.
const PROBE_STEP := 3.0

## How far a probe ray is allowed to travel before a miss counts as a hole. The
## shell is closed - every dead end is capped by its own capsule hemisphere - so
## a ray that escapes has either found a hole or is passing through a wall that
## physics cannot see.
const PROBE_RANGE := 250.0

## Tolerance between the bore a route was authored at and the bore measured by
## the ray fan. Fourteen discrete directions under-measure a round tube, and the
## isosurface rounds corners, so this is not tight.
const BORE_TOLERANCE := 0.45

var _failures := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		print("FAIL [load] could not load %s" % SCENE_PATH)
		get_tree().quit(1)
		return

	var scene := packed.instantiate() as TunnelSystemPrototype
	add_child(scene)
	# Let the collision shapes register with the physics server before anything
	# queries them; a shape query one frame too early answers "open space".
	for _i: int in 8:
		await get_tree().physics_frame

	var network: TunnelNetwork = scene.network
	var space := get_viewport().world_3d.direct_space_state
	var geometry := scene.get_node("Geometry")

	_check_graph(network)
	_check_spawn(space)
	_check_stops(space)
	_check_traverse(network, space)
	_check_probes(network, space)
	_check_extent(geometry)
	_report_budget(geometry, network)

	print("")
	if _failures == 0:
		print("PASS - %d checks, no failures" % _checks)
	else:
		print("FAIL - %d failures across %d checks" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


## Every junction reachable from the spawn by walking the route graph. Catches a
## mistyped endpoint that split one junction into two, which is invisible in the
## editor because the two curves still visually touch.
func _check_graph(network: TunnelNetwork) -> void:
	var reached := network.reachable_junctions(TunnelKnobs.SPAWN_POSITION).size()
	var total := network.junctions.size()
	_assert("graph", reached == total, "%d of %d junctions reachable from spawn" % [reached, total])
	var orphans := network.unreachable_routes(TunnelKnobs.SPAWN_POSITION)
	_assert(
		"graph",
		orphans.is_empty(),
		(
			"every route joins the network"
			if orphans.is_empty()
			else "orphaned routes: %s" % ", ".join(orphans)
		)
	)


func _check_spawn(space: PhysicsDirectSpaceState3D) -> void:
	var blocked := _sphere_blocked(space, TunnelKnobs.SPAWN_POSITION)
	_assert(
		"spawn",
		not blocked,
		(
			"spawn at %v is in solid rock" % TunnelKnobs.SPAWN_POSITION
			if blocked
			else "spawn at %v is clear" % TunnelKnobs.SPAWN_POSITION
		)
	)


## Every teleport stop lands in open space.
##
## A stop whose coordinate drifts into rock does not error - it renders as a
## black screen, which reads as a broken build rather than as a bad number. That
## already happened once to a screenshot viewpoint picked by eye.
func _check_stops(space: PhysicsDirectSpaceState3D) -> void:
	var buried := PackedStringArray()
	for stop: Dictionary in TunnelKnobs.TELEPORT_STOPS:
		if _sphere_blocked(space, stop["position"]):
			buried.append("%s at %v" % [stop["label"], stop["position"]])
	_assert(
		"stops",
		buried.is_empty(),
		(
			"all %d teleport stops are in open space" % TunnelKnobs.TELEPORT_STOPS.size()
			if buried.is_empty()
			else "buried in rock: %s" % "; ".join(buried)
		)
	)


## A player-sized sphere fitted at every TRAVERSE_STEP along every centreline,
## against the baked collision. This is the requirement - "the tunnels connect,
## so the player can traverse from one throughout it" - stated as a measurement.
func _check_traverse(network: TunnelNetwork, space: PhysicsDirectSpaceState3D) -> void:
	var samples := 0
	var blocked_routes := PackedStringArray()
	var worst_position := Vector3.ZERO
	for route: Dictionary in network.routes:
		var points: PackedVector3Array = route["points"]
		var blocked := false
		for i: int in points.size() - 1:
			var span := points[i].distance_to(points[i + 1])
			var steps := maxi(int(ceil(span / TRAVERSE_STEP)), 1)
			for step: int in steps:
				var at := points[i].lerp(points[i + 1], float(step) / float(steps))
				samples += 1
				if _sphere_blocked(space, at):
					if not blocked:
						worst_position = at
					blocked = true
		if blocked:
			blocked_routes.append(route["name"])

	_assert(
		"traverse",
		blocked_routes.is_empty(),
		(
			(
				"a %.1f m sphere fits at all %d centreline samples"
				% [(TunnelKnobs.PLAYER_RADIUS + TunnelKnobs.CLEARANCE_MARGIN) * 2.0, samples]
			)
			if blocked_routes.is_empty()
			else ("blocked in %s (first at %v)" % [", ".join(blocked_routes), worst_position])
		)
	)


## The ray fan: proves the shell is opaque to physics, and measures the bore that
## actually got baked against the bore that was authored.
func _check_probes(network: TunnelNetwork, space: PhysicsDirectSpaceState3D) -> void:
	var directions := _fan_directions()
	var misses := 0
	var stations := 0
	var narrow := PackedStringArray()
	var creature_routes := PackedStringArray()

	for route: Dictionary in network.routes:
		var points: PackedVector3Array = route["points"]
		var radii: PackedFloat32Array = route["radii"]
		var route_min := INF
		var authored_min := INF
		var travelled := 0.0
		for i: int in points.size():
			if i > 0:
				travelled += points[i - 1].distance_to(points[i])
			if travelled < PROBE_STEP and i > 0 and i < points.size() - 1:
				continue
			travelled = 0.0
			stations += 1
			var nearest := INF
			for direction: Vector3 in directions:
				var query := PhysicsRayQueryParameters3D.create(
					points[i], points[i] + direction * PROBE_RANGE, 1
				)
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					misses += 1
					continue
				nearest = minf(nearest, points[i].distance_to(hit["position"]))
			if nearest < INF:
				route_min = minf(route_min, nearest)
			authored_min = minf(authored_min, radii[i])

		if route_min < INF:
			if route_min < authored_min - BORE_TOLERANCE:
				narrow.append(
					(
						"%s measured %.2f m against %.2f m authored"
						% [route["name"], route_min, authored_min]
					)
				)
			if route_min * 2.0 >= TunnelKnobs.CREATURE_MIN_PASSAGE:
				creature_routes.append(route["name"])

	_assert(
		"winding",
		misses == 0,
		(
			"all %d probe stations are enclosed by physics-visible walls" % stations
			if misses == 0
			else (
				"%d of %d rays escaped the shell - the walls are wound outward and are invisible to raycasts"
				% [misses, stations * directions.size()]
			)
		)
	)
	_assert(
		"bore",
		narrow.is_empty(),
		(
			"every route baked to its authored bore within %.2f m" % BORE_TOLERANCE
			if narrow.is_empty()
			else "; ".join(narrow)
		)
	)
	print(
		(
			"      passable to the crawler (>= %.1f m): %s"
			% [
				TunnelKnobs.CREATURE_MIN_PASSAGE,
				", ".join(creature_routes) if not creature_routes.is_empty() else "none",
			]
		)
	)


func _check_extent(geometry: Node) -> void:
	var box := AABB()
	var started := false
	for child: Node in geometry.get_children():
		var mesh_node := child.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null:
			continue
		var piece := mesh_node.get_aabb()
		box = piece if not started else box.merge(piece)
		started = true

	var half := TunnelKnobs.WORLD_EXTENT * 0.5
	var low := box.position
	var high := box.position + box.size
	var inside := (
		low.x >= -half
		and high.x <= half
		and low.z >= -half
		and high.z <= half
		and low.y >= -TunnelKnobs.WORLD_EXTENT
		and high.y <= 0.0
	)
	_assert(
		"extent",
		inside,
		(
			(
				"%.0f x %.0f x %.0f m, inside the %.0f m box"
				% [box.size.x, box.size.y, box.size.z, TunnelKnobs.WORLD_EXTENT]
			)
			if inside
			else (
				"geometry spans %v..%v, outside the %.0f m box"
				% [low, high, TunnelKnobs.WORLD_EXTENT]
			)
		)
	)


func _report_budget(geometry: Node, network: TunnelNetwork) -> void:
	var triangles := 0
	var chunks := 0
	var colliders := 0
	for child: Node in geometry.get_children():
		chunks += 1
		var mesh_node := child.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node != null and mesh_node.mesh is ArrayMesh:
			var mesh := mesh_node.mesh as ArrayMesh
			for surface: int in mesh.get_surface_count():
				triangles += mesh.surface_get_array_index_len(surface) / 3
		var collider := child.get_node_or_null("Collision") as CollisionShape3D
		if collider != null and collider.shape != null:
			colliders += 1

	_assert("budget", colliders == chunks, "%d of %d chunks carry collision" % [colliders, chunks])
	print(
		(
			"      %d triangles across %d chunks, %.0f m of centreline in %d routes"
			% [triangles, chunks, network.total_length(), network.routes.size()]
		)
	)


func _sphere_blocked(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = TunnelKnobs.PLAYER_RADIUS + TunnelKnobs.CLEARANCE_MARGIN
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1
	return not space.intersect_shape(query, 1).is_empty()


## Six axes plus the eight body diagonals. Fourteen is the same fan the crawler's
## corridor probe uses, and for the same reason: it is the cheapest set that
## cannot be fooled by a tube whose axis happens to line up with an axis.
func _fan_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	for x: int in [-1, 1]:
		for y: int in [-1, 1]:
			for z: int in [-1, 1]:
				directions.append(Vector3(x, y, z).normalized())
	return directions


## Prints PASS or FAIL for one check and counts it. The count is what the summary
## compares against - a summary that prints PASS unconditionally will print it
## directly underneath its own failures.
func _assert(tag: String, passed: bool, detail: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("%s [%s] %s" % ["PASS" if passed else "FAIL", tag, detail])
