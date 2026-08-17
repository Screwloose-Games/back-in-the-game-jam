class_name PlayerPowerClient
extends Node

## Draws power from the shared box for the lamp and the mining tool, and says
## when there is none. The box is found by group lookup rather than wired per
## placement, so the prefab works dropped into any level — the same trick
## AlienNavAgent uses to find its navigation baker.

signal charge_changed(fraction: float)
signal supply_changed(connected: bool)
signal power_lost
signal power_restored

## The group the shared power and oxygen box puts itself in.
const BOX_GROUP := &"life_support_box"

## How far the fraction must move before charge_changed fires. Finer than the
## HUD's whole-percent readout, so nothing visible is skipped.
const CHANGE_EPSILON := 0.0005

## How far charge has to climb back before power counts as restored. A suit
## tethered to a live box drains and refills on the same frame at zero, so
## without the gap the warning would flap at frame rate.
const RESTORE_FRACTION := 0.02

@export var settings: PlayerSettings

## A network driver advances authority and applies replica charge while true.
var externally_driven := false

## The suit's own battery. Charge is in arbitrary units; only ratios matter.
var charge := 0.0

var _box: Node
var _announced_fraction := -1.0
var _was_powered := true

@onready var tether: PlayerTether = %Tether


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerPowerClient has no settings; running on PlayerSettings defaults.")
	charge = settings.suit_capacity * clampf(settings.suit_start_fraction, 0.0, 1.0)
	_was_powered = has_power()
	_find_box()
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if externally_driven:
		return
	authority_step(delta)


## Advances authoritative drain and any shared-box recharge.
func authority_step(delta: float) -> void:
	if settings.suit_drain_per_second > 0.0:
		spend(settings.suit_drain_per_second * delta)
	_recharge_from_box(delta)


func fraction() -> float:
	if settings.suit_capacity <= 0.0:
		return 0.0
	return clampf(charge / settings.suit_capacity, 0.0, 1.0)


func has_power() -> bool:
	return charge > 0.0


## Applies a replicated ratio without drawing from or returning charge to a box.
func apply_network_fraction(value: float) -> void:
	var safe_value := clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	charge = maxf(settings.suit_capacity, 0.0) * safe_value
	_announce()


## Whether a live tether currently reaches the shared box.
func is_supplied() -> bool:
	return _box != null and tether.is_attached() and tether.tethered_object() == _box_body()


## Takes up to `amount` out and returns what was actually taken. The return
## value is the point: a draw that assumed it got what it asked for would run
## the lamp on charge that is not there.
func spend(amount: float) -> float:
	var taken := minf(maxf(amount, 0.0), charge)
	charge -= taken
	_announce()
	return taken


## Puts up to `amount` in and returns what was accepted.
func store(amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), settings.suit_capacity - charge)
	charge += accepted
	_announce()
	return accepted


## Refills the suit from the box while the tether is live. The box is asked for
## the charge rather than told, so an empty box stops the suit filling.
func _recharge_from_box(delta: float) -> void:
	if not is_supplied():
		return
	var wanted := settings.suit_charge_per_second * delta
	var supplied := wanted
	if _box.has_method("spend"):
		supplied = _box.spend(wanted)
	var unused := wanted - store(supplied)
	# Hand back what would not fit, so a full suit stops draining the box.
	if unused > 0.0 and _box.has_method("store"):
		_box.store(unused)


func _box_body() -> Node:
	if _box == null:
		return null
	# The box's physics body is what a tether clips to, not its logic node.
	if _box is RigidBody3D:
		return _box
	return _box.get_parent()


func _find_box() -> void:
	var found := get_tree().get_first_node_in_group(BOX_GROUP)
	if found == _box:
		return
	_box = found
	supply_changed.emit(_box != null)


## Re-binds when a box enters the level after the player, which is what makes
## the prefab safe to drop in before the level has finished building itself.
func _on_node_added(node: Node) -> void:
	if _box == null and node.is_in_group(BOX_GROUP):
		_find_box()


func _announce() -> void:
	var current := fraction()
	# Ahead of the epsilon gate: the tick that empties the suit can move the
	# fraction by less than CHANGE_EPSILON, and losing power is not a change
	# anyone should be able to miss.
	_announce_powered_state(current)
	if absf(current - _announced_fraction) < CHANGE_EPSILON:
		return
	_announced_fraction = current
	charge_changed.emit(current)


## Edges only, with a dead band on the way back up so a suit drawing from a box
## at zero does not chatter.
func _announce_powered_state(current: float) -> void:
	if _was_powered and not has_power():
		_was_powered = false
		power_lost.emit()
	elif not _was_powered and current >= RESTORE_FRACTION:
		_was_powered = true
		power_restored.emit()
