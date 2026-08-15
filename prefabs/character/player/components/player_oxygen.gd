class_name PlayerOxygen
extends Node

## This player's personal oxygen. A powered tether refills it; with no power it
## drains, and once the tether is cut every burst of thrust spends it directly.
## Each player owns their own, which is why this is a component and not a system.

signal oxygen_changed(fraction: float)
signal emptied

## Matches HudState's gate: finer than the readout can show, so nothing visible
## is skipped and a smooth drain does not redraw the HUD every frame.
const CHANGE_EPSILON := 0.001

@export var settings: PlayerSettings

var oxygen := 0.0

var _announced_fraction := -1.0
var _was_empty := false

@onready var input: PlayerInput = %Input
@onready var tether: PlayerTether = %Tether
@onready var power: PlayerPowerClient = %PowerClient


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerOxygen has no settings; running on PlayerSettings defaults.")
	oxygen = settings.oxygen_capacity * clampf(settings.oxygen_start_fraction, 0.0, 1.0)
	_announce()


func _process(delta: float) -> void:
	oxygen = PlayerOxygenModel.step(oxygen, settings.oxygen_capacity, rate_per_second(), delta)
	_announce()

	var empty := oxygen <= 0.0
	if empty and not _was_empty:
		emptied.emit()
	_was_empty = empty


## Oxygen gained or lost this second. Negative is draining.
func rate_per_second() -> float:
	return PlayerOxygenModel.rate_per_second(
		tether.is_attached(),
		power.has_power(),
		input.thrust_fraction(),
		settings.oxygen_regen_per_second,
		settings.oxygen_idle_drain_per_second,
		settings.oxygen_thrust_cost_per_second
	)


func fraction() -> float:
	return PlayerOxygenModel.fraction(oxygen, settings.oxygen_capacity)


## Seconds of air left at the current rate, or INF while it is refilling.
func seconds_remaining() -> float:
	return PlayerOxygenModel.seconds_remaining(oxygen, rate_per_second())


func is_empty() -> bool:
	return oxygen <= 0.0


## Refills the tank, for an oxygen pocket or a return to the elevator.
func refill(amount: float) -> void:
	oxygen = PlayerOxygenModel.step(oxygen, settings.oxygen_capacity, amount, 1.0)
	_announce()


func _announce() -> void:
	var current := fraction()
	if absf(current - _announced_fraction) < CHANGE_EPSILON:
		return
	_announced_fraction = current
	oxygen_changed.emit(current)
