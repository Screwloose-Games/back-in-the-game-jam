class_name PlayerLife
extends Node

## Whether this suit is still alive, and the one way it stops being. Death is a
## moment rather than a state: control is taken away, the death cue is heard, and
## PlayerRespawn puts you back where you started. Anything that can kill calls
## die() — suffocation is wired here, the creature calls it when it lands.

signal died
signal revived

## How long you stay dead. Long enough for Impact_Death_01 to be heard as a death
## rather than as a bump, short enough that a jam playtest keeps moving.
const RESPAWN_DELAY := 1.5

## A network driver sets this before the node enters the tree. Online, dying has
## to run on the host and go through the prediction reset that PlayerNetworkGameplay
## already owns, so this node stands down rather than teleporting a body itself.
var externally_driven := false

var _alive := true

@onready var input: PlayerInput = %Input
@onready var oxygen: PlayerOxygen = %Oxygen
@onready var respawn: PlayerRespawn = %Respawn


func _ready() -> void:
	if not externally_driven:
		oxygen.emptied.connect(die)


func is_alive() -> bool:
	return _alive


## Kills the suit, if it is not already dead. Safe to call from anything.
func die() -> void:
	if not _alive or externally_driven:
		return
	_alive = false
	input.enabled = false
	died.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_instance_valid(self) and is_inside_tree():
		_revive()


## Air comes back with you. Respawning into the empty tank that just killed you
## would leave you alive at zero and unable to suffocate again, because `emptied`
## is edge-gated.
func _revive() -> void:
	respawn.respawn()
	oxygen.refill(oxygen.settings.oxygen_capacity)
	input.enabled = true
	_alive = true
	revived.emit()
