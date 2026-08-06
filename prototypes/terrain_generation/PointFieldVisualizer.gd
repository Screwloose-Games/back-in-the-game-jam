@tool
extends Node3D
class_name PointFieldVisualizer


@export_category("Point Field Settings")


@export var field_size: Vector3 = Vector3(10,10,10):
	set(value):
		field_size = value
		call_deferred("_regenerate")


@export_range(2,200,1)
var number_of_points: int = 10:
	set(value):
		number_of_points = value
		call_deferred("_regenerate")


@export_range(0.01,2.0,0.01)
var point_size: float = 0.1:
	set(value):
		point_size = value
		call_deferred("_update_point_size")


var point_mesh: MultiMeshInstance3D


func _ready():
	_create_visualizer()
	_regenerate()


func _enter_tree():
	if Engine.is_editor_hint():
		call_deferred("_create_visualizer")


func _create_visualizer():
	if point_mesh:
		return


	point_mesh = MultiMeshInstance3D.new()
	point_mesh.name = "PointField_Display"
	add_child(point_mesh)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * point_size


	var material := StandardMaterial3D.new()
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.albedo_color = Color(
		0.0,
		0.3,
		1.0,
		0.8
	)
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	material.billboard_mode = (
		BaseMaterial3D.BILLBOARD_ENABLED
	)
	quad.material = material


	var mm := MultiMesh.new()
	mm.mesh = quad
	mm.transform_format = (
		MultiMesh.TRANSFORM_3D
	)
	point_mesh.multimesh = mm


func _update_point_size():
	if point_mesh == null:
		return
	if point_mesh.multimesh == null:
		return


	var quad := point_mesh.multimesh.mesh as QuadMesh
	if quad == null:
		return
	quad.size = Vector2.ONE * point_size


func _regenerate():
	if not Engine.is_editor_hint():
		return
	if point_mesh == null:
		return


	call_deferred(
		"_generate_points"
	)


func _generate_points():
	var mm := point_mesh.multimesh
	var count := (
		number_of_points *
		number_of_points *
		number_of_points
	)
	mm.instance_count = count
	var half := field_size * 0.5
	var i := 0


# this needs to be refactored
	for z in range(number_of_points):
		var zpos := lerpf(
			-half.z,
			half.z,
			float(z) /
			float(number_of_points-1)
		)
		for y in range(number_of_points):
			var ypos := lerpf(
				-half.y,
				half.y,
				float(y) /
				float(number_of_points-1)
			)
			for x in range(number_of_points):
				var xpos := lerpf(
					-half.x,
					half.x,
					float(x) /
					float(number_of_points-1)
				)
				var t := Transform3D()
				t.origin = Vector3(
					xpos,
					ypos,
					zpos
				)
				t.basis = Basis.IDENTITY.scaled(
					Vector3.ONE * point_size
				)
				mm.set_instance_transform(
					i,
					t
				)
				i += 1
	point_mesh.multimesh = mm
