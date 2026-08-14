class_name HudDemoDriver
extends Node

## Fake telemetry, so the HUDs can be judged before the systems they report on exist.
##
## Nothing in the game currently produces oxygen, radar contacts, tether distance or
## a suit status - the power prototype has a PowerStore and that is all. Comparing
## four layouts on four frozen HUDs would answer nothing: half of what makes a
## readout good or bad is how it behaves while the number is moving.
##
## Every rate here is invented and none of it is a design proposal. When real systems
## arrive they push into HudState directly and this node comes out.

## Seconds for a full drain-and-recharge cycle. Deliberately not equal, so the two
## meters drift out of phase and you see them in every combination.
const POWER_PERIOD := 17.0
const OXYGEN_PERIOD := 26.0

## Seconds between the tether clipping and unclipping.
const TETHER_PERIOD := 11.0
const TETHER_MIN := 4.0
const TETHER_MAX := 38.0

## One contact, because one is what the game has - the alien. Five was a stress test of
## the old flat radar and it hid the thing that now matters, which is that a single blip
## has to be readable on its own.
const CONTACT_COUNT := 1

## Radians per second around the dish.
const CONTACT_BASE_SPEED := 0.22

## Metres. The sweep runs past the radar's default 30m max_distance on purpose, so the
## preview shows the cull happening rather than leaving you to trust that it would.
const CONTACT_NEAR := 4.0
const CONTACT_FAR := 38.0
const CONTACT_RANGE_PERIOD := 19.0

## Metres above and below, and the seconds for a full rise and fall. Slower than the
## orbit and not a divisor of it, so the blip traces the whole bubble instead of
## repeating one path.
const CONTACT_HEIGHT := 22.0
const CONTACT_HEIGHT_PERIOD := 13.0

@export var enabled := true

var _state: HudState
var _elapsed := 0.0


func _process(delta: float) -> void:
	if not enabled or _state == null:
		return
	_elapsed += delta
	_state.power = _triangle(_elapsed / POWER_PERIOD)
	_state.oxygen = _triangle(_elapsed / OXYGEN_PERIOD + 0.35)
	_drive_tether()
	_drive_contacts()
	_state.status = _derive_status()


func bind(state: HudState) -> void:
	_state = state


## A 0..1 ramp up and back down again. Smoother than a sawtooth, which would snap the
## meter from empty to full and make the fade on the leading cell impossible to see.
func _triangle(phase: float) -> float:
	var t := fposmod(phase, 1.0)
	return t * 2.0 if t < 0.5 else 2.0 - t * 2.0


func _drive_tether() -> void:
	var cycle := fposmod(_elapsed / TETHER_PERIOD, 1.0)
	_state.tether_attached = cycle < 0.75
	var swing := 0.5 + 0.5 * sin(_elapsed * 0.6)
	_state.tether_metres = lerpf(TETHER_MIN, TETHER_MAX, swing)


## The contact orbits, rises and falls, and walks out of range and back, on three
## periods that do not divide into each other. Three motions rather than one because
## each demonstrates a different part of the radar - the ellipse, the height lift, and
## the max_distance cull - and a blip doing only the first would leave the other two
## looking broken rather than untested.
##
## Metres in the player's frame, which is what HudState.contacts is now: +X right,
## +Y up, -Z forward.
func _drive_contacts() -> void:
	var contacts := PackedVector3Array()
	contacts.resize(CONTACT_COUNT)
	for i in CONTACT_COUNT:
		var angle := _elapsed * CONTACT_BASE_SPEED
		angle += TAU * float(i) / float(CONTACT_COUNT)
		var reach := lerpf(CONTACT_NEAR, CONTACT_FAR, _triangle(_elapsed / CONTACT_RANGE_PERIOD))
		var height := CONTACT_HEIGHT * sin(TAU * _elapsed / CONTACT_HEIGHT_PERIOD)
		contacts[i] = Vector3(cos(angle) * reach, height, sin(angle) * reach)
	_state.contacts = contacts
	_state.set_objective(true, Vector2(0.62, -0.48))


func _derive_status() -> HudState.Status:
	return HudState.status_for(minf(_state.power, _state.oxygen))
