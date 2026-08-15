class_name PlayerTetherRopeMesh
extends RefCounted

## A tube of triangles laid over the points PlayerTetherRope simulates. Nothing
## here is physical — it only gives the chain a thickness it does not have. The
## mesh is rebuilt in place, so hand `read_mesh()` to a MeshInstance3D once.

## Faces around the tube's circumference.
var sides := 6
## Radius the rope is drawn at, in metres.
var radius := 0.05

var _mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
## Worked out only when the rope's point count changes, not every frame.
var _indices := PackedInt32Array()


## The mesh to hand a MeshInstance3D, in world space.
func read_mesh() -> ArrayMesh:
	return _mesh


## Redraws the tube over wherever the rope's points ended up this frame.
func rebuild(rope_points: PackedVector3Array) -> void:
	if rope_points.size() < 2:
		_mesh.clear_surfaces()
		return
	_build_tube(rope_points)

	var surface_arrays := []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = _vertices
	surface_arrays[Mesh.ARRAY_NORMAL] = _normals
	surface_arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)


## Lays a ring of vertices across the rope at each point. Neighbouring rings
## must agree on which way round their axes go or the tube creases, so each ring
## leans the previous one's axes onto its own cross-section. Both end rings draw
## in to nothing, which closes the tube off inside its anchors.
func _build_tube(rope_points: PackedVector3Array) -> void:
	var point_count := rope_points.size()
	var side_count := maxi(3, sides)
	_resize(point_count, side_count)

	var across := Vector3.ZERO
	for point_index: int in range(point_count):
		var along := _measure_rope_direction(rope_points, point_index)
		across -= along * across.dot(along)
		# Only reachable on the first ring, and on a rope doubled back hard
		# enough to leave nothing to lean on.
		if across.length_squared() < 0.0001:
			across = _find_any_perpendicular(along)
		across = across.normalized()
		var other_across := along.cross(across)

		var ring_radius := radius
		if point_index == 0 or point_index == point_count - 1:
			ring_radius = 0.0

		var ring_center := rope_points[point_index]
		var ring_start := point_index * side_count
		for side_index: int in range(side_count):
			var angle := TAU * float(side_index) / float(side_count)
			var outward := across * cos(angle) + other_across * sin(angle)
			_vertices[ring_start + side_index] = ring_center + outward * ring_radius
			_normals[ring_start + side_index] = outward


## Sizes the arrays and winds the faces. Both only change when the rope's point
## count does, which is when a line is clipped on.
func _resize(point_count: int, side_count: int) -> void:
	var vertex_count := point_count * side_count
	if _vertices.size() == vertex_count:
		return
	_vertices.resize(vertex_count)
	_normals.resize(vertex_count)
	_indices.resize((point_count - 1) * side_count * 6)

	var index := 0
	for ring_index: int in range(point_count - 1):
		for side_index: int in range(side_count):
			var next_side := (side_index + 1) % side_count
			var near_first := ring_index * side_count + side_index
			var near_second := ring_index * side_count + next_side
			var far_first := near_first + side_count
			var far_second := near_second + side_count
			_indices[index] = near_first
			_indices[index + 1] = far_first
			_indices[index + 2] = far_second
			_indices[index + 3] = near_first
			_indices[index + 4] = far_second
			_indices[index + 5] = near_second
			index += 6


## Which way the rope runs at a point, averaged from the runs either side so the
## tube bends through a link rather than kinking at it. Where the average
## cancels the rope has doubled right back, and the run out of the point is the
## honest answer.
static func _measure_rope_direction(rope_points: PackedVector3Array, point_index: int) -> Vector3:
	var ahead := Vector3.ZERO
	if point_index < rope_points.size() - 1:
		ahead = (rope_points[point_index + 1] - rope_points[point_index]).normalized()
	var behind := Vector3.ZERO
	if point_index > 0:
		behind = (rope_points[point_index] - rope_points[point_index - 1]).normalized()

	var along := ahead + behind
	if along.length_squared() < 0.0001:
		along = behind if ahead.is_zero_approx() else ahead
	if along.is_zero_approx():
		return Vector3.BACK
	return along.normalized()


## Any unit vector across the direction given; a tube has no preferred way round.
static func _find_any_perpendicular(direction: Vector3) -> Vector3:
	var off_axis := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	return direction.cross(off_axis).normalized()
