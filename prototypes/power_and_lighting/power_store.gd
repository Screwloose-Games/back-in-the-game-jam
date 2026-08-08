class_name PowerStore
extends Node

## One battery. Two of these exist: one on the suit, one in the cube.
##
## Deliberately dumb. It knows its capacity, its charge, and what it leaks on its
## own, and nothing whatsoever about tethers, cranking, or who is allowed to draw
## from it - PowerSystem owns all of that. That is what lets the same node serve
## a 100-unit suit battery that drains constantly and a 600-unit cube that never
## leaks a drop.
##
## Charge is in arbitrary units. Only ratios matter, so PowerKnobs sets the suit
## to 100 and every readout is a percentage.

## Emitted when the charge fraction has moved far enough to be worth redrawing
## something over. Gauges are stepped and readouts are rounded, so firing this
## every frame would be pure cost - see CHANGE_EPSILON.
signal charge_changed(fraction: float)

## How far the fraction must move before charge_changed fires. Under a tenth of
## one percent: finer than the cube gauge's eight segments can show and finer
## than the HUD's whole-percent readout, so nothing visible is ever skipped.
const CHANGE_EPSILON := 0.0005

var capacity := 1.0
var charge := 0.0
var idle_drain_per_second := 0.0

## The fraction charge_changed was last fired at. Starts off-scale so the first
## real update always announces itself.
var _announced_fraction := -1.0


func _process(delta: float) -> void:
	if idle_drain_per_second > 0.0:
		spend(idle_drain_per_second * delta)


## Sets the battery up and fills it. Called instead of exported properties,
## because every value in this prototype lives in PowerKnobs.
func configure(new_capacity: float, start_fraction: float, drain_per_second: float) -> void:
	capacity = maxf(new_capacity, CHANGE_EPSILON)
	idle_drain_per_second = drain_per_second
	charge = capacity * clampf(start_fraction, 0.0, 1.0)
	_announce()


## Resizes the battery, keeping how full it is rather than how much is in it.
##
## Keeping the FRACTION is what makes the capacity slider usable: dragging it
## would otherwise make the lamp lurch bright or dark, and the thing you are
## trying to judge - how long the charge lasts - would be buried under a
## brightness change you did not ask for.
func set_capacity(new_capacity: float) -> void:
	var fraction := get_fraction()
	capacity = maxf(new_capacity, CHANGE_EPSILON)
	charge = capacity * fraction
	_announce()


func get_fraction() -> float:
	return clampf(charge / capacity, 0.0, 1.0)


func is_empty() -> bool:
	return charge <= 0.0


## Takes up to `amount` out and returns what was actually taken.
##
## The return value is the whole point: a transfer that assumed it got what it
## asked for would invent charge out of an empty cube. PowerSystem moves power by
## spending from one store and handing exactly the spent amount to the other.
func spend(amount: float) -> float:
	var taken := minf(maxf(amount, 0.0), charge)
	charge -= taken
	_announce()
	return taken


## Puts up to `amount` in and returns what was actually accepted. The remainder
## is the caller's problem - PowerSystem hands it straight back to where it came
## from, so a full suit stops draining the cube instead of pouring it away.
func store(amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), capacity - charge)
	charge += accepted
	_announce()
	return accepted


## Sets the charge directly, as a fraction. The tuning panel's state buttons use
## this to put the prototype straight into the condition being judged, rather
## than making someone wait three minutes to see the bottom of the dim curve.
func set_fraction(fraction: float) -> void:
	charge = capacity * clampf(fraction, 0.0, 1.0)
	_announce()


func _announce() -> void:
	var fraction := get_fraction()
	if absf(fraction - _announced_fraction) < CHANGE_EPSILON:
		return
	_announced_fraction = fraction
	charge_changed.emit(fraction)
