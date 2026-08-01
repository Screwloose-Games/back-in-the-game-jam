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
var _obstacle_brushes: Array[CSGBox3D] = []


func _ready() -> void:
	_hull_overrun = PrototypeKnobs.CORRIDOR_WIDTH * 0.5 + PrototypeKnobs.WALL_THICKNESS
	_tunnel_overrun = PrototypeKnobs.CORRIDOR_WIDTH * 0.5

	for path: Array in PrototypeKnobs.CORRIDOR_PATHS:
		_collect_path_brushes(path)

	_assemble_combiner()
	_build_end_marker()


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

	if PrototypeKnobs.SPAWN_OBSTACLES:
		_collect_span_obstacles(span_start, span_end, span_length, span_transform)


## Protruding cubes give the eye something to read parallax against, and punish
## drifting through a junction without slowing down.
func _collect_span_obstacles(
	span_start: Vector3, span_end: Vector3, span_length: float, span_transform: Transform3D
) -> void:
	var spacing := PrototypeKnobs.METRES_BETWEEN_OBSTACLES
	# Keep obstacles clear of the junctions at either end, where they would sit
	# in the middle of an opening rather than against a wall.
	var distance := spacing
	var span_direction := (span_end - span_start).normalized()
	var lateral := span_transform.basis.x
	var wall_offset := (
		PrototypeKnobs.CORRIDOR_WIDTH * 0.5 - PrototypeKnobs.OBSTACLE_SIZE * 0.5
	)
	var alternate := false

	while distance < span_length - spacing * 0.5:
		var mount_position := (
			span_start
			+ span_direction * distance
			+ lateral * (wall_offset if alternate else -wall_offset)
		)
		_obstacle_brushes.append(
			_make_brush(
				Transform3D(span_transform.basis, mount_position),
				Vector3.ONE * PrototypeKnobs.OBSTACLE_SIZE,
				CSGShape3D.OPERATION_UNION
			)
		)
		distance += spacing
		alternate = not alternate


## Order matters: hulls union into one solid, tunnels then subtract from it,
## and obstacles union back in afterwards so they are not carved away.
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
	for brush in _obstacle_brushes:
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
	var reference_up := Vector3.UP
	if absf(span_direction.dot(reference_up)) > 0.99:
		reference_up = Vector3.BACK
	return Transform3D(
		Basis.looking_at(span_direction, reference_up), (span_start + span_end) * 0.5
	)


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

	var reference_up := Vector3.UP
	if absf(approach_direction.dot(reference_up)) > 0.99:
		reference_up = Vector3.BACK
	marker.transform = Transform3D(
		Basis.looking_at(approach_direction, reference_up),
		marker_position + approach_direction * (_tunnel_overrun - 0.1)
	)
	add_child(marker)
