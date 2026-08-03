class_name WallNavmeshBaker
extends NavigationRegion3D

## Paints a navigation mesh over the walls and the ceiling as well as the floor.
##
## Recast bakes against an up vector: anything past agent_max_slope is not
## walkable and no setting makes a wall into a floor. So bake_navigation_mesh()
## cannot produce what a wall-crawler needs, and this assembles the mesh by hand.
##
## HOW: flood the open space with a uniform grid of cells, starting from a seed
## known to be inside it, then put one quad on every face where a reachable cell
## meets one that is not. That is the whole algorithm. What comes out is the inner
## surface of everything the marker can get to - floor, walls, ceiling, the inside
## of a junction, the shaft - as a single welded sheet.
##
## WHY A GRID, rather than tessellating each wall in turn. Polygons in one
## NavigationMesh connect only where they share an edge, and the map matches edges
## by vertex POSITION. Cut each surface on a grid of its own and no two ever agree
## where their shared edge is subdivided, so a T-junction comes out as four
## rectangles that visibly touch and cannot be crossed. Here every quad corner is
## a point on one global lattice, so anything that meets, welds - and junctions,
## bends and shafts need no special case at all. An earlier version of this file
## enumerated the faces of a box room from constants; it could not have expressed
## this network.
##
## It knows nothing about corridors. It asks the physics world what is solid, so
## geometry can be added, moved or bent without touching this file.

signal baked

## The six face directions, which are also the six neighbours of a cell.
const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

## The four corners of a face, as (u, v) picks between a cell's low and high
## bounds. In order, so the quad is a ring rather than a bowtie.
const CORNER_PICKS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
]

## Grid that vertex positions are snapped to before being used as a dictionary
## key. Every corner is a multiple of the cell size, so equal positions are
## already bit-identical; this only guards against that stopping being true.
const WELD_GRID := 0.0001

## How many physics frames to keep re-offering the mesh to the navigation server
## before giving up and complaining. See _await_map_sync.
const SYNC_ATTEMPTS := 40

## How close the witness query has to land before the mesh counts as live.
const SYNC_TOLERANCE := 2.0

@export var cell: float = ChaseKnobs.NAVMESH_CELL
@export var openness_radius: float = ChaseKnobs.NAVMESH_OPENNESS_RADIUS
@export_flags_3d_physics var probe_mask: int = ChaseKnobs.NAVMESH_PROBE_MASK
@export var cell_size: float = ChaseKnobs.NAVMESH_CELL_SIZE
@export var max_cells: int = ChaseKnobs.NAVMESH_MAX_CELLS

var _open: Dictionary = {}
var _solid: Dictionary = {}
var _vertices: PackedVector3Array = PackedVector3Array()
var _polygons: Array[PackedInt32Array] = []
var _vertex_ids: Dictionary = {}
var _witness: Vector3 = Vector3.ZERO
var _leaked: bool = false


## Build the mesh and hand it to the server. Does not return until the mesh is
## live on the navigation map.
##
## MUST NOT be called before the corridors' collision exists. ChaseCorridorGenerator
## raises a CSGCombiner3D in _ready() and its trimesh collider only reaches the
## physics world once the CSG has processed, so a bake on frame zero probes an
## empty world, finds no surface anywhere, and produces a mesh of nothing at all
## without erroring. The prototype root awaits two physics frames first.
##
## `seed_point` has to be in open space - the player's spawn is the natural
## choice. `bounds` fences the fill; see the note on it in the generator.
func bake_network(seed_point: Vector3, bounds: AABB) -> void:
	_open.clear()
	_solid.clear()
	_vertex_ids.clear()
	_polygons.clear()
	_vertices = PackedVector3Array()
	_witness = Vector3.ZERO
	_leaked = false

	var space := get_world_3d().direct_space_state
	_flood(seed_point, bounds, space)
	_emit_faces()
	_commit()
	await _await_map_sync()
	baked.emit()


func stats() -> Dictionary:
	return {"cells": _open.size(), "quads": _polygons.size(), "leaked": _leaked}


## Every polygon edge as a flat run of line endpoints, for the debug overlay.
func debug_edges() -> PackedVector3Array:
	var edges := PackedVector3Array()
	for polygon: PackedInt32Array in _polygons:
		for i: int in polygon.size():
			edges.append(_vertices[polygon[i]])
			edges.append(_vertices[polygon[(i + 1) % polygon.size()]])
	return edges


# --- Flood fill ------------------------------------------------------------


## Breadth-first over the grid from a seed, collecting every cell the marker
## could actually get to.
##
## Reachability, not just emptiness, and the difference is load-bearing. A cell
## one step outside the hull is empty space too - the void beyond the corridor -
## and testing cells in isolation would march the fill straight through the wall
## and out into infinity. So every step also casts between the two cell centres:
## a neighbour is only taken if there is nothing in the way of getting to it.
##
## A failed passage test does NOT mark the neighbour solid. Being unreachable from
## one side says nothing about the other, and a cell round the far side of a
## corner is reached on a later pop.
func _flood(seed_point: Vector3, bounds: AABB, space: PhysicsDirectSpaceState3D) -> void:
	var start := _cell_at(seed_point)
	if not _cell_is_open(_center(start), space):
		push_warning(
			"WallNavmeshBaker: seed %v is not in open space, so nothing was baked." % seed_point
		)
		return

	_open[start] = true
	var queue: Array[Vector3i] = [start]
	var head := 0

	while head < queue.size():
		if _open.size() > max_cells:
			_leaked = true
			push_warning(
				(
					(
						"WallNavmeshBaker: the fill passed %d cells and was stopped. "
						+ "The hull most likely has a hole in it."
					)
					% max_cells
				)
			)
			return

		var current: Vector3i = queue[head]
		head += 1
		var from := _center(current)

		for step: Vector3i in NEIGHBOURS:
			var next: Vector3i = current + step
			if _open.has(next) or _solid.has(next):
				continue
			var to := _center(next)
			if not bounds.has_point(to):
				_solid[next] = true
				continue
			if not _cell_is_open(to, space):
				_solid[next] = true
				continue
			if not _passage_clear(from, to, space):
				continue
			_open[next] = true
			queue.append(next)


func _cell_is_open(point: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = openness_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = probe_mask
	return space.intersect_shape(query, 1).is_empty()


func _passage_clear(from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, probe_mask)
	return space.intersect_ray(query).is_empty()


func _cell_at(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / cell), floori(point.y / cell), floori(point.z / cell))


func _center(grid_cell: Vector3i) -> Vector3:
	return (Vector3(grid_cell) + Vector3.ONE * 0.5) * cell


# --- Surface extraction ----------------------------------------------------


## One quad per open-meets-solid face. Each face belongs to exactly one reachable
## cell and one unreachable neighbour, so no face can be emitted twice and no edge
## ends up with more polygons on it than the navigation map will merge.
func _emit_faces() -> void:
	for current: Vector3i in _open:
		var low := Vector3(current) * cell
		var high := low + Vector3.ONE * cell
		for step: Vector3i in NEIGHBOURS:
			if _open.has(current + step):
				continue
			# Pointing out of the wall and into the room the creature is in.
			var normal := -Vector3(step)
			_emit_quad(_face_corners(low, high, step), normal)
			if _polygons.size() == 1:
				# A point the finished mesh must be able to answer for, taken
				# from a face that actually exists rather than guessed at.
				_witness = (low + high) * 0.5 + Vector3(step) * cell * 0.5 + normal * cell * 0.25


func _face_corners(low: Vector3, high: Vector3, step: Vector3i) -> Array[Vector3]:
	var axis := _axis_of(step)
	var plane: float = high[axis] if step[axis] > 0 else low[axis]
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3

	var corners: Array[Vector3] = []
	for pick: Vector2i in CORNER_PICKS:
		var point := Vector3.ZERO
		point[axis] = plane
		point[u] = high[u] if pick.x == 1 else low[u]
		point[v] = high[v] if pick.y == 1 else low[v]
		corners.append(point)
	return corners


func _axis_of(step: Vector3i) -> int:
	if step.x != 0:
		return 0
	return 1 if step.y != 0 else 2


# --- Mesh assembly ---------------------------------------------------------


## Wound so the polygon's own normal agrees with the face it came from, by
## measuring rather than by reasoning about which axis pair flips the sign.
func _emit_quad(corners: Array[Vector3], normal: Vector3) -> void:
	var order := PackedInt32Array([0, 1, 2, 3])
	var cross := (corners[1] - corners[0]).cross(corners[2] - corners[1])
	if cross.dot(normal) < 0.0:
		order = PackedInt32Array([3, 2, 1, 0])

	var polygon := PackedInt32Array()
	for index: int in order:
		polygon.append(_vertex_id(corners[index]))
	_polygons.append(polygon)


func _vertex_id(point: Vector3) -> int:
	var key := point.snappedf(WELD_GRID)
	if _vertex_ids.has(key):
		return _vertex_ids[key] as int
	var id := _vertices.size()
	_vertices.append(point)
	_vertex_ids[key] = id
	return id


## Assigned, never baked. bake_navigation_mesh() would throw all of this away and
## run Recast over the same geometry with the same up-vector problem.
func _commit() -> void:
	var mesh := NavigationMesh.new()
	# Matched to the map's own quantisation, which is what it hashes polygon
	# edges with. A mismatch here reads as a mesh that looks right in the debug
	# overlay and cannot be pathed across.
	mesh.cell_size = cell_size
	mesh.cell_height = cell_size
	mesh.vertices = _vertices
	for polygon: PackedInt32Array in _polygons:
		mesh.add_polygon(polygon)
	navigation_mesh = mesh


## Wait until the navigation server has actually taken the mesh, re-offering it
## once per frame until it does.
##
## This is not belt and braces, it is load-bearing, and it was measured rather
## than assumed. Assigning `navigation_mesh` this early leaves the region on the
## map, enabled, holding a mesh with the right polygon count and a matching cell
## size - and every query against that map still answers the origin. Nothing
## errors. Handing the very same mesh object to the server thirty-odd frames later
## makes it live, so the mesh was never the problem and neither was the API: the
## bake simply lands before the map is ready to receive it, and the region's own
## dirty flag does not survive whatever happens in between.
##
## Hence a witness rather than a frame count. A fixed delay would be a guess that
## holds until the network gets bigger or the machine gets slower; asking the map
## a question only a live mesh can answer is the same check the failure would fail.
func _await_map_sync() -> void:
	if _polygons.is_empty():
		return

	var map := get_navigation_map()
	for _attempt: int in SYNC_ATTEMPTS:
		await get_tree().physics_frame
		var landed := NavigationServer3D.map_get_closest_point(map, _witness)
		if landed.distance_to(_witness) < SYNC_TOLERANCE:
			return
		NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)

	push_warning(
		(
			"WallNavmeshBaker: %d quads never reached the navigation map after %d frames."
			% [_polygons.size(), SYNC_ATTEMPTS]
		)
	)
