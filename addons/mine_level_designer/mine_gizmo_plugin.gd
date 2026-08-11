@tool
extends EditorNode3DGizmoPlugin

## Makes spaces and tunnels clickable in the 3D viewport, and gives each one a
## handle for the number you most want to drag.
##
## WITHOUT THIS THEY CANNOT BE SELECTED AT ALL. A MineSpace is a bare Node3D, and
## the meshes that make the level visible belong to the level's unowned visuals
## container rather than to the nodes themselves - so there is nothing under the
## cursor that the editor is willing to select, and the Scene dock is the only way
## in. A gizmo's collision geometry is what puts the node back under the mouse.
##
## The collision shapes match what is drawn: the sphere you see is the sphere you
## click, and the tube you see is the tube you click. Overlapping volumes are
## cycled through by clicking again in the same spot, which is Godot's normal
## behaviour for stacked objects.

const SPACE_COLOR := Color(0.55, 0.85, 1.0)
const TUNNEL_COLOR := Color(1.0, 0.72, 0.35)

## Sides on the collision tube. Coarse on purpose - it is never drawn, it only has
## to be about the right shape for a ray to hit.
const COLLISION_TUBE_SIDES := 6

const WIREFRAME_STEPS := 24

## How far the width handle sits out from the tunnel's centreline, as a multiple
## of half-width. Slightly proud, so it is not buried inside the drawn tube.
const WIDTH_HANDLE_REACH := 1.15

var _undo_redo: EditorUndoRedoManager = null


func _init() -> void:
	create_material("space", SPACE_COLOR)
	create_material("tunnel", TUNNEL_COLOR)
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "Mine Level"


func _has_gizmo(node: Node3D) -> bool:
	return node is MineSpace or node is MineTunnel


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var space := gizmo.get_node_3d() as MineSpace
	if space != null:
		_redraw_space(gizmo, space)
		return
	var tunnel := gizmo.get_node_3d() as MineTunnel
	if tunnel != null:
		_redraw_tunnel(gizmo, tunnel)


func bind_undo_redo(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


func _get_handle_name(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> String:
	return "Radius" if gizmo.get_node_3d() is MineSpace else "Width"


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	var space := gizmo.get_node_3d() as MineSpace
	if space != null:
		return space.radius
	return (gizmo.get_node_3d() as MineTunnel).width


## Drags the handle by measuring where the mouse ray passes closest to the axis
## the handle runs along, which is what keeps the number tracking the cursor from
## any camera angle.
func _set_handle(
	gizmo: EditorNode3DGizmo,
	_handle_id: int,
	_secondary: bool,
	camera: Camera3D,
	screen_point: Vector2
) -> void:
	var node := gizmo.get_node_3d()
	var origin := _handle_origin(node)
	var axis := node.global_transform.basis.x.normalized()
	var reach := _distance_along_axis(origin, axis, camera, screen_point)

	var space := node as MineSpace
	if space != null:
		space.radius = maxf(reach, 0.0)
		return
	var tunnel := node as MineTunnel
	if tunnel != null:
		tunnel.width = maxf(reach / WIDTH_HANDLE_REACH, 0.1) * 2.0


func _commit_handle(
	gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool
) -> void:
	var node := gizmo.get_node_3d()
	var property := &"radius" if node is MineSpace else &"width"
	if cancel:
		node.set(property, restore)
		return
	if _undo_redo == null:
		return
	var committed: Variant = node.get(property)
	_undo_redo.create_action("Set %s on %s" % [property, node.name])
	_undo_redo.add_do_property(node, property, committed)
	_undo_redo.add_undo_property(node, property, restore)
	_undo_redo.commit_action()


func _redraw_space(gizmo: EditorNode3DGizmo, space: MineSpace) -> void:
	var radius := maxf(space.radius, MineLevel.MARKER_RADIUS)
	gizmo.add_lines(_sphere_wireframe(radius), get_material("space", gizmo), false)

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	gizmo.add_collision_triangles(sphere.generate_triangle_mesh())
	gizmo.add_handles([Vector3(radius, 0.0, 0.0)], get_material("handles", gizmo), [0])


func _redraw_tunnel(gizmo: EditorNode3DGizmo, tunnel: MineTunnel) -> void:
	var points := _local_polyline(tunnel)
	if points.size() < 2:
		return

	var lines := PackedVector3Array()
	for index: int in points.size() - 1:
		lines.append(points[index])
		lines.append(points[index + 1])
	gizmo.add_lines(lines, get_material("tunnel", gizmo), false)

	# Segments as well as the tube, so a tunnel drawn edge-on is still catchable
	# on its centreline when the tube is only a couple of pixels wide.
	gizmo.add_collision_segments(lines)
	var tube := _tube_triangle_mesh(points, tunnel.width * 0.5)
	if tube != null:
		gizmo.add_collision_triangles(tube)

	var midpoint := LevelGraph.point_on_polyline(points, _polyline_length(points) * 0.5)
	var reach := maxf(tunnel.width * 0.5 * WIDTH_HANDLE_REACH, 0.5)
	gizmo.add_handles([midpoint + Vector3(reach, 0.0, 0.0)], get_material("handles", gizmo), [0])


## The tunnel's shape lives in global space, because its ends belong to other
## nodes. Gizmos draw in the node's own space.
func _local_polyline(tunnel: MineTunnel) -> PackedVector3Array:
	var local := PackedVector3Array()
	for point: Vector3 in tunnel.build_polyline():
		local.append(tunnel.to_local(point))
	return local


## Where the handle's measuring axis starts. A space measures from its centre; a
## tunnel from the midpoint of its run, which is where the handle is drawn.
func _handle_origin(node: Node3D) -> Vector3:
	var tunnel := node as MineTunnel
	if tunnel == null:
		return node.global_position
	var points := _local_polyline(tunnel)
	if points.size() < 2:
		return node.global_position
	return node.to_global(LevelGraph.point_on_polyline(points, _polyline_length(points) * 0.5))


func _distance_along_axis(
	origin: Vector3, axis: Vector3, camera: Camera3D, screen_point: Vector2
) -> float:
	var ray_from := camera.project_ray_origin(screen_point)
	var ray_to := ray_from + camera.project_ray_normal(screen_point) * camera.far
	var closest := Geometry3D.get_closest_points_between_segments(
		origin, origin + axis * camera.far, ray_from, ray_to
	)
	return origin.distance_to(closest[0])


## Three great circles. Enough to read a sphere's size without filling the view
## with wireframe on a level that has thirty of them.
func _sphere_wireframe(radius: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for plane: int in 3:
		for step: int in WIREFRAME_STEPS:
			lines.append(_circle_point(plane, TAU * float(step) / WIREFRAME_STEPS, radius))
			lines.append(_circle_point(plane, TAU * float(step + 1) / WIREFRAME_STEPS, radius))
	return lines


func _circle_point(plane: int, angle: float, radius: float) -> Vector3:
	var across := cos(angle) * radius
	var up := sin(angle) * radius
	if plane == 0:
		return Vector3(across, up, 0.0)
	if plane == 1:
		return Vector3(across, 0.0, up)
	return Vector3(0.0, across, up)


## A tube along the polyline, purely as something for a click ray to hit. Built
## from the same alignment the level uses to draw its visible tubes, so the two
## agree about which way a vertical shaft points.
func _tube_triangle_mesh(points: PackedVector3Array, radius: float) -> TriangleMesh:
	var faces := PackedVector3Array()
	for index: int in points.size() - 1:
		var start := points[index]
		var finish := points[index + 1]
		var direction := finish - start
		var span := direction.length()
		if span <= 0.0:
			continue
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = maxf(radius, 0.25)
		cylinder.bottom_radius = maxf(radius, 0.25)
		cylinder.height = span
		cylinder.radial_segments = COLLISION_TUBE_SIDES
		cylinder.rings = 0
		var placement := Transform3D(
			MineLevel.basis_aligning_up_with(direction), (start + finish) * 0.5
		)
		for corner: Vector3 in cylinder.get_faces():
			faces.append(placement * corner)

	if faces.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh.generate_triangle_mesh()


func _polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in maxi(points.size() - 1, 0):
		total += points[index].distance_to(points[index + 1])
	return total
