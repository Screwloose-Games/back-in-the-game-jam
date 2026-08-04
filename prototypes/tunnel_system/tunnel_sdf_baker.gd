class_name TunnelSdfBaker
extends RefCounted

## Turns a TunnelNetwork's signed distance field into chunked, watertight,
## inward-facing cave geometry.
##
## NAIVE SURFACE NETS, NOT MARCHING CUBES. Both produce a closed isosurface;
## surface nets gets there without a 256-entry case table. That matters here for
## one specific reason: in this repo a hole in the shell is a catastrophic bug
## class - tentacle_crawler/CLAUDE.md documents a creature hauling itself out
## through one - and a hole caused by a mistranscribed table row looks EXACTLY
## like a winding bug, which is the other trap this file has to defend against.
## Two indistinguishable symptoms with four thousand candidate causes is not a
## debugging position worth accepting to save a few triangles.
##
## Surface nets has no configuration that can fail to close: one vertex per
## sign-changing cell, one quad per sign-changing grid edge joining the four
## cells around it. The quad is defined by ADJACENCY, not by a lookup, so there
## is nothing to get wrong per-case. It costs a rounder silhouette, which for a
## rock cave is the right direction anyway.

## The eight corners of a cell, indexed so corner k is (k&1, k>>1&1, k>>2&1).
const CORNER_OFFSETS: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 1),
	Vector3i(0, 1, 1),
	Vector3i(1, 1, 1),
]

## The twelve cell edges as corner-index pairs: the four along X, then Y, then Z.
const CELL_EDGES: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(2, 3),
	Vector2i(4, 5),
	Vector2i(6, 7),
	Vector2i(0, 2),
	Vector2i(1, 3),
	Vector2i(4, 6),
	Vector2i(5, 7),
	Vector2i(0, 4),
	Vector2i(1, 5),
	Vector2i(2, 6),
	Vector2i(3, 7),
]

## How far either side of its own surface a primitive enumerates candidate cells,
## in cells.
##
## The field is close to 1-Lipschitz, and a cell's corners are at most
## sqrt(3)/2 = 0.87 cells from its centre, so any cell containing a sign change
## has |field| <= 0.87 at its centre. 1.3 is that bound with room for the error
## the radius taper introduces. Raising it costs bake time and finds nothing;
## lowering it below 0.87 starts dropping surface cells, which is a hole.
const CANDIDATE_BAND := 1.3

var cells_considered := 0
var surface_cells := 0
var vertex_count := 0
var triangle_count := 0
var skipped_quads := 0
var winding_agreement := 0.0
var winding_flipped := false
var bake_seconds := 0.0

var _network: TunnelNetwork
var _corners: Dictionary = {}
var _vertex_index: Dictionary = {}
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _indices := PackedInt32Array()
var _triangle_cells: Array[Vector3i] = []
var _rng := RandomNumberGenerator.new()


## Builds the isosurface. Returns an empty string on success, or the reason it
## refused to emit - the same posture as build_corridor_run.gd. A baker that
## emits a broken cave and lets a later check find it wastes the bake.
func bake(network: TunnelNetwork) -> String:
	var started := Time.get_ticks_msec()
	_network = network
	_rng.seed = 20260803

	var candidates := _collect_candidates()
	cells_considered = candidates.size()
	_build_vertices(candidates)
	if _vertices.is_empty():
		return "the field produced no surface cells at all"
	_build_quads()
	if triangle_count == 0:
		return "surface cells produced no triangles"

	var error := _resolve_winding()
	bake_seconds = float(Time.get_ticks_msec() - started) / 1000.0
	return error


## The baked geometry split into CHUNK_SIZE cubes, as chunk key -> ArrayMesh.
##
## One mesh for the whole 200 m network would never be frustum-culled and would
## hand Jolt a single enormous BVH; one mesh per route would give sixteen nodes
## with overlapping 150 m AABBs, which culls no better. Chunks sized to the
## camera's far plane let the far plane do the work.
##
## Seams are watertight for free: every corner sample is field(world_position) on
## ONE global lattice keyed by global cell index, so two neighbouring chunks
## compute bit-identical values for the cells they share and emit bit-identical
## vertices. There is no stitching pass because there is nothing to stitch.
func chunk_meshes() -> Dictionary:
	var buckets: Dictionary = {}
	for triangle: int in triangle_count:
		var key := _chunk_key(_triangle_cells[triangle])
		var bucket: PackedInt32Array = buckets.get(key, PackedInt32Array())
		bucket.append(triangle)
		buckets[key] = bucket

	var meshes: Dictionary = {}
	for key: Vector3i in buckets:
		var triangles: PackedInt32Array = buckets[key]
		var remap: Dictionary = {}
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for triangle: int in triangles:
			for corner: int in 3:
				var global_index := _indices[triangle * 3 + corner]
				if not remap.has(global_index):
					remap[global_index] = vertices.size()
					vertices.append(_vertices[global_index])
					normals.append(_normals[global_index])
				indices.append(remap[global_index])
		if indices.size() < 3:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[key] = mesh
	return meshes


## Every cell that might straddle the surface, found by asking each primitive to
## enumerate its OWN shell rather than by sweeping the 200 m box.
##
## The box at CELL_SIZE is 8.8 million cells and the ones that produce triangles
## are under 1% of it. Per-primitive enumeration is exhaustive despite being
## sparse: the field is a minimum, so if field(p) is near zero then the primitive
## achieving that minimum has its own distance near zero at p, and therefore
## enumerated p itself.
func _collect_candidates() -> Dictionary:
	var cell := TunnelKnobs.CELL_SIZE
	var band := cell * CANDIDATE_BAND
	var candidates: Dictionary = {}

	for route: Dictionary in _network.routes:
		var points: PackedVector3Array = route["points"]
		var radii: PackedFloat32Array = route["radii"]
		for i: int in points.size() - 1:
			var a := points[i]
			var ab := points[i + 1] - a
			var len_sq := ab.length_squared()
			if len_sq <= 0.0:
				continue
			var inv_len_sq := 1.0 / len_sq
			var r0 := radii[i]
			var r1 := radii[i + 1]
			var box := AABB(a, Vector3.ZERO).expand(points[i + 1]).grow(maxf(r0, r1) + band)
			var lo := _cell_of(box.position)
			var hi := _cell_of(box.position + box.size)
			for x: int in range(lo.x, hi.x + 1):
				for y: int in range(lo.y, hi.y + 1):
					for z: int in range(lo.z, hi.z + 1):
						var centre := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * cell
						var t := clampf((centre - a).dot(ab) * inv_len_sq, 0.0, 1.0)
						var d := centre.distance_to(a + ab * t) - lerpf(r0, r1, t)
						if absf(d) <= band:
							candidates[Vector3i(x, y, z)] = true

	for i: int in _network.chamber_centers.size():
		var centre_point := _network.chamber_centers[i]
		var radius := _network.chamber_radii[i]
		var box := AABB(centre_point, Vector3.ZERO).grow(radius + band)
		var lo := _cell_of(box.position)
		var hi := _cell_of(box.position + box.size)
		for x: int in range(lo.x, hi.x + 1):
			for y: int in range(lo.y, hi.y + 1):
				for z: int in range(lo.z, hi.z + 1):
					var centre := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * cell
					if absf(centre.distance_to(centre_point) - radius) <= band:
						candidates[Vector3i(x, y, z)] = true

	return candidates


## One vertex per sign-changing cell, at the mean of its edge crossings.
func _build_vertices(candidates: Dictionary) -> void:
	for cell: Vector3i in candidates:
		var values := PackedFloat32Array()
		var negatives := 0
		for corner: int in 8:
			var value := _corner(cell + CORNER_OFFSETS[corner])
			values.append(value)
			if value < 0.0:
				negatives += 1
		if negatives == 0 or negatives == 8:
			continue

		var total := Vector3.ZERO
		var crossings := 0
		for edge: Vector2i in CELL_EDGES:
			var from_value := values[edge.x]
			var to_value := values[edge.y]
			if (from_value < 0.0) == (to_value < 0.0):
				continue
			var span := from_value - to_value
			var t := 0.5 if absf(span) < 1e-9 else from_value / span
			total += (_corner_position(cell + CORNER_OFFSETS[edge.x]).lerp(
				_corner_position(cell + CORNER_OFFSETS[edge.y]), clampf(t, 0.0, 1.0)
			))
			crossings += 1
		if crossings == 0:
			continue

		var position := total / float(crossings)
		_vertex_index[cell] = _vertices.size()
		_vertices.append(position)
		# The gradient of the real field, not of the polygonised surface. Smooth
		# across the whole cave with no seams at chunk boundaries, because it does
		# not know chunks exist.
		_normals.append(_network.air_normal(position))
	surface_cells = _vertices.size()
	vertex_count = _vertices.size()


## One quad per sign-changing grid edge, joining the four cells that share it.
func _build_quads() -> void:
	var axes: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	for cell: Vector3i in _vertex_index:
		for axis: int in 3:
			var step := axes[axis]
			var near := _corner(cell)
			var far := _corner(cell + step)
			if (near < 0.0) == (far < 0.0):
				continue
			var u := axes[(axis + 1) % 3]
			var v := axes[(axis + 2) % 3]
			var quad: Array[Vector3i] = [cell, cell - u, cell - u - v, cell - v]
			var ring := PackedInt32Array()
			var complete := true
			for corner_cell: Vector3i in quad:
				if not _vertex_index.has(corner_cell):
					complete = false
					break
				ring.append(_vertex_index[corner_cell])
			if not complete:
				# Cannot happen: a sign change on a grid edge means all four cells
				# around it straddle the surface and were therefore given a vertex.
				# Counted anyway, because if it ever does happen it is a HOLE, and
				# the bake refuses to emit rather than shipping one.
				skipped_quads += 1
				continue
			# Consistent orientation relative to which side the air is on. Whether
			# this un-reversed case ends up facing in or out is settled globally by
			# _resolve_winding, which measures it rather than assuming it.
			if near < 0.0:
				ring.reverse()
			_emit_quad(ring, cell)


## Surface-nets quads are NOT planar, and splitting one along its longer diagonal
## puts a visible crease down the middle of an otherwise smooth wall.
func _emit_quad(ring: PackedInt32Array, cell: Vector3i) -> void:
	var a := _vertices[ring[0]]
	var b := _vertices[ring[1]]
	var c := _vertices[ring[2]]
	var d := _vertices[ring[3]]
	if a.distance_squared_to(c) <= b.distance_squared_to(d):
		_add_triangle(ring[0], ring[1], ring[2], cell)
		_add_triangle(ring[0], ring[2], ring[3], cell)
	else:
		_add_triangle(ring[1], ring[2], ring[3], cell)
		_add_triangle(ring[1], ring[3], ring[0], cell)


func _add_triangle(i0: int, i1: int, i2: int, cell: Vector3i) -> void:
	_indices.append(i0)
	_indices.append(i1)
	_indices.append(i2)
	_triangle_cells.append(cell)
	triangle_count += 1


## MEASURE the winding against the field instead of trusting the derivation.
##
## This is the trap that has already cost this repo an afternoon, and it is worth
## restating why it is worth a whole pass: Godot treats CLOCKWISE winding as
## front-facing, and ConcavePolygonShape3D.backface_collision defaults to false.
## An outward-wound cave renders perfectly from outside, errors nowhere, and is
## INVISIBLE TO EVERY RAYCAST - so the creature's probes, the ore bounces and the
## verifier's own clearance checks all report open space in solid rock.
##
## backface_collision is deliberately left at false, matching build_corridor_run.
## Turning it on would paper over exactly this failure.
func _resolve_winding() -> String:
	winding_agreement = _measure_agreement()
	if winding_agreement < 0.5:
		for triangle: int in triangle_count:
			var base := triangle * 3
			var swap := _indices[base + 1]
			_indices[base + 1] = _indices[base + 2]
			_indices[base + 2] = swap
		winding_flipped = true
		winding_agreement = _measure_agreement()

	if winding_agreement < TunnelKnobs.WINDING_MIN_AGREEMENT:
		return (
			"only %.1f%% of triangles face the air after correction (need %.1f%%) - the surface is locally inconsistent, which is a hole rather than a winding error"
			% [winding_agreement * 100.0, TunnelKnobs.WINDING_MIN_AGREEMENT * 100.0]
		)
	return ""


## Fraction of sampled triangles whose FRONT face points into the bore.
##
## Godot's front face is the clockwise one, which under the right-hand cross
## product is the negated geometric normal - so a triangle faces the air when
## -(edge1 x edge2) agrees with the field's air-facing normal.
func _measure_agreement() -> float:
	var samples := mini(TunnelKnobs.WINDING_SAMPLE_COUNT, triangle_count)
	if samples == 0:
		return 0.0
	var agreed := 0
	for sample: int in samples:
		var triangle := _rng.randi_range(0, triangle_count - 1)
		var base := triangle * 3
		var a := _vertices[_indices[base]]
		var b := _vertices[_indices[base + 1]]
		var c := _vertices[_indices[base + 2]]
		var geometric := (b - a).cross(c - a)
		if geometric.length_squared() < 1e-12:
			agreed += 1
			continue
		var centroid := (a + b + c) / 3.0
		if (-geometric.normalized()).dot(_network.air_normal(centroid)) > 0.0:
			agreed += 1
	return float(agreed) / float(samples)


func _corner(index: Vector3i) -> float:
	var cached: Variant = _corners.get(index)
	if cached != null:
		return cached
	var value := _network.field(_corner_position(index))
	_corners[index] = value
	return value


func _corner_position(index: Vector3i) -> Vector3:
	return Vector3(index) * TunnelKnobs.CELL_SIZE


func _cell_of(point: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(point.x / TunnelKnobs.CELL_SIZE)),
		int(floor(point.y / TunnelKnobs.CELL_SIZE)),
		int(floor(point.z / TunnelKnobs.CELL_SIZE))
	)


func _chunk_key(cell: Vector3i) -> Vector3i:
	var per_chunk := int(round(TunnelKnobs.CHUNK_SIZE / TunnelKnobs.CELL_SIZE))
	return Vector3i(
		int(floor(float(cell.x) / float(per_chunk))),
		int(floor(float(cell.y) / float(per_chunk))),
		int(floor(float(cell.z) / float(per_chunk)))
	)
