class_name PlayerRespawn
extends Node

## Remembers where the player entered the level and puts them back there at
## rest, empty-handed and unclipped. The level is responsible for placing the
## prefab before it enters the tree; the pose it arrives with is the one this
## returns to.

signal respawned

## A network driver sets this before the node enters the tree and forwards reset
## requests to the host rather than letting a client teleport itself directly.
var externally_driven := false

var _spawn_transform: Transform3D

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input
@onready var oxygen: PlayerOxygen = %Oxygen
@onready var power: PlayerPowerClient = %PowerClient
@onready var lamp: PlayerLamp = %Lamp
@onready var hands: PlayerHands = %Hands


func _ready() -> void:
	_spawn_transform = body.global_transform
	if not externally_driven:
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


## The pose plus everything the suit was carrying, for a death rather than a stuck player.
##
## `apply_network_fraction` is the setter both stores already have; it re-announces to the
## HUD and deliberately skips the authority-only `emptied` event, which is what a reset wants.
func reset() -> void:
	respawn()
	oxygen.apply_network_fraction(oxygen.settings.oxygen_start_fraction)
	power.apply_network_fraction(power.settings.suit_start_fraction)
	lamp.set_lit(lamp.settings.lamp_starts_on)
	hands.stow_tool()
