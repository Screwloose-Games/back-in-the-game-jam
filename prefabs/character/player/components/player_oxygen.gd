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

## A network driver advances authority and applies replica oxygen while true.
var externally_driven := false

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
	if externally_driven:
		return
	authority_step(delta)


## Advances authoritative oxygen. An explicit thrust fraction lets a host use
## the accepted command for a remote player instead of that replica's idle Input.
func authority_step(delta: float, thrust_fraction_override := -1.0) -> void:
	oxygen = (
		PlayerOxygenModel
		. step(
			oxygen,
			settings.oxygen_capacity,
			rate_per_second(thrust_fraction_override),
			delta,
		)
	)
	_announce()

	var empty := oxygen <= 0.0
	if empty and not _was_empty:
		emptied.emit()
	_was_empty = empty


## Oxygen gained or lost this second. Negative is draining.
func rate_per_second(thrust_fraction_override := -1.0) -> float:
	var thrust_fraction := input.thrust_fraction()
	if thrust_fraction_override >= 0.0:
		thrust_fraction = clampf(thrust_fraction_override, 0.0, 1.0)
	return PlayerOxygenModel.rate_per_second(
		tether.is_attached(),
		power.has_power(),
		thrust_fraction,
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


## Applies a replicated ratio and updates presentation signals, but deliberately
## does not emit the authority-only emptied gameplay event.
func apply_network_fraction(value: float) -> void:
	var safe_value := clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	oxygen = maxf(settings.oxygen_capacity, 0.0) * safe_value
	_was_empty = oxygen <= 0.0
	_announce()


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
