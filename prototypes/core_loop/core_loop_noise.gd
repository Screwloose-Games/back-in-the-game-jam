class_name CoreLoopNoise
extends Node

## Everything you do makes noise, and this is the one place that says how much.
##
## LOUDNESS IS A RADIUS IN METRES: how far away the creature can hear that source.
## Nothing here is in decibels or in arbitrary units, because every number the
## monster director compares it against is a distance, and a scale that needs
## converting is a scale people stop trusting.
##
## ONE EVENT PER TICK, NOT PER FRAME. The director rolls a spawn chance against
## what it hears, so emitting per frame would make the frame rate a hidden
## multiplier on how often the creature turns up. NOISE_TICK_INTERVAL is the rate,
## and the loudest source active during a tick is the one that gets reported -
## noises do not stack, because two things happening at once is not twice as far
## away.
##
## THIS NODE READS Input DIRECTLY for the thrust test, which is a deliberate
## duplication of what the suit does with the same actions. The alternative was a
## public is_thrusting() on the suit, and that file is nine lines under a lint cap
## it already had to be trimmed to reach. Both read the same action names, so they
## can only disagree if somebody rebinds one of them.

## Emitted at most once per tick. `radius` is how far it carries, in metres.
signal noise_made(position: Vector3, radius: float)

## What the thrust test counts as "moving". Below this the stick is at rest and a
## drifting suit stays silent, which is the whole point of being able to coast.
const THRUST_DEADZONE := 0.15

## How far drilling and cranking carry, pushed in from the prototype root.
var drill_radius := CoreLoopKnobs.DRILL_NOISE_RADIUS
var crank_radius := CoreLoopKnobs.CRANK_NOISE_RADIUS
var sprint_radius := CoreLoopKnobs.SPRINT_NOISE_RADIUS
var thrust_radius := CoreLoopKnobs.THRUST_NOISE_RADIUS

var _suit: CoreLoopSuit
var _beam: CoreLoopDrillBeam
var _power: CoreLoopPowerSystem

var _elapsed := 0.0

## The loudest thing heard during the tick being accumulated, and what it was.
## Held across frames so a source that is only active for part of a tick still
## gets reported at its own loudness.
var _pending_radius := 0.0
var _pending_source := ""

## The last event actually emitted, for the HUD.
var _last_position := Vector3.ZERO
var _last_radius := 0.0
var _last_source := "silence"


func _physics_process(delta: float) -> void:
	if _suit == null:
		return

	var loudest := _loudest_now()
	if loudest["radius"] > _pending_radius:
		_pending_radius = loudest["radius"]
		_pending_source = loudest["source"]

	_elapsed += delta
	if _elapsed < CoreLoopKnobs.NOISE_TICK_INTERVAL:
		return
	_elapsed = 0.0

	if _pending_radius <= 0.0:
		_last_source = "silence"
		_last_radius = 0.0
		return

	_last_position = _suit.global_position
	_last_radius = _pending_radius
	_last_source = _pending_source
	_pending_radius = 0.0
	_pending_source = ""
	noise_made.emit(_last_position, _last_radius)


func bind(suit: CoreLoopSuit, beam: CoreLoopDrillBeam, power: CoreLoopPowerSystem) -> void:
	_suit = suit
	_beam = beam
	_power = power


## What the HUD prints: the source and radius of the last tick, so a playtester
## can see that flying is quiet and drilling is not.
func describe() -> String:
	if _last_radius <= 0.0:
		return "silent"
	return "%s (%.0f m)" % [_last_source, _last_radius]


func get_last_position() -> Vector3:
	return _last_position


func get_last_radius() -> float:
	return _last_radius


## The loudest source active this frame.
##
## Ordered loudest first and returned on the first hit, so the comparison chain
## below is the priority. Drilling and cranking are equal and both drown
## everything else, which is the shape of the whole loop: the two things worth
## doing are the two things that fetch the creature.
func _loudest_now() -> Dictionary:
	if _beam != null and _beam.is_firing():
		return {"radius": drill_radius, "source": "drill"}
	if _power != null and _power.is_cranking():
		return {"radius": crank_radius, "source": "crank"}
	if _suit.sprint_engaged and _is_thrusting():
		return {"radius": sprint_radius, "source": "sprint"}
	if _is_thrusting() or _suit.stabilizers_engaged:
		return {"radius": thrust_radius, "source": "thrusters"}
	return {"radius": 0.0, "source": ""}


## Whether the player is commanding thrust, as against drifting.
##
## Sprinting with no stick input is silent on purpose: sprint only raises the
## speed ceiling, so holding it while coasting spends nothing and should announce
## nothing.
func _is_thrusting() -> bool:
	var stick := Vector3(
		Input.get_axis("thrust_left", "thrust_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_forward", "thrust_back")
	)
	return stick.length() > THRUST_DEADZONE
