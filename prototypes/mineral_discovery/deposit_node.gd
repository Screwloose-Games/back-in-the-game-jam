class_name DepositNode
extends Node3D

## One mineral deposit: a formation of primitive chunks sharing the prototype's
## single tunable ore material, plus a collider on the mineral layer so the
## prototype's mining ray can find it.
##
## The formation is built from fixed offset patterns rather than random ones, so
## a deposit looks the same every run and Q3's "can I tell a vein from a cluster?"
## is judged against a stable shape. Tier and formation are the two things that
## vary between deposits; the MATERIAL does not - every deposit shares one, which
## is what lets one slider retune all of them (Q1) and keeps richer deposits
## distinguished by where they are and how they are shaped, not by colour.

enum Tier { COMMON, RICH, PREMIUM }
enum Formation { SEAM, VEIN, CLUSTER, POCKET, FLECKS }

## Reward per tier, in placeholder units. No economy hangs off this yet - it is
## the number the HUD adds up so "was that worth the trip?" has an answer.
const TIER_VALUE := {Tier.COMMON: 1, Tier.RICH: 3, Tier.PREMIUM: 6}

## Half-extent of the box collider that catches the mining ray, in metres. One
## box bounding the whole formation is enough; the ray only needs to know it hit
## this deposit, not which chunk.
const COLLIDER_HALF_EXTENT := Vector3(0.6, 0.6, 0.4)

@export var tier: Tier = Tier.COMMON
@export var formation: Formation = Formation.SEAM

var _material: StandardMaterial3D
var _mined := false
var _meshes: Array[MeshInstance3D] = []
var _body: StaticBody3D


## Set before the node enters the tree; _ready builds from these. The cave hands
## in the one shared material so every deposit tracks the tuning panel together.
func setup(deposit_tier: Tier, deposit_formation: Formation, material: StandardMaterial3D) -> void:
	tier = deposit_tier
	formation = deposit_formation
	_material = material


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
	_build_collider()
	_build_formation()


## Empties the deposit: the chunks vanish and the collider stops catching the
## mining ray, so a mined-out deposit reads as spent and cannot be re-mined.
func deplete() -> void:
	if _mined:
		return
	_mined = true
	for mesh: MeshInstance3D in _meshes:
		mesh.visible = false
	_body.collision_layer = 0


func is_mined() -> bool:
	return _mined


func get_value() -> int:
	return TIER_VALUE[tier]


func get_tier_name() -> String:
	return Tier.keys()[tier].capitalize()


## Where the HUD hangs this deposit's proximity marker, in world space. Lifted a
## little off the surface so the marker sits over the ore rather than in the wall.
func get_marker_position() -> Vector3:
	return global_position + Vector3.UP * 0.3


func _build_collider() -> void:
	_body = StaticBody3D.new()
	_body.name = "OreBody"
	# Layer only, no mask: the deposit is a target, it senses nothing itself.
	_body.collision_layer = MineralKnobs.MINERAL_LAYER_BIT
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = COLLIDER_HALF_EXTENT * 2.0
	shape.shape = box
	_body.add_child(shape)
	add_child(_body)


func _build_formation() -> void:
	match formation:
		Formation.SEAM:
			_build_seam()
		Formation.VEIN:
			_build_vein()
		Formation.CLUSTER:
			_build_cluster()
		Formation.POCKET:
			_build_pocket()
		Formation.FLECKS:
			_build_flecks()


## A single flat slab flush to the wall - the plainest, most legible deposit.
func _build_seam() -> void:
	_add_box(Vector3(0.9, 0.6, 0.14), Vector3.ZERO)


## A streak of chunks running along the wall, reading as a mineral vein.
func _build_vein() -> void:
	var offsets := [
		Vector3(-0.6, -0.12, 0.0),
		Vector3(-0.28, 0.06, 0.02),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.32, 0.1, 0.02),
		Vector3(0.62, -0.05, 0.0),
	]
	for offset: Vector3 in offsets:
		_add_box(Vector3(0.26, 0.16, 0.13), offset)


## A tight clump of crystalline chunks - obviously richer, obviously worth the
## detour to reach.
func _build_cluster() -> void:
	var offsets := [
		Vector3(0.0, 0.0, 0.05),
		Vector3(-0.24, 0.16, 0.0),
		Vector3(0.22, 0.12, 0.02),
		Vector3(-0.14, -0.2, 0.03),
		Vector3(0.18, -0.16, 0.0),
	]
	for offset: Vector3 in offsets:
		_add_sphere(0.17, offset)


## Crystals set into a shallow recess: only reads once the lamp is pointed into
## the pocket, which is the "hidden until you look" case.
func _build_pocket() -> void:
	# The recess wall, darker for sitting back from the surface.
	_add_box(Vector3(0.7, 0.7, 0.1), Vector3(0.0, 0.0, -0.18))
	var offsets := [
		Vector3(-0.12, 0.1, -0.02),
		Vector3(0.14, 0.06, 0.0),
		Vector3(0.0, -0.14, -0.04),
	]
	for offset: Vector3 in offsets:
		_add_box(Vector3(0.12, 0.22, 0.12), offset)


## A small core ringed by scattered specks - the faint "something is here" clue
## rather than an obvious mass.
func _build_flecks() -> void:
	_add_sphere(0.14, Vector3.ZERO)
	var offsets := [
		Vector3(-0.32, 0.22, 0.0),
		Vector3(0.3, 0.26, 0.01),
		Vector3(0.36, -0.1, 0.0),
		Vector3(-0.28, -0.2, 0.02),
		Vector3(0.1, 0.36, 0.0),
		Vector3(-0.14, -0.34, 0.0),
	]
	for offset: Vector3 in offsets:
		_add_box(Vector3(0.06, 0.06, 0.06), offset)


func _add_box(size: Vector3, local_position: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_chunk(mesh, local_position)


func _add_sphere(radius: float, local_position: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_add_chunk(mesh, local_position)


func _add_chunk(mesh: Mesh, local_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material
	instance.position = local_position
	add_child(instance)
	_meshes.append(instance)
