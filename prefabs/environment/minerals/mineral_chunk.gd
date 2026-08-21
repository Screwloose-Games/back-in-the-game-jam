class_name MineralChunk
extends RigidBody3D

## A single voxel-cube unit of ore. Damage accumulates continuously while the
## beam stays on it; each whole point crossed transfers one mineral piece to
## the player immediately, so the count ticks up smoothly rather than in one
## lump at the end. The chunk is spent and removed once its health runs out.

const DEFAULT_TUNING := preload("res://systems/minerals/mining_tuning_default.tres")

@export var mineral_type: MineralType
@export var tuning: MiningTuning = DEFAULT_TUNING

var _damage_taken := 0.0
var _hit_this_frame := false
var _tool: PlayerMiningTool

@onready var _impact: MiningImpact = $MiningImpact


func _ready() -> void:
	freeze = true
	_apply_material()


func take_mining_damage(_damage: float, at: Vector3, tool: PlayerMiningTool) -> void:
	_hit_this_frame = true
	_tool = tool
	_impact.global_position = at


func _physics_process(delta: float) -> void:
	if not _hit_this_frame or _damage_taken >= tuning.chunk_health:
		_hit_this_frame = false
		_impact.stop()
		return
	_hit_this_frame = false
	_impact.start()
	var before := floori(_damage_taken)
	_damage_taken = minf(_damage_taken + tuning.damage_per_second * delta, tuning.chunk_health)
	var after := floori(_damage_taken)
	for _i in after - before:
		_tool.mineral_collected.emit(mineral_type)
	if _damage_taken >= tuning.chunk_health:
		queue_free()


func _apply_material() -> void:
	if mineral_type == null or mineral_type.chunk_material == null:
		return
	var meshes := find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		(meshes[0] as MeshInstance3D).material_override = mineral_type.chunk_material
	if mineral_type.chunk_material is StandardMaterial3D:
		_impact.set_color((mineral_type.chunk_material as StandardMaterial3D).albedo_color)
