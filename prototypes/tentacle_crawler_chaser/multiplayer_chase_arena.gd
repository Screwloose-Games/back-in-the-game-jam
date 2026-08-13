class_name MultiplayerChaseArena
extends Node3D

## Six static primitive colliders form the entire multiplayer chase arena.
##
## The original chaser builds a large CSG network and a surface navmesh at run
## time. Neither is needed to prove replication, and both are hostile to a Web
## demo's first frame. This room is ready as soon as these primitive nodes exist.

const WALL_MATERIAL := preload("res://prototypes/tentacle_crawler/materials/corridor_wall.tres")
const FLOOR_MATERIAL := preload("res://prototypes/tentacle_crawler/materials/corridor_floor.tres")


func _ready() -> void:
	_build_shell()
	_build_extraction_marker()


func _build_shell() -> void:
	var half_width := MultiplayerChaseKnobs.ARENA_WIDTH * 0.5
	var half_length := MultiplayerChaseKnobs.ARENA_LENGTH * 0.5
	var thickness := MultiplayerChaseKnobs.WALL_THICKNESS
	var cross_size := MultiplayerChaseKnobs.ARENA_WIDTH + thickness * 2.0

	_add_surface(
		"Floor",
		Vector3(cross_size, thickness, MultiplayerChaseKnobs.ARENA_LENGTH),
		Vector3(0.0, -half_width - thickness * 0.5, 0.0),
		FLOOR_MATERIAL,
	)
	_add_surface(
		"Ceiling",
		Vector3(cross_size, thickness, MultiplayerChaseKnobs.ARENA_LENGTH),
		Vector3(0.0, half_width + thickness * 0.5, 0.0),
		WALL_MATERIAL,
	)
	_add_surface(
		"LeftWall",
		Vector3(thickness, MultiplayerChaseKnobs.ARENA_WIDTH, MultiplayerChaseKnobs.ARENA_LENGTH),
		Vector3(-half_width - thickness * 0.5, 0.0, 0.0),
		WALL_MATERIAL,
	)
	_add_surface(
		"RightWall",
		Vector3(thickness, MultiplayerChaseKnobs.ARENA_WIDTH, MultiplayerChaseKnobs.ARENA_LENGTH),
		Vector3(half_width + thickness * 0.5, 0.0, 0.0),
		WALL_MATERIAL,
	)
	_add_surface(
		"ExtractionEnd",
		Vector3(cross_size, cross_size, thickness),
		Vector3(0.0, 0.0, -half_length - thickness * 0.5),
		WALL_MATERIAL,
	)
	_add_surface(
		"CrawlerEnd",
		Vector3(cross_size, cross_size, thickness),
		Vector3(0.0, 0.0, half_length + thickness * 0.5),
		WALL_MATERIAL,
	)


func _add_surface(
	surface_name: String,
	size: Vector3,
	position: Vector3,
	material: Material,
) -> void:
	var body := StaticBody3D.new()
	body.name = surface_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_extraction_marker() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.9, 0.75, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.75, 0.58)
	material.emission_energy_multiplier = 2.0

	var mesh := BoxMesh.new()
	mesh.size = Vector3(MultiplayerChaseKnobs.ARENA_WIDTH - 1.0, 0.08, 0.6)
	var marker := MeshInstance3D.new()
	marker.name = "ExtractionMarker"
	marker.position = Vector3(
		0.0,
		-MultiplayerChaseKnobs.ARENA_WIDTH * 0.5 + 0.08,
		MultiplayerChaseKnobs.EXTRACTION_Z,
	)
	marker.mesh = mesh
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
