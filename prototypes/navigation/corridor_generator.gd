extends Node3D

## Carves the corridor network out of solid hull with CSG.
##
## Every span contributes two brushes: a solid box the size of the hull, and a
## smaller box that hollows the tunnel out of it. All the hull brushes are
## unioned first, then all the tunnel brushes subtract from the result.
##
## The tunnel brush is always strictly narrower and shorter than its own hull
## brush, so a span can never carve through to the outside no matter what angle
## it sits at. That is what makes arbitrary angles and multi-way junctions safe
## here - there are no seams to line up, only overlapping volumes.

const HULL_MATERIAL := preload("res://prototypes/navigation/materials/hull_material.tres")
const MARKER_MATERIAL := preload("res://prototypes/navigation/materials/marker_material.tres")

## How far a hull brush runs past each end of its span. Generous, so hulls of
## adjoining spans always overlap through a junction.
var _hull_overrun: float
## How far a tunnel brush runs past each end. Must stay below _hull_overrun or
## the tunnel would breach its own hull; it needs to be positive so adjoining
## tunnels actually meet and the junction is passable.
var _tunnel_overrun: float

var _hull_brushes: Array[CSGBox3D] = []
var _tunnel_brushes: Array[CSGBox3D] = []

## Spikes are plain geometry rather than CSG brushes. They only ever stick out
## into open tunnel, so there is no boolean to compute, and unioning a hundred
## of them into the combiner would cost far more than it bought.
var _spike_body: StaticBody3D
var _spike_mesh := BoxMesh.new()
var _spike_randomizer := RandomNumberGenerator.new()
var _spike_density_noise := FastNoiseLite.new()
var _spike_count := 0


func _ready() -> void:
	_hull_overrun = PrototypeKnobs.CORRIDOR_WIDTH * 0.5 + PrototypeKnobs.WALL_THICKNESS
	_tunnel_overrun = PrototypeKnobs.CORRIDOR_WIDTH * 0.5
	_prepare_spikes()

	for path: Array in PrototypeKnobs.CORRIDOR_PATHS:
		_collect_path_brushes(path)

	_assemble_combiner()
	_build_end_marker()


func _prepare_spikes() -> void:
	_spike_mesh.size = Vector3.ONE
	_spike_mesh.material = HULL_MATERIAL

	_spike_randomizer.seed = PrototypeKnobs.SPIKE_RANDOM_SEED
	_spike_density_noise.seed = PrototypeKnobs.SPIKE_RANDOM_SEED
	_spike_density_noise.frequency = PrototypeKnobs.SPIKE_CLUSTER_FREQUENCY

	_spike_body = StaticBody3D.new()
	_spike_body.name = "SpikeBody"
	_spike_body.collision_layer = 1
	_spike_body.collision_mask = 0
	add_child(_spike_body)


## Returns how many spikes were placed. Read by the corridor probe.
func get_spike_count() -> int:
	return _spike_count


func _collect_path_brushes(waypoints: Array) -> void:
	if waypoints.size() < 2:
		push_warning("Corridor path needs at least two waypoints; skipped.")
		return

	for index in waypoints.size() - 1:
		var span_start: Vector3 = waypoints[index]
		var span_end: Vector3 = waypoints[index + 1]
		if span_start.is_equal_approx(span_end):
			push_warning("Corridor span has zero length at %s; skipped." % span_start)
			continue
		_collect_span_brushes(span_start, span_end)


func _collect_span_brushes(span_start: Vector3, span_end: Vector3) -> void:
	var span_length := span_start.distance_to(span_end)
	var span_transform := _make_span_transform(span_start, span_end)

	var hull_side := PrototypeKnobs.CORRIDOR_WIDTH + PrototypeKnobs.WALL_THICKNESS * 2.0
	_hull_brushes.append(
		_make_brush(
			span_transform,
			Vector3(hull_side, hull_side, span_length + _hull_overrun * 2.0),
			CSGShape3D.OPERATION_UNION
		)
	)
	_tunnel_brushes.append(
		_make_brush(
			span_transform,
			Vector3(
				PrototypeKnobs.CORRIDOR_WIDTH,
				PrototypeKnobs.CORRIDOR_WIDTH,
				span_length + _tunnel_overrun * 2.0
			),
			CSGShape3D.OPERATION_SUBTRACTION
		)
	)

	if PrototypeKnobs.SPAWN_SPIKES:
		_scatter_span_spikes(span_start, span_end, span_length, span_transform)


## Walks the span placing spikes against its four walls. Density comes from
## noise sampled in world space, so clusters read as continuous thickets across
## a stretch of corridor rather than restarting at every waypoint.
func _scatter_span_spikes(
	span_start: Vector3, span_end: Vector3, span_length: float, span_transform: Transform3D
) -> void:
	var span_direction := (span_end - span_start).normalized()
	var wall_axes: Array[Vector3] = [
		span_transform.basis.x, -span_transform.basis.x,
		span_transform.basis.y, -span_transform.basis.y,
	]
	# Hold spikes back from the ends so they do not grow across a junction
	# opening, where they would block a turn rather than complicate a corridor.
	var margin := PrototypeKnobs.CORRIDOR_WIDTH * 0.5
	var distance := margin

	while distance < span_length - margin:
		var axis_position := span_start + span_direction * distance
		var density := (_spike_density_noise.get_noise_3dv(axis_position) + 1.0) * 0.5
		var spawn_chance := lerpf(
			PrototypeKnobs.SPIKE_SPARSE_CHANCE, PrototypeKnobs.SPIKE_DENSE_CHANCE, density
		)
		if _spike_randomizer.randf() < spawn_chance:
			_build_spike(axis_position, wall_axes[_spike_randomizer.randi() % 4])
		distance += PrototypeKnobs.SPIKE_SAMPLE_STEP


func _build_spike(axis_position: Vector3, wall_outward: Vector3) -> void:
	var length := _spike_randomizer.randf_range(
		PrototypeKnobs.SPIKE_MIN_LENGTH, PrototypeKnobs.SPIKE_MAX_LENGTH
	)
	var thickness := _spike_randomizer.randf_range(
		PrototypeKnobs.SPIKE_MIN_THICKNESS, PrototypeKnobs.SPIKE_MAX_THICKNESS
	)

	# Slide the base around on the wall face it is mounted to.
	var along_wall := wall_outward.cross(Vector3.UP)
	if along_wall.length_squared() < 0.01:
		along_wall = wall_outward.cross(Vector3.BACK)
	along_wall = along_wall.normalized()
	var slide := PrototypeKnobs.CORRIDOR_WIDTH * 0.5 - thickness
	var base_position := (
		axis_position
		+ wall_outward * PrototypeKnobs.CORRIDOR_WIDTH * 0.5
		+ along_wall * _spike_randomizer.randf_range(-slide, slide)
	)

	# Lean the spike off the wall normal by a random amount, in a random
	# direction around it, so no two read as parallel.
	var tilt_axis := along_wall.rotated(wall_outward, _spike_randomizer.randf_range(0.0, TAU))
	var spike_direction := (-wall_outward).rotated(
		tilt_axis,
		deg_to_rad(_spike_randomizer.randf_range(0.0, PrototypeKnobs.SPIKE_MAX_TILT_DEGREES))
	)

	var spike_basis := Basis.looking_at(spike_direction, _pick_reference_up(spike_direction))
	var spike_center := (
		base_position + spike_direction * (length * 0.5 - PrototypeKnobs.SPIKE_EMBED_DEPTH)
	)

	var spike_mesh_instance := MeshInstance3D.new()
	spike_mesh_instance.mesh = _spike_mesh
	spike_mesh_instance.transform = Transform3D(
		spike_basis.scaled(Vector3(thickness, thickness, length)), spike_center
	)
	add_child(spike_mesh_instance)

	# The collider carries its size on the shape rather than as node scale,
	# which physics does not handle reliably.
	var spike_shape := BoxShape3D.new()
	spike_shape.size = Vector3(thickness, thickness, length)
	var spike_collider := CollisionShape3D.new()
	spike_collider.shape = spike_shape
	spike_collider.transform = Transform3D(spike_basis, spike_center)
	_spike_body.add_child(spike_collider)

	_spike_count += 1


## Order matters: hulls union into one solid, then tunnels subtract from it.
func _assemble_combiner() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = true
	combiner.collision_layer = 1
	combiner.collision_mask = 0
	combiner.material_override = HULL_MATERIAL
	add_child(combiner)

	for brush in _hull_brushes:
		combiner.add_child(brush)
	for brush in _tunnel_brushes:
		combiner.add_child(brush)


func _make_brush(
	brush_transform: Transform3D, brush_size: Vector3, operation: CSGShape3D.Operation
) -> CSGBox3D:
	var brush := CSGBox3D.new()
	brush.size = brush_size
	brush.operation = operation
	brush.transform = brush_transform
	return brush


## Builds a basis whose local Z runs along the span, centred on its midpoint.
func _make_span_transform(span_start: Vector3, span_end: Vector3) -> Transform3D:
	var span_direction := (span_end - span_start).normalized()
	return Transform3D(
		Basis.looking_at(span_direction, _pick_reference_up(span_direction)),
		(span_start + span_end) * 0.5
	)


## Basis.looking_at fails when its up vector is parallel to the direction, so
## vertical spans and straight-down spikes need a different reference.
func _pick_reference_up(direction: Vector3) -> Vector3:
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


## Caps the last waypoint of the last path with an emissive panel, so the run
## has one unambiguous destination among all the dead ends.
func _build_end_marker() -> void:
	var final_path: Array = PrototypeKnobs.CORRIDOR_PATHS.back()
	var marker_position: Vector3 = final_path.back()
	var approach_direction: Vector3 = (marker_position - final_path[-2]).normalized()

	var marker := MeshInstance3D.new()
	marker.name = "EndMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(
		PrototypeKnobs.CORRIDOR_WIDTH * 0.7, PrototypeKnobs.CORRIDOR_WIDTH * 0.7, 0.08
	)
	marker.mesh = marker_mesh
	marker.material_override = MARKER_MATERIAL

	marker.transform = Transform3D(
		Basis.looking_at(approach_direction, _pick_reference_up(approach_direction)),
		marker_position + approach_direction * (_tunnel_overrun - 0.1)
	)
	add_child(marker)
