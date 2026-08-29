class_name MineralChunk
extends RigidBody3D

## A single voxel-cube unit of ore. Damage accumulates continuously while the
## beam stays on it; each whole point crossed transfers one mineral piece to
## the player immediately, so the count ticks up smoothly rather than in one
## lump at the end. The chunk is spent and removed once its health runs out.
##
## THE SCENE PUTS IT ON LAYER 6, `ore`, AND THAT IS LOAD-BEARING RATHER THAN TIDINESS.
## It carried no collision_layer line at all, so it inherited RigidBody3D's default of 1 --
## the `hull` layer, byte-identical to cave rock for every ray in the game. A 1.2 x 2.6 m
## box that reads as rock is a navigable island the clinger crawls onto and cannot get off,
## and it also bakes into the stalker's nav graph as permanent rock that survives the chunk
## being mined out. Anything that needs to hit ore names bit 6; the mining beam passes no
## mask at all and is unaffected. The note lives here because an editor save drops .tscn
## comments.

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


## Re-applies the owning deposit's settings, for a chunk that was baked into a
## level with older ones.
func configure(new_type: MineralType, new_tuning: MiningTuning) -> void:
	mineral_type = new_type
	tuning = new_tuning
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
