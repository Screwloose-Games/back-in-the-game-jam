class_name ClingerStuck
extends RefCounted

## NOTICES THAT A CRAWL IS GETTING NOWHERE, and it exists because of one 1.2 x 2.6 m box.
## A clinger that wanders onto a surface too small to navigate believes it is on a wall, and
## on a face that small `Clinger._step` runs off an edge every few frames, turns
## EDGE_TURN_DEGREES, and spends the rest of the run walking a square.
##
## TWO SIGNALS, EITHER ONE ENOUGH, because they fail in opposite directions. Turn churn
## catches the thrash -- a body pinned in a fold turns constantly and can cover ground doing
## it, which a displacement watchdog reads as healthy. No-progress catches the tidy circle,
## and does it twice: `moved` catches the body that has all but stopped, `wander` catches the
## one walking a clean loop, which `moved` alone never sees.
##
## Pure. No node, no tree, no physics, the rule the rest of `systems/clinger/` keeps.

## Below this the body has all but stopped and `wander` is noise over a tiny divisor.
## CreatureDebugReadout.WANDER_FLOOR_M's figure, for the same reason.
const WANDER_FLOOR := 0.05

## Guards the two divisions. Never a tunable: it exists so a zero window reports rather than
## returning INF, not so anybody can choose how long a window is.
const MIN_WINDOW := 0.0001

var window := 3.0
var windows_needed := 2
var progress_metres := 0.5
var wander_limit := 4.0
var turn_rate_limit := 2.0

var moved := 0.0
var wander := 1.0
var turn_rate := 0.0
var streak := 0
var trips := 0

var _origin := Vector3.ZERO
var _last := Vector3.ZERO
var _heading := Vector3.ZERO
var _path := 0.0
var _turned := 0.0
var _elapsed := 0.0
var _tracking := false


## True on the tick the crawl is judged stuck, which also restarts the window -- so a body
## that stays stuck reports again `windows_needed` windows later rather than every tick.
##
## IT TAKES CONSECUTIVE WINDOWS, AND THAT IS WHAT MAKES IT RARE. One window of churn is
## ordinary: a body rounding a corner between two walls sees its goal jump into a new
## tangent plane and turns hard once. Measured against a shed clinger circling a player in a
## sixteen-metre room, that transient alone was enough to send it across the room and end
## the encounter. Sustained across two windows it is not cornering, it is stuck.
func note(at: Vector3, heading: Vector3, delta: float) -> bool:
	if not _tracking:
		_restart(at, heading)
		return false
	_path += _last.distance_to(at)
	_last = at
	# Unsigned, and that is not laziness. A signed turn is only meaningful about a fixed
	# axis, and `Clinger._step` rewrites `_up` from the seat normal on every successful step
	# -- so a body rounding corners constantly, which is the case this exists to catch, has
	# no stable axis to measure against. Unsigned churn subsumes reversals anyway.
	if not heading.is_zero_approx() and not _heading.is_zero_approx():
		_turned += _heading.angle_to(heading)
		_heading = heading
	_elapsed += maxf(delta, 0.0)
	if _elapsed < maxf(window, MIN_WINDOW):
		return false
	moved = _origin.distance_to(at)
	wander = _path / maxf(moved, WANDER_FLOOR)
	turn_rate = _turned / maxf(_elapsed, MIN_WINDOW)
	var failing := moved < progress_metres or wander > wander_limit or turn_rate > turn_rate_limit
	streak = streak + 1 if failing else 0
	_restart(at, heading)
	if streak < maxi(windows_needed, 1):
		return false
	streak = 0
	trips += 1
	return true


## Forgets the window outright, rather than pausing the clock. A body held still while it
## re-grips, or one that has just landed somewhere new, has not been failing to make
## progress -- it has not been trying, and those seconds must not be banked against the ones
## after it starts again. NavProgressMonitor.reset()'s reasoning, and the same trap.
func reset() -> void:
	_tracking = false
	streak = 0
	_elapsed = 0.0
	_path = 0.0
	_turned = 0.0


func debug_state() -> Dictionary:
	return {
		"tracking": _tracking,
		"elapsed": _elapsed,
		"moved": moved,
		"wander": wander,
		"turn_rate": turn_rate,
		"streak": streak,
		"trips": trips,
	}


func _restart(at: Vector3, heading: Vector3) -> void:
	_tracking = true
	_origin = at
	_last = at
	_heading = heading
	_path = 0.0
	_turned = 0.0
	_elapsed = 0.0
