class_name MultiplayerTestChamber
extends Node3D

## Static-primitive version of the power prototype's chamber.
##
## The single-player prototype carves this room with CSG. That is useful while
## designing geometry, but CSG boolean evaluation and its generated concave
## collision are expensive deferred work in a Web export. This networking demo
## builds the same simple room from final box/cylinder meshes and matching
## primitive collision shapes instead.

const HULL_MATERIAL := preload(
	"res://prototypes/power_and_lighting/imported/materials/hull_material.tres"
)
const HULL_LAYER := 1


func _ready() -> void:
	_build_room_shell()
	_build_pillars()
	_build_divider()


func _build_room_shell() -> void:
	var room_size := MovementKnobs.CHAMBER_SIZE
	var wall_thickness := MovementKnobs.WALL_THICKNESS
	var padded_width := room_size.x + wall_thickness * 2.0
	var padded_height := room_size.y + wall_thickness * 2.0
	var padded_depth := room_size.z + wall_thickness * 2.0

	_add_box_piece(
		"Floor",
		Vector3(0.0, -(room_size.y + wall_thickness) * 0.5, 0.0),
		Vector3(padded_width, wall_thickness, padded_depth),
	)
	_add_box_piece(
		"Ceiling",
		Vector3(0.0, (room_size.y + wall_thickness) * 0.5, 0.0),
		Vector3(padded_width, wall_thickness, padded_depth),
	)
	_add_box_piece(
		"LeftWall",
		Vector3(-(room_size.x + wall_thickness) * 0.5, 0.0, 0.0),
		Vector3(wall_thickness, padded_height, room_size.z),
	)
	_add_box_piece(
		"RightWall",
		Vector3((room_size.x + wall_thickness) * 0.5, 0.0, 0.0),
		Vector3(wall_thickness, padded_height, room_size.z),
	)
	_add_box_piece(
		"FrontWall",
		Vector3(0.0, 0.0, -(room_size.z + wall_thickness) * 0.5),
		Vector3(room_size.x, padded_height, wall_thickness),
	)
	_add_box_piece(
		"BackWall",
		Vector3(0.0, 0.0, (room_size.z + wall_thickness) * 0.5),
		Vector3(room_size.x, padded_height, wall_thickness),
	)


func _build_pillars() -> void:
	for pillar: Dictionary in MovementKnobs.PILLARS:
		var center: Vector3 = pillar["center"]
		var size: Vector3 = pillar["size"]
		_add_box_piece("SquarePillar", center, size)

	for pillar: Dictionary in MovementKnobs.ROUND_PILLARS:
		var center: Vector3 = pillar["center"]
		var radius: float = pillar["radius"]
		_add_cylinder_piece(
			"RoundPillar",
			center,
			radius,
			MovementKnobs.CHAMBER_SIZE.y,
		)


func _build_divider() -> void:
	var room_size := MovementKnobs.CHAMBER_SIZE
	var gap_size := MovementKnobs.DIVIDER_GAP
	var depth := MovementKnobs.DIVIDER_DEPTH
	var thickness := MovementKnobs.DIVIDER_THICKNESS
	var side_width := (room_size.x - gap_size.x) * 0.5
	var cap_height := (room_size.y - gap_size.y) * 0.5

	_add_box_piece(
		"DividerLeft",
		Vector3(-(gap_size.x + side_width) * 0.5, 0.0, depth),
		Vector3(side_width, room_size.y, thickness),
	)
	_add_box_piece(
		"DividerRight",
		Vector3((gap_size.x + side_width) * 0.5, 0.0, depth),
		Vector3(side_width, room_size.y, thickness),
	)
	_add_box_piece(
		"DividerTop",
		Vector3(0.0, (gap_size.y + cap_height) * 0.5, depth),
		Vector3(gap_size.x, cap_height, thickness),
	)
	_add_box_piece(
		"DividerBottom",
		Vector3(0.0, -(gap_size.y + cap_height) * 0.5, depth),
		Vector3(gap_size.x, cap_height, thickness),
	)


func _add_box_piece(piece_name: String, center: Vector3, size: Vector3) -> void:
	var body := _make_static_body(piece_name, center)

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = HULL_MATERIAL
	body.add_child(mesh_instance)

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = box_shape
	body.add_child(collision)


func _add_cylinder_piece(
	piece_name: String,
	center: Vector3,
	radius: float,
	height: float,
) -> void:
	var body := _make_static_body(piece_name, center)

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = height
	cylinder_mesh.radial_segments = MovementKnobs.ROUND_PILLAR_SIDES
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = cylinder_mesh
	mesh_instance.material_override = HULL_MATERIAL
	body.add_child(mesh_instance)

	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = cylinder_shape
	body.add_child(collision)


func _make_static_body(piece_name: String, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.position = center
	body.collision_layer = HULL_LAYER
	body.collision_mask = 0
	add_child(body, true)
	return body
