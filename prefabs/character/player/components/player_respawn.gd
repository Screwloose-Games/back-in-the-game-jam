class_name PlayerRespawn
extends Node

## Remembers where the player entered the level and puts them back there at
## rest, empty-handed and unclipped. The level is responsible for placing the
## prefab before it enters the tree; the pose it arrives with is the one this
## returns to.

signal respawned

var _spawn_transform: Transform3D

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input


func _ready() -> void:
	_spawn_transform = body.global_transform
	input.reset_requested.connect(respawn)


## Overrides the remembered pose, for a level that moves the player after spawn
## — riding the elevator down, for one.
func set_spawn_transform(transform: Transform3D) -> void:
	_spawn_transform = transform


func spawn_transform() -> Transform3D:
	return _spawn_transform


func respawn() -> void:
	var grab := get_parent().get_node_or_null("Grab") as PlayerGrab
	if grab != null:
		grab.release()
	var tether := get_parent().get_node_or_null("Tether") as PlayerTether
	if tether != null:
		tether.unclip()

	var locomotion := get_parent().get_node_or_null("Locomotion") as PlayerLocomotion
	if locomotion != null:
		locomotion.halt()
	var collision := get_parent().get_node_or_null("CollisionResponse") as PlayerCollisionResponse
	if collision != null:
		collision.clear_contact()

	input.clear()
	body.global_transform = _spawn_transform
	respawned.emit()
