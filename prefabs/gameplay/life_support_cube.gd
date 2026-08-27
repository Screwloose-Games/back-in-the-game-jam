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

## The group every player puts itself in, used to find who is moored to this box.

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

@onready var handle: Interactable = $Handle

@onready var lamp: OmniLight3D = $ChargeLamp

@onready var bar: BatteryBar = $BatteryBar

@onready var grab_sfx: AudioStreamPlayer3D = $GrabSfx

@onready var charge_sfx: AudioStreamPlayer3D = $ChargeSfx

@onready var operating_sfx: AudioStreamPlayer3D = $OperatingSfx


func _ready() -> void:
	add_to_group(BOX_GROUP)

	charge = capacity * clampf(start_fraction, 0.0, 1.0)

	_apply_lamp()

	_apply_bar()

	_apply_operating_sfx()

	_announce()

	handle.interacted.connect(_on_handle_interacted)

	handle.hold_started.connect(_on_crank_started.unbind(1))

	handle.hold_cancelled.connect(_on_crank_stopped)


func _physics_process(delta: float) -> void:
	if not _cranking:
		return

	store(crank_charge_per_second * delta)

	# Hold until full, and no further. Letting go early keeps whatever went in.

	if fraction() >= 1.0:
		handle.cancel_hold()


func fraction() -> float:
	if capacity <= 0.0:
		return 0.0

	return clampf(charge / capacity, 0.0, 1.0)


func has_charge() -> bool:
	return charge > 0.0


func is_being_cranked() -> bool:
	return _cranking


## Called by whoever picked the box up. The sound lives here rather than on the

## hands so it comes from the box, and so everyone nearby hears it.


func play_grab_sfx() -> void:
	grab_sfx.play(0.0)


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


func _set_cranking(value: bool) -> void:
	if value == _cranking:
		return

	_cranking = value

	cranking_changed.emit(_cranking)


## A tap takes it or puts it down. The reach owns the hands, so it decides which -- and
## refuses when they are already full of something else.
func _on_handle_interacted(interactor: Node3D) -> void:
	var reach := interactor as PlayerInteractor
	if reach == null:
		return
	reach.toggle_carry(self, global_position)


func _on_crank_started() -> void:
	# Nothing to wind on a full box, and ending the hold here is what stops the prompt
	# promising something that will not happen.
	if fraction() >= 1.0:
		handle.cancel_hold()
		return
	_set_cranking(true)
	charge_sfx.play(0.0)


func _on_crank_stopped() -> void:
	if not _cranking:
		return
	_set_cranking(false)
	charge_sfx.stop()


## The hum is the box saying it is alive, so it runs on any charge at all and stops dead
## when there is none left. Driven from _after_change rather than from charge_changed,
## which is epsilon-gated -- the same reason the lamp is.
func _apply_operating_sfx() -> void:
	if operating_sfx == null or has_charge() == operating_sfx.playing:
		return
	if has_charge():
		operating_sfx.play(0.0)
	else:
		operating_sfx.stop()


func _after_change() -> void:
	_apply_lamp()

	_apply_bar()

	_apply_operating_sfx()

	_announce()


## Colour and brightness both follow the charge, so a dying box does not simply

## dim - it turns red first, while there is still time to do something about it.


func _apply_lamp() -> void:
	if lamp == null:
		return

	var level := fraction()

	lamp.light_color = empty_color.lerp(full_color, level)

	lamp.light_energy = lamp_energy * level


## Driven from _after_change rather than from charge_changed, which is

## epsilon-gated - the same reason the lamp is.


func _apply_bar() -> void:
	if bar == null:
		return

	bar.show_fraction(fraction())


func _announce() -> void:
	var current := fraction()

	if absf(current - _announced_fraction) < CHANGE_EPSILON:
		return

	_announced_fraction = current

	charge_changed.emit(current)
