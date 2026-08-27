class_name Blockage
extends StaticBody3D

## Collapsed rock sealing an optional route. Mining one open is loud, slow and
## expensive -- and none of that needs code here: at the shipped mining figures this
## plug is twenty-five seconds of held beam and two hundred charge against a suit that
## holds a hundred, so you cannot finish one without a tether, and PlayerBeamNoiseEmitter
## is already reporting the cut at full strength the entire time.

## The collapse itself, once. AsteroidLevel wires this to the creature.
signal world_noise(at: Vector3, loudness: float)
signal cleared

## How much beam it takes. A mineral chunk is five.
@export_range(1.0, 200.0, 1.0) var blockage_health: float = 25.0

## Raw loudness of the collapse. Above 1.0 deliberately, for the reason GasPod gives.
@export_range(0.0, 4.0, 0.1) var collapse_loudness: float = 1.8

var _damage_taken := 0.0
var _hit_this_frame := false
var _spent := false

@onready var _rubble: Node3D = $Rubble
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _impact: MiningImpact = $MiningImpact
@onready var _sfx: AudioStreamPlayer3D = $Sfx


func _ready() -> void:
	add_to_group(HazardDamage.NOISE_GROUP)


## How far through it the crew is, 0 to 1.
func progress() -> float:
	return clampf(_damage_taken / maxf(blockage_health, 0.001), 0.0, 1.0)


## Called every physics frame the beam is on it, so it latches and integrates.
func take_mining_damage(damage: float, at: Vector3, _tool: PlayerMiningTool) -> void:
	if _spent:
		return
	_hit_this_frame = true
	_damage_taken += damage
	_impact.global_position = at


func _physics_process(_delta: float) -> void:
	if _spent:
		return
	if not _hit_this_frame:
		_impact.stop()
		return
	_hit_this_frame = false
	_impact.start()
	if _damage_taken >= blockage_health:
		open()


## Takes the plug out of the world and drops one rockfall for the creature to hear.
func open() -> void:
	if _spent:
		return
	_spent = true
	_impact.stop()
	_rubble.visible = false
	_shape.set_deferred("disabled", true)
	world_noise.emit(global_position, collapse_loudness)
	cleared.emit()
	_sfx.play(0.0)
	# A tree timer rather than `await _sfx.finished`, for the reason GasPod gives.
	var linger := 0.0 if _sfx.stream == null else _sfx.stream.get_length()
	await get_tree().create_timer(maxf(linger, 0.05)).timeout
	queue_free()
