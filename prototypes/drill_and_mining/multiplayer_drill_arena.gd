class_name MultiplayerDrillArena
extends Node3D

## Cheap static copy of the drill chamber for the Web multiplayer proof.
##
## The original prototype intentionally uses runtime CSG while iterating on the
## room. Multiplayer needs two browser instances and should spend its frame time
## on remeshing ore, so this version builds the same shell from primitive meshes
## and primitive collision shapes.

const HULL_MATERIAL := preload("res://prototypes/drill_and_mining/materials/hull_material.tres")


func _ready() -> void:
	_build_shell()
	_build_pillars()


func _build_shell() -> void:
	var size := DrillKnobs.CHAMBER_SIZE
	var thickness := DrillKnobs.WALL_THICKNESS
	_add_box(
		"Floor",
		Vector3(0.0, -size.y * 0.5 - thickness * 0.5, 0.0),
		Vector3(size.x + thickness * 2.0, thickness, size.z + thickness * 2.0),
	)
	_add_box(
		"Ceiling",
		Vector3(0.0, size.y * 0.5 + thickness * 0.5, 0.0),
		Vector3(size.x + thickness * 2.0, thickness, size.z + thickness * 2.0),
	)
	_add_box(
		"LeftWall",
		Vector3(-size.x * 0.5 - thickness * 0.5, 0.0, 0.0),
		Vector3(thickness, size.y, size.z),
	)
	_add_box(
		"RightWall",
		Vector3(size.x * 0.5 + thickness * 0.5, 0.0, 0.0),
		Vector3(thickness, size.y, size.z),
	)
	_add_box(
		"FrontWall",
		Vector3(0.0, 0.0, size.z * 0.5 + thickness * 0.5),
		Vector3(size.x, size.y, thickness),
	)
	_add_box(
		"BackWall",
		Vector3(0.0, 0.0, -size.z * 0.5 - thickness * 0.5),
		Vector3(size.x, size.y, thickness),
	)


func _build_pillars() -> void:
	for index in DrillKnobs.PILLARS.size():
		var pillar: Dictionary = DrillKnobs.PILLARS[index]
		var centre: Vector3 = pillar["center"]
		var size: Vector3 = pillar["size"]
		_add_box("Pillar%d" % index, centre, size)


func _add_box(box_name: String, centre: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = HULL_MATERIAL

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "%sMesh" % box_name
	mesh_instance.mesh = mesh

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % box_name
	collision.shape = shape

	var body := StaticBody3D.new()
	body.name = box_name
	body.position = centre
	body.collision_layer = DrillKnobs.HULL_LAYER
	body.collision_mask = 0
	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)
