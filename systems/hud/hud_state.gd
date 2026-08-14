class_name HudState
extends Node

## Everything the HUD reads, and the only thing it reads.
##
## Widgets bind to the signals here and to nothing else, which is what lets four
## different layouts be swapped underneath the same running game without any
## per-variant wiring. Deliberately shaped like PowerStore - public fields, a change
## epsilon, and a signal per readout rather than a poll - so that when the real suit
## systems arrive they push into this the same way the power prototype already
## pushes into its store.
##
## This is not on the GlobalSignalBus and should not move there. That bus carries
## level and menu lifecycle, which is one event per scene change; this is per-frame
## gameplay telemetry with a different lifetime, and mixing them would mean a HUD
## that outlives the thing it is reporting on.
##
## The signals are typed int rather than Status because gdlint requires signals to
## be declared above enums, so the enum does not exist yet at that point in the file.

signal power_changed(fraction: float)
signal oxygen_changed(fraction: float)
signal tether_changed(attached: bool, metres: float)
signal contacts_changed(contacts: PackedVector2Array)
signal objective_changed(shown: bool, at: Vector2)
signal status_changed(status: int)

## What the face reports. Three steps rather than a continuous value, and three
## rather than any other number because the designer drew exactly three faces -
## HUD_UI Status Green, Yellow and Red. There is no drawing for 43% worried.
enum Status { NOMINAL, STRAINED, CRITICAL }

## How far a fraction must move before its signal fires. Finer than the smallest
## visible step any widget has - the oxygen ring's eight dashes are 0.125 apart and
## the power meter's six cells 0.167 - so nothing visible is ever skipped, while a
## smooth drain stops redrawing the HUD several hundred times a second.
const CHANGE_EPSILON := 0.001

## Where the face changes. Here rather than in whatever is driving the HUD, because
## the demo driver and the preview's sliders both need it, and a suit that disagrees
## with itself about when to look worried is worse than either answer would be.
const STRAINED_BELOW := 0.55
const CRITICAL_BELOW := 0.25

var power := 1.0:
	set(value):
		power = clampf(value, 0.0, 1.0)
		if absf(power - _announced_power) < CHANGE_EPSILON:
			return
		_announced_power = power
		power_changed.emit(power)

var oxygen := 1.0:
	set(value):
		oxygen = clampf(value, 0.0, 1.0)
		if absf(oxygen - _announced_oxygen) < CHANGE_EPSILON:
			return
		_announced_oxygen = oxygen
		oxygen_changed.emit(oxygen)

## Metres, not a fraction. The readout says "33m", and a fraction would need a tether
## length here that only the suit knows.
var tether_metres := 0.0:
	set(value):
		tether_metres = maxf(value, 0.0)
		_announce_tether()

var tether_attached := false:
	set(value):
		tether_attached = value
		_announce_tether()

## Unit-disc coordinates, -1 to 1, already rotated into the radar's frame. A packed
## array rather than objects because the radar redraws whole and a HUD-sized contact
## list allocating one object per blip every frame would be pure churn.
var contacts := PackedVector2Array():
	set(value):
		contacts = value
		contacts_changed.emit(contacts)

var objective_shown := false
var objective_at := Vector2.ZERO

var status: Status = Status.NOMINAL:
	set(value):
		if value == status:
			return
		status = value
		status_changed.emit(status)

## Deliberately impossible starting values, so the first real assignment always
## announces however it compares.
var _announced_power := -1.0
var _announced_oxygen := -1.0
var _announced_metres := -1
var _announced_attached := false


## Fires every signal at its current value. Called by a HUD as it binds, so a variant
## swapped in halfway through a run shows the truth immediately rather than waiting
## for the next thing to change. This is the seeding half of the connect-then-seed
## pattern power_hud.gd uses on the suit bar.
func announce_all() -> void:
	power_changed.emit(power)
	oxygen_changed.emit(oxygen)
	tether_changed.emit(tether_attached, tether_metres)
	contacts_changed.emit(contacts)
	objective_changed.emit(objective_shown, objective_at)
	status_changed.emit(status)


## The face for a supply fraction - whichever of power and oxygen is worse, since
## either one running out is the same problem from the suit's point of view.
static func status_for(fraction: float) -> Status:
	if fraction < CRITICAL_BELOW:
		return Status.CRITICAL
	if fraction < STRAINED_BELOW:
		return Status.STRAINED
	return Status.NOMINAL


func set_objective(shown: bool, at: Vector2) -> void:
	if shown == objective_shown and at.is_equal_approx(objective_at):
		return
	objective_shown = shown
	objective_at = at
	objective_changed.emit(objective_shown, objective_at)


## The readout shows whole metres, so it is told in whole metres. Same reasoning as
## PowerHud's 0.1s refresh clock: rebuild the string only as often as the string can
## actually differ.
func _announce_tether() -> void:
	var whole := roundi(tether_metres)
	if whole == _announced_metres and tether_attached == _announced_attached:
		return
	_announced_metres = whole
	_announced_attached = tether_attached
	tether_changed.emit(tether_attached, tether_metres)
