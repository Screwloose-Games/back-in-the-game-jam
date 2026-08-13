class_name NavProgressMonitor
extends RefCounted

## Notices that the body is not going anywhere (navigation.md section 40).
##
## THE BACKSTOP FOR THE FAILURES NOBODY HAS THOUGHT OF YET. Section 40 enumerates six local
## failures and each has its own detector -- a crevice that grinds, a surface that is not
## there, a leap invalidated on the launch tick. Between them they have twice shipped an
## alien that held a COMPLETE route, reported a plausible mode, and did not move again for
## the rest of the run: once wedged against a ceiling inside its own planning envelope, once
## floating in open space with every ray missing. Both were invisible to every layer of the
## system, because "covered no ground" was not a thing anything measured.
##
## Each of those had a specific cause and each now has a specific fix. This exists because
## the third one will not, and an alien that recovers badly is enormously better than an
## alien that stops forever -- a replan and a mode reset cost nothing, and the section 30
## inspection request routes through `NavInspector.report`, which already deduplicates.
##
## MEASURED OVER A WINDOW, NOT PER TICK, for the reason `WiggleController.note_progress`
## is: the slowest legitimate mode covers 1.2 m/s, so a single tick of small displacement
## is what success looks like. That controller keeps its own copy rather than calling this
## one, because section 40.2's grind is a statement about a specific EDGE and reports
## differently; the shapes being similar is not a reason to make one class answer two
## questions.
##
## DELIBERATE STOPS ARE EXCLUDED, NOT WAITED OUT. Section 29 has the alien stop, orient and
## look for as long as an inspection takes, and section 43's Scenario B has it hold still
## while it compresses. A watchdog that had to be tuned longer than every legitimate pause
## would eventually be tuned longer than the failures too.

## Metres from where the window started, or 0 when not tracking.
var moved: float = 0.0
## How many times this has tripped since the last reset, for the panel and the HUD. A
## number that climbs slowly is an alien having a hard time; one that climbs every two
## seconds is a bug this class is papering over.
var trips: int = 0

var _origin: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _tracking: bool = false


## True on the tick the body is judged wedged, which also restarts the window -- so a body
## that stays stuck reports again one window later rather than every tick after the first.
##
## `moving_deliberately` is false when something above has chosen stillness on purpose.
func note(at: Vector3, delta: float, moving_deliberately: bool, config: NavigationConfig) -> bool:
	if not moving_deliberately:
		# Not "pause the clock" but "forget the window". A body held still for an inspection
		# has not been failing to make progress; it has not been trying, and the seconds it
		# spent looking must not be banked against the seconds after it starts again.
		reset()
		return false
	if not _tracking:
		_tracking = true
		_origin = at
		_elapsed = 0.0
		moved = 0.0
		return false
	_elapsed += delta
	moved = _origin.distance_to(at)
	if _elapsed < config.progress_window:
		return false
	var wedged: bool = moved < config.progress_threshold
	_origin = at
	_elapsed = 0.0
	if wedged:
		trips += 1
	return wedged


## Forgets the window. Called whenever the situation changes enough that the seconds
## already spent say nothing about the seconds to come -- a replan, a new route, a
## deliberate hold.
func reset() -> void:
	_tracking = false
	_elapsed = 0.0
	moved = 0.0


func debug_state() -> Dictionary:
	return {
		"tracking": _tracking,
		"elapsed": _elapsed,
		"moved": moved,
		"trips": trips,
	}
