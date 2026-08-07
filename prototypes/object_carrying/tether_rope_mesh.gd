class_name TetherRopeMesh
extends RefCounted

## The drawn tether: a tube of triangles laid over the points tether_rope.gd
## simulates the line at.
##
## Nothing here is physical. The rope's shape is decided entirely by the
## simulation and by what carrier_player.gd hauls on; this only reads the points
## it was left with and gives them a thickness the chain does not have.
##
## The mesh is rebuilt in place every frame, so whoever draws it hands
## read_mesh() to a MeshInstance3D once and never looks at it again.

var _mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
## Which vertices make which faces. The rope's point count is fixed from the
## moment it is laid out, so this is worked out once rather than every frame.
var _indices := PackedInt32Array()


## The mesh to hand a MeshInstance3D, in world space. Rebuilt in place, so it
## only has to be read once.
func read_mesh() -> ArrayMesh:
	return _mesh


## Redraws the tube over wherever the rope's points ended up this frame.
func rebuild(rope_points: PackedVector3Array) -> void:
	_build_tube(rope_points)

	var surface_arrays := []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = _vertices
	surface_arrays[Mesh.ARRAY_NORMAL] = _normals
	surface_arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)


## Lays a ring of vertices across the rope at each of its points, which is what
## gives the drawn rope a thickness the simulated chain of points does not have.
##
## Each ring needs a pair of axes across the rope, and nothing picks which way
## round they go - a tube is the same shape whichever you choose. What matters
## is that neighbouring rings agree, or the tube creases along its length, so
## each ring leans the previous ring's axes onto its own cross-section rather
## than choosing afresh.
##
## Both end rings are drawn in to nothing. That closes the tube off where it
## meets its anchors without any geometry beyond what is already here, and the
## taper is hidden in the module and the harness it runs into.
func _build_tube(rope_points: PackedVector3Array) -> void:
	var point_count := rope_points.size()
	var sides := maxi(3, CarryKnobs.TETHER_ROPE_DRAW_SIDES)
	_resize(point_count, sides)

	var across := Vector3.ZERO
	for point_index: int in range(point_count):
		var along := _measure_rope_direction(rope_points, point_index)
		across -= along * across.dot(along)
		# Only reachable on the first ring, which has nothing to lean, and on a
		# rope that has doubled back hard enough to leave nothing to lean on.
		if across.length_squared() < 0.0001:
			across = _find_any_perpendicular(along)
		across = across.normalized()
		var other_across := along.cross(across)

		var radius := CarryKnobs.TETHER_ROPE_DRAW_RADIUS
		if point_index == 0 or point_index == point_count - 1:
			radius = 0.0

		var ring_center := rope_points[point_index]
		var ring_start := point_index * sides
		for side_index: int in range(sides):
			var angle := TAU * float(side_index) / float(sides)
			var outward := across * cos(angle) + other_across * sin(angle)
			_vertices[ring_start + side_index] = ring_center + outward * radius
			_normals[ring_start + side_index] = outward


## Sizes the tube's arrays to the rope and works out its faces. Both only ever
## change when the rope's point count does, which is when a line is clipped on.
func _resize(point_count: int, sides: int) -> void:
	var vertex_count := point_count * sides
	if _vertices.size() == vertex_count:
		return
	_vertices.resize(vertex_count)
	_normals.resize(vertex_count)
	_indices.resize((point_count - 1) * sides * 6)

	# Each pair of neighbouring rings is joined by a quad per side, wound the way
	# round that leaves it facing out of the rope.
	var index := 0
	for ring_index: int in range(point_count - 1):
		for side_index: int in range(sides):
			var next_side := (side_index + 1) % sides
			var near_first := ring_index * sides + side_index
			var near_second := ring_index * sides + next_side
			var far_first := near_first + sides
			var far_second := near_second + sides
			_indices[index] = near_first
			_indices[index + 1] = far_first
			_indices[index + 2] = far_second
			_indices[index + 3] = near_first
			_indices[index + 4] = far_second
			_indices[index + 5] = near_second
			index += 6


## Which way the rope runs at one of its points, averaged from the runs either
## side of it so the tube bends through a link rather than kinking at it.
##
## Averaged rather than simply taken across the point, because the two
## neighbours of a point where the rope has folded back on itself are in nearly
## the same place, and the line between them is noise. A ring built on a tangent
## that has come out pointing back down the rope is wound the opposite way to
## its neighbours, and the tube turns inside out between them.
##
## Where the average cancels the rope really has doubled right back, and the run
## out of the point is the honest answer. A tube through a fold that sharp
## pinches through itself whatever tangent it is given.
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


## Any unit vector across the direction given. Which one is immaterial: it only
## ever seeds the first ring, and a tube has no preferred way round.
static func _find_any_perpendicular(direction: Vector3) -> Vector3:
	var off_axis := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	return direction.cross(off_axis).normalized()
