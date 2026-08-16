class_name LifeSupportCube
extends RigidBody3D

## The shared power and oxygen box. It is the reservoir every suit refills from:
## clip a tether to it and the suit draws charge, and turn its crank to put
## charge back in. Its lamp reads the charge, so how much is left is something
## you can see across a tunnel rather than something you have to check.

## Emitted whenever the stored fraction moves, for a HUD or a light to follow.
signal charge_changed(fraction: float)
## Emitted when the crank starts and stops turning. Cranking is loud, and this is
## what the creature's perception layer will listen to.
signal cranking_changed(cranking: bool)

## The group PlayerPowerClient finds the box by. It looks up exactly this name,
## so the box has to join it rather than be wired per placement.
const BOX_GROUP := &"life_support_box"

## The group every player puts itself in, used to find who is near enough to crank.
const PLAYER_GROUP := &"player"

## How far the stored fraction must move before it is re-announced.
const CHANGE_EPSILON := 0.0005

@export_group("Charge")

## Total charge the box holds. Several suits' worth, so it reads as the thing the
## crew shares rather than a second battery.
@export_range(100.0, 5000.0, 50.0) var capacity: float = 1000.0

## How full it starts. Not full: the box running down is the pressure the level
## is built on, and a crew that never has to crank never meets it.
@export_range(0.0, 1.0, 0.05) var start_fraction: float = 0.5

## How fast the crank puts charge back. Faster than a suit drains, so cranking
## is a way out of trouble rather than a way of losing more slowly.
@export_range(0.0, 200.0, 1.0) var crank_charge_per_second: float = 25.0

## How close you have to be to get a hand on the crank.
@export_range(0.5, 8.0, 0.1, "suffix:m") var crank_reach: float = 2.5

@export_group("Lamp")

## Colour at a full box and at an empty one. The box going red is the warning.
@export var full_color := Color(0.35, 1.0, 0.45)

@export var empty_color := Color(1.0, 0.2, 0.12)

## Brightness at a full box. Scaled by the charge, so an empty box is dark.
@export_range(0.0, 16.0, 0.1) var lamp_energy: float = 2.5

## Charge in the same arbitrary units the suit uses; only ratios matter.
var charge := 0.0

var _cranking := false
var _announced_fraction := -1.0

@onready var lamp: OmniLight3D = $ChargeLamp


func _ready() -> void:
	add_to_group(BOX_GROUP)
	charge = capacity * clampf(start_fraction, 0.0, 1.0)
	_apply_lamp()
	_announce()


func _physics_process(delta: float) -> void:
	_set_cranking(_is_being_cranked())
	if _cranking:
		store(crank_charge_per_second * delta)


func fraction() -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(charge / capacity, 0.0, 1.0)


func has_charge() -> bool:
	return charge > 0.0


func is_being_cranked() -> bool:
	return _cranking


## Takes up to `amount` out and returns what was actually there. PlayerPowerClient
## asks rather than tells, so an empty box stops a suit filling.
func spend(amount: float) -> float:
	var taken := minf(maxf(amount, 0.0), charge)
	charge -= taken
	_after_change()
	return taken


## Puts up to `amount` in and returns what was accepted.
func store(amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), capacity - charge)
	charge += accepted
	_after_change()
	return accepted


## Every suit currently moored to this box. The tether is what carries charge, so
## this is also the list of who is drawing on it.
func tethered_players() -> Array[Node]:
	var moored: Array[Node] = []
	for player: Node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		var tether := player.get_node_or_null("Tether") as PlayerTether
		if tether != null and tether.tethered_object() == self:
			moored.append(player)
	return moored


func is_tethered() -> bool:
	return not tethered_players().is_empty()


## Whether anyone within reach is turning the crank. Reach rather than tether, so
## a suit that has run the line out can still swim over and wind it by hand.
func _is_being_cranked() -> bool:
	for player: Node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		var body := player as Node3D
		if body == null or body.global_position.distance_to(global_position) > crank_reach:
			continue
		var input := player.get_node_or_null("Input") as PlayerInput
		if input != null and input.enabled and input.crank_held:
			return true
	return false


func _set_cranking(value: bool) -> void:
	if value == _cranking:
		return
	_cranking = value
	cranking_changed.emit(_cranking)


func _after_change() -> void:
	_apply_lamp()
	_announce()


## Colour and brightness both follow the charge, so a dying box does not simply
## dim - it turns red first, while there is still time to do something about it.
func _apply_lamp() -> void:
	if lamp == null:
		return
	var level := fraction()
	lamp.light_color = empty_color.lerp(full_color, level)
	lamp.light_energy = lamp_energy * level


func _announce() -> void:
	var current := fraction()
	if absf(current - _announced_fraction) < CHANGE_EPSILON:
		return
	_announced_fraction = current
	charge_changed.emit(current)
