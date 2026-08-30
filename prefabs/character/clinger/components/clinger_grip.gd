class_name ClingerGrip
extends Node

## Everything that happens while a clinger is on a face: the three drains, the press count
## and the peel that count buys.
##
## IT NEVER REPARENTS ANYTHING AND NEVER TOUCHES HeadCamera. `Clinger` asks for
## `anchor_transform()` each tick and drives its own body from it, which keeps the creature
## a level-owned node with its own lifetime -- so a respawn that teleports the player, or a
## player freed outright, costs one field write instead of tree surgery.

## Each press, for whoever wants to make a noise about it.
signal peeled

## Handed back, with the player it let go of.
signal shed(victim: Node3D)

## How fast the shown peel catches up to the press count, so a press reads as a jerk
## rather than a jump.
const PEEL_SPRING := 14.0

## What one full peel buys: the bottom edge tips off the glass and the whole body backs
## out. Both only ever INCREASE the distance to the near plane.
const PEEL_DEGREES := 34.0
const PEEL_METRES := 0.06

## Where a fresh grip sits in the head's frame. camera_near is 0.05 m, so 0.24 m is nearly
## five times the clearance it needs, and the peel only adds to it.
const GRIP_OFFSET := Vector3(0.0, -0.02, -0.24)

@export var settings: PlayerSettings

var _victim: Node3D = null
var _head: Node3D = null
var _input: PlayerInput = null
var _presses := 0
var _wanted_peel := 0.0
var _shown_peel := 0.0


## Takes hold of a suit, or refuses one it has no business billing. Returns whether it
## took. A networked body is somebody else's to drive, and the creature is solo-only.
func attach(victim: Node3D) -> bool:
	var health := HazardDamage.health_of(victim)
	if health == null or health.externally_driven:
		return false
	release()
	_victim = victim
	_head = HazardDamage.head_of(victim)
	_presses = 0
	_wanted_peel = 0.0
	_shown_peel = 0.0
	_input = HazardDamage.input_of(victim)
	if _input != null:
		_input.struggle_listening = true
		_input.struggled.connect(_on_struggled)
	# Dying and respawning both have to let go, and for the same reason: PlayerRespawn
	# writes the body's transform directly, so a grip that outlived either would drag a
	# creature across the level still attached to a suit that has been put back.
	var life := victim.get_node_or_null("Life") as PlayerLife
	if life != null:
		life.died.connect(release)
	var respawn := victim.get_node_or_null("Respawn") as PlayerRespawn
	if respawn != null:
		respawn.respawned.connect(release)
	return true


func release() -> void:
	if _victim == null:
		return
	if _input != null and is_instance_valid(_input):
		_input.struggle_listening = false
		if _input.struggled.is_connected(_on_struggled):
			_input.struggled.disconnect(_on_struggled)
	if is_instance_valid(_victim):
		var life := _victim.get_node_or_null("Life") as PlayerLife
		if life != null and life.died.is_connected(release):
			life.died.disconnect(release)
		var respawn := _victim.get_node_or_null("Respawn") as PlayerRespawn
		if respawn != null and respawn.respawned.is_connected(release):
			respawn.respawned.disconnect(release)
	_victim = null
	_head = null
	_input = null


func is_attached() -> bool:
	return _victim != null and is_instance_valid(_victim)


## Bills the suit for one frame of being worn and eases the peel toward the press count.
func authority_step(delta: float) -> void:
	if not is_attached():
		release()
		return
	var power := HazardDamage.power_of(_victim)
	if power != null:
		power.spend(ClingerState.bill(settings.clinger_power_drain_per_second, delta))
	var oxygen := HazardDamage.oxygen_of(_victim)
	if oxygen != null:
		oxygen.spend(ClingerState.bill(settings.clinger_oxygen_drain_per_second, delta))
	var health := HazardDamage.health_of(_victim)
	if health != null:
		health.take_damage(
			ClingerState.bill(settings.clinger_health_drain_per_second, delta),
			PlayerHealth.Source.CLINGER
		)
	_shown_peel = lerpf(_shown_peel, _wanted_peel, ClingerSurface.smoothing(PEEL_SPRING, delta))


## Where the body should put itself this frame.
##
## Belly to the glass -- the shell's +Y turned to face away from the eye, so the eight legs
## open ACROSS the view rather than into it.
func anchor_transform() -> Transform3D:
	if not is_instance_valid(_head):
		return Transform3D.IDENTITY
	var facing := Basis(Vector3.RIGHT, -PI / 2.0)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(PEEL_DEGREES) * _shown_peel)
	var at := GRIP_OFFSET + Vector3(0.0, 0.0, -PEEL_METRES * _shown_peel)
	return _head.global_transform * Transform3D(tilt * facing, at)


func peel() -> float:
	return _shown_peel


func debug_state() -> Dictionary:
	return {
		"attached": is_attached(),
		"presses": _presses,
		"wanted_peel": _wanted_peel,
		"shown_peel": _shown_peel,
	}


func _on_struggled() -> void:
	_presses += 1
	_wanted_peel = ClingerState.peel_fraction(_presses, settings.clinger_interaction_count)
	peeled.emit()
	if _presses < settings.clinger_interaction_count:
		return
	var victim := _victim
	release()
	shed.emit(victim)
