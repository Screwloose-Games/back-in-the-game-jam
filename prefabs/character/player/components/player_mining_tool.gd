class_name PlayerMiningTool
extends Node

## Fires the mining laser while power allows and the hands are free. It does not
## know what ore is: it reports what the beam is breaking and how fast, and
## whatever it hit decides what that means.

signal started_firing
signal stopped_firing
## Emitted each frame the beam is on something that can be mined.
signal mining(target: Node3D, at: Vector3, damage: float)

@export var settings: PlayerSettings

## The laser's model, shown only while the tool is out.
@export var tool_model: Node3D

var _firing := false

@onready var mine_ray: RayCast3D = %GrabRay
@onready var input: PlayerInput = %Input
@onready var power: PlayerPowerClient = %PowerClient
@onready var hands: PlayerHands = %Hands

## The same node as tool_model when the model is the laser prefab, which owns the
## beam it draws. Null for any other model, and the tool still cuts without one.
@onready var _beam := tool_model as MiningLaserBeam


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerMiningTool has no settings; running on PlayerSettings defaults.")


func _physics_process(delta: float) -> void:
	var wants_to_fire := input.mine_held and can_fire()
	if wants_to_fire != _firing:
		_firing = wants_to_fire
		if _firing:
			started_firing.emit()
		else:
			stopped_firing.emit()
			if _beam != null:
				_beam.hold_fire()
	if _firing:
		_cut(delta)


func is_firing() -> bool:
	return _firing


## The laser runs on suit power, and your hands have to be free — the design
## states outright that carrying loot means no digging.
func can_fire() -> bool:
	return power.has_power() and hands.can_mine()


## Casts along the beam and reports what it is breaking. The cast is its own
## query rather than the grab ray, because the laser reaches much further than
## arm's length.
func _cut(delta: float) -> void:
	power.spend(settings.mining_power_per_second * delta)

	var space_state := mine_ray.get_world_3d().direct_space_state
	var origin := mine_ray.global_position
	var beam_end := origin - mine_ray.global_transform.basis.z * settings.mining_range
	var query := PhysicsRayQueryParameters3D.create(origin, beam_end)
	query.exclude = [get_parent().get_rid()]
	var hit := space_state.intersect_ray(query)
	if _beam != null:
		# Nothing in range still draws a beam — it just runs out at the far end.
		_beam.fire_at(beam_end if hit.is_empty() else hit["position"] as Vector3)
	if hit.is_empty():
		return

	var target := hit["collider"] as Node3D
	if target == null:
		return
	mining.emit(target, hit["position"], settings.mining_damage_per_second * delta)
	if target.has_method("take_mining_damage"):
		target.take_mining_damage(settings.mining_damage_per_second * delta, hit["position"])
