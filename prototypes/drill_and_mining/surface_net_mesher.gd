class_name SurfaceNetMesher
extends RefCounted

## Turns one sub-chunk of a VoxelField into a faceted triangle soup.
##
## NAIVE SURFACE NETS, NOT MARCHING CUBES - the same choice, for the same reason,
## as prototypes/tunnel_system/tunnel_sdf_baker.gd, whose header is worth reading:
## surface nets has no 256-entry case table and therefore no case that can be
## mistranscribed into a hole, and a hole looks exactly like a winding bug. That
## baker is a sparse Dictionary-based one-shot over a whole tunnel network; this
## is a dense one over a 10-cell cube that has to run several times a frame, so
## the algorithm ports and the code does not.
##
## One vertex per cell whose eight corners disagree on a sign, placed at the mean
## of the crossings on that cell's edges. One quad per grid edge that changes
## sign, joining the vertices of the four cells around it. The quad is defined by
## ADJACENCY rather than by a lookup, so there is nothing to get wrong per case.
##
## FACETED, so vertices are never shared: every triangle carries its own three
## with one flat normal. That costs three times the vertices and buys the hard
## angular crater walls the prototype is after, plus it makes the same array
## usable as the collision shape's face list with no second pass.

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

## The four cells around a grid edge, as offsets from the edge's low corner, in
## counter-clockwise order seen from the positive end of that axis. Adjacency,
## not a case table - this is the whole of the quad rule.
const RING_ABOUT_X: Array[Vector3i] = [
	Vector3i(0, -1, -1), Vector3i(0, 0, -1), Vector3i(0, 0, 0), Vector3i(0, -1, 0)
]
const RING_ABOUT_Y: Array[Vector3i] = [
	Vector3i(-1, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 0, -1)
]
const RING_ABOUT_Z: Array[Vector3i] = [
	Vector3i(-1, -1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 0), Vector3i(-1, 0, 0)
]

var _field: VoxelField
var _from: Vector3i
var _span: Vector3i
var _positions := PackedVector3Array()
var _present := PackedByteArray()


## Every triangle of one sub-chunk, three unshared vertices each, in the field's
## local space. Empty when the sub-chunk holds no surface, which is most of them
## most of the time.
##
## `normals_out` is filled to the same length, one flat normal per vertex.
func build(
	field: VoxelField, subchunk: Vector3i, normals_out: PackedVector3Array
) -> PackedVector3Array:
	_field = field
	var low := subchunk * field.subchunk_cells
	var high := (low + Vector3i.ONE * field.subchunk_cells).mini(field.resolution)

	# Vertices are needed one cell OUTSIDE this sub-chunk on the low side: a quad
	# owned by the edge at `low` reaches back to the cells at `low - 1`. Without
	# the skirt every sub-chunk boundary would be a crack.
	_from = (low - Vector3i.ONE).maxi(0)
	_span = high - _from
	if _span.x <= 0 or _span.y <= 0 or _span.z <= 0:
		return PackedVector3Array()

	_positions.resize(_span.x * _span.y * _span.z)
	_present.resize(_positions.size())
	var found_any := _place_vertices()

	var triangles := PackedVector3Array()
	normals_out.clear()
	if not found_any:
		return triangles
	_emit_quads(low, high, triangles, normals_out)
	return triangles


## One vertex per sign-changing cell, at the mean of its edge crossings. Returns
## false when the sub-chunk is entirely solid or entirely empty, which skips the
## quad pass outright.
func _place_vertices() -> bool:
	var found_any := false
	var corners := PackedFloat32Array()
	corners.resize(8)
	for z in _span.z:
		for y in _span.y:
			for x in _span.x:
				var cell := _from + Vector3i(x, y, z)
				var negatives := 0
				for corner in 8:
					var offset: Vector3i = CORNER_OFFSETS[corner]
					var value := _field.corner_value(
						cell.x + offset.x, cell.y + offset.y, cell.z + offset.z
					)
					corners[corner] = value
					if value < 0.0:
						negatives += 1
				var index := x + _span.x * (y + _span.y * z)
				if negatives == 0 or negatives == 8:
					_present[index] = 0
					continue
				_positions[index] = _crossing_mean(cell, corners)
				_present[index] = 1
				found_any = true
	return found_any


func _crossing_mean(cell: Vector3i, corners: PackedFloat32Array) -> Vector3:
	var total := Vector3.ZERO
	var crossings := 0
	for edge: Vector2i in CELL_EDGES:
		var near: float = corners[edge.x]
		var far: float = corners[edge.y]
		if (near < 0.0) == (far < 0.0):
			continue
		# The corners straddle zero, so the denominator cannot vanish.
		var along := near / (near - far)
		var near_offset: Vector3i = CORNER_OFFSETS[edge.x]
		var far_offset: Vector3i = CORNER_OFFSETS[edge.y]
		total += (
			_field
			. corner_position(
				cell.x + near_offset.x, cell.y + near_offset.y, cell.z + near_offset.z
			)
			. lerp(
				_field.corner_position(
					cell.x + far_offset.x, cell.y + far_offset.y, cell.z + far_offset.z
				),
				along
			)
		)
		crossings += 1
	if crossings == 0:
		return _field.corner_position(cell.x, cell.y, cell.z)
	return total / float(crossings)


## One quad per sign-changing grid edge owned by this sub-chunk. Ownership is by
## the edge's low corner, so every quad in the field is emitted exactly once even
## though neighbouring sub-chunks both computed the vertices around it.
func _emit_quads(
	low: Vector3i, high: Vector3i, triangles: PackedVector3Array, normals: PackedVector3Array
) -> void:
	for z in range(low.z, high.z):
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				var corner := Vector3i(x, y, z)
				var here := _field.corner_value(x, y, z)
				var solid := here < 0.0
				if x < _field.resolution and solid != (_field.corner_value(x + 1, y, z) < 0.0):
					_emit_ring(corner, RING_ABOUT_X, solid, triangles, normals)
				if y < _field.resolution and solid != (_field.corner_value(x, y + 1, z) < 0.0):
					_emit_ring(corner, RING_ABOUT_Y, solid, triangles, normals)
				if z < _field.resolution and solid != (_field.corner_value(x, y, z + 1) < 0.0):
					_emit_ring(corner, RING_ABOUT_Z, solid, triangles, normals)


## Two triangles across the four cells around one edge.
##
## `solid_at_low` decides which way the surface faces: the rock is on the
## negative-value side, so when the low corner is the solid one the outward
## direction is along the axis and the ring is already in order, and when it is
## not the ring is walked backwards.
##
## Godot's front faces are CLOCKWISE, and the rings above are counter-clockwise
## seen from outside, so the triangles are emitted with their middle two indices
## swapped. Get this wrong and the node renders as a hole in the world that still
## lights and shadows correctly from behind.
func _emit_ring(
	corner: Vector3i,
	ring: Array[Vector3i],
	solid_at_low: bool,
	triangles: PackedVector3Array,
	normals: PackedVector3Array
) -> void:
	var quad := PackedVector3Array()
	quad.resize(4)
	for step in 4:
		var offset: Vector3i = ring[step if solid_at_low else 3 - step]
		var cell := corner + offset
		var index := _local_index(cell)
		if index < 0 or _present[index] == 0:
			# One of the four cells has no vertex. On a closed field this cannot
			# happen inside the grid; at the very edge of it, it can, and the
			# honest answer is to leave the hole rather than invent a corner.
			return
		quad[step] = _positions[index]

	var normal := (quad[1] - quad[0]).cross(quad[2] - quad[0])
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	_add_triangle(quad[0], quad[2], quad[1], normal, triangles, normals)
	_add_triangle(quad[0], quad[3], quad[2], normal, triangles, normals)


func _add_triangle(
	first: Vector3,
	second: Vector3,
	third: Vector3,
	normal: Vector3,
	triangles: PackedVector3Array,
	normals: PackedVector3Array
) -> void:
	triangles.append(first)
	triangles.append(second)
	triangles.append(third)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


## Where a cell sits in this pass's local arrays, or -1 if it is outside them.
func _local_index(cell: Vector3i) -> int:
	var local := cell - _from
	if local.x < 0 or local.y < 0 or local.z < 0:
		return -1
	if local.x >= _span.x or local.y >= _span.y or local.z >= _span.z:
		return -1
	return local.x + _span.x * (local.y + _span.y * local.z)
