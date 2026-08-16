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

## A network driver owns authority ticks and replica presentation while true.
var externally_driven := false

var _firing := false
var _beam_endpoint := Vector3.ZERO

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
	if externally_driven:
		return
	authority_step(delta, input.mine_held)


## Advances the authoritative tool, including charge spend and world damage.
func authority_step(delta: float, held: bool) -> void:
	_set_firing(held and can_fire())
	if _firing:
		_cut(delta)


func is_firing() -> bool:
	return _firing


func beam_endpoint() -> Vector3:
	return _beam_endpoint


## The beam this tool draws with, or null when the model is not the laser prefab.
func laser_beam() -> MiningLaserBeam:
	return _beam


## Gives the controlling client an immediate beam while authority catches up.
## This performs a read-only ray query and presentation transition only.
func preview_step(held: bool) -> void:
	var active := held and can_fire()
	if not active:
		apply_network_presentation(false, _beam_endpoint)
		return
	var hit := query_beam_hit()
	apply_network_presentation(true, _endpoint_for_hit(hit))


## Updates beam and animation state without raycasts, damage, or power spend.
func apply_network_presentation(active: bool, endpoint: Vector3) -> void:
	_beam_endpoint = endpoint
	_set_firing(active)
	if _firing and _beam != null:
		_beam.fire_at(_beam_endpoint)


## The laser runs on suit power, and your hands have to be free — the design
## states outright that carrying loot means no digging.
func can_fire() -> bool:
	return power.has_power() and hands.can_mine()


## Casts along the beam and reports what it is breaking. The cast is its own
## query rather than the grab ray, because the laser reaches much further than
## arm's length.
func _cut(delta: float) -> void:
	power.spend(settings.mining_power_per_second * delta)

	var hit := query_beam_hit()
	_beam_endpoint = _endpoint_for_hit(hit)
	if _beam != null:
		# Nothing in range still draws a beam — it just runs out at the far end.
		_beam.fire_at(_beam_endpoint)
	if hit.is_empty():
		return

	var target := hit["collider"] as Node3D
	if target == null:
		return
	mining.emit(target, hit["position"], settings.mining_damage_per_second * delta)
	if target.has_method("take_mining_damage"):
		target.take_mining_damage(settings.mining_damage_per_second * delta, hit["position"])


## Where the beam would land right now. Read-only, so a warm-up can pay for the
## first query against the level before gameplay asks for it.
func query_beam_hit() -> Dictionary:
	var origin := mine_ray.global_position
	var beam_end := _maximum_beam_endpoint()
	var query := PhysicsRayQueryParameters3D.create(origin, beam_end)
	query.exclude = [get_parent().get_rid()]
	return mine_ray.get_world_3d().direct_space_state.intersect_ray(query)


func _endpoint_for_hit(hit: Dictionary) -> Vector3:
	return _maximum_beam_endpoint() if hit.is_empty() else hit["position"] as Vector3


func _maximum_beam_endpoint() -> Vector3:
	return mine_ray.global_position - mine_ray.global_transform.basis.z * settings.mining_range


func _set_firing(active: bool) -> void:
	if active == _firing:
		return
	_firing = active
	if _firing:
		started_firing.emit()
	else:
		stopped_firing.emit()
		if _beam != null:
			_beam.hold_fire()
