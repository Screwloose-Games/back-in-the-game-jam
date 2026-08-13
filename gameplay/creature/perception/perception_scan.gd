class_name PerceptionScan
extends RefCounted

## One deliberate look at a region, spread over time (perception.md sections 18-19,
## 23). Serves both the activity scan Behavior requests and the geometry scan
## Navigation requests.
##
## Pure timing and bookkeeping -- it never touches the probe, never builds an
## observation, and never emits anything. advance() returns a SAMPLE BUDGET and the
## facade decides what a sample means. That is what keeps the whole state machine
## testable with no scene, no physics and no clock.
##
## Spreading the budget across the duration also stops a thorough scan from landing
## 256 shape queries in one frame, which on the GL Compatibility target is a visible
## hitch rather than a profiler curiosity.

## IDLE     never started, or cancelled.
## RUNNING  in progress.
## FINISHED latched: the scan ended and nobody has started another one yet.
enum State { IDLE, RUNNING, FINISHED }

var state: State = State.IDLE
var region: AABB = AABB()
var thoroughness: float = 0.0
## Caller's tag, passed through untouched. Geometry scans put a
## CreatureGeometryPerception.GeometryScanReason here; activity scans leave it 0.
var reason: int = 0
var duration: float = 0.0
var elapsed: float = 0.0
var samples_total: int = 0
var samples_done: int = 0
## Set by the facade when a sample produced evidence. Decides which of the two
## mutually exclusive outcomes the scan ends with.
var found_any: bool = false
## True when the scan reached FINISHED without ever looking -- see
## finish_immediately(). A caller must not report an aborted scan as a thorough
## examination that found nothing.
var aborted: bool = false

var _just_finished: bool = false


## Start, or RESTART. A re-request while running replaces the scan in progress
## rather than queueing behind it: Behavior re-issues a search as it moves, and a
## queue would build a backlog nobody ever drains.
func begin(
	p_region: AABB, p_thoroughness: float, p_duration: float, p_samples: int, p_reason: int = 0
) -> void:
	region = p_region
	thoroughness = clampf(p_thoroughness, 0.0, 1.0)
	duration = maxf(p_duration, 0.0)
	reason = p_reason
	samples_total = maxi(p_samples, 1)
	samples_done = 0
	elapsed = 0.0
	found_any = false
	aborted = false
	_just_finished = false
	state = State.RUNNING


## Advance the clock and return how many samples are DUE this tick.
##
## Returning a budget rather than doing the work is the whole design. The scan stays
## free of the probe, and the facade -- which owns the probe and the senses -- spends
## the budget however that scan type wants.
func advance(delta: float) -> int:
	_just_finished = false
	if state != State.RUNNING:
		return 0

	elapsed += maxf(delta, 0.0)
	# A zero-duration scan is legitimate: an instant look. It completes on its first
	# advance() with its whole budget spent, rather than dividing by zero.
	var progressed: float = 1.0 if duration <= 0.0 else clampf(elapsed / duration, 0.0, 1.0)
	var target: int = int(ceilf(float(samples_total) * progressed))
	var due: int = maxi(0, mini(target, samples_total) - samples_done)
	samples_done += due

	if progressed >= 1.0:
		state = State.FINISHED
		_just_finished = true
	return due


## Finish immediately, spending nothing.
##
## THE ESCAPE HATCH THAT STOPS BEHAVIOR HANGING FOREVER. A scan requested while its
## sense is disabled, or with an unbound probe, or over a degenerate region, must
## still reach FINISHED -- otherwise `request -> poll until complete` never returns
## and the creature stands still because of a config flag, silently.
##
## It sets `aborted`, and the caller MUST honour it. An aborted scan that reported a
## normal disconfirmation would tell Suspicion "I thoroughly checked and found
## nothing" about a region nothing ever looked at, clearing a hotspot that was
## perfectly real. Hanging is the obvious bug here; this is the quiet one.
func finish_immediately() -> void:
	samples_done = 0
	elapsed = duration
	aborted = true
	state = State.FINISHED
	_just_finished = true


func cancel() -> void:
	state = State.IDLE
	_just_finished = false
	samples_done = 0
	elapsed = 0.0


func is_active() -> bool:
	return state == State.RUNNING


## True only in FINISHED, and latched until the next begin() or cancel().
##
## DELIBERATELY FALSE IN IDLE. Behavior's loop is `request, then poll until
## complete`. If IDLE reported complete, a request that never started would look
## finished the instant it was made -- and worse, the previous scan's completion
## would be read by the next caller.
func is_complete() -> bool:
	return state == State.FINISHED


## True for exactly the one advance() call that ended the scan, so the facade can
## emit its outcome once rather than every tick afterwards.
func just_finished() -> bool:
	return _just_finished


func progress() -> float:
	if state == State.FINISHED:
		return 1.0
	if state == State.IDLE or duration <= 0.0:
		return 0.0
	return clampf(elapsed / duration, 0.0, 1.0)


func note_positive() -> void:
	found_any = true


## Where sample `index` should look, as a deterministic point inside the region.
##
## A low-discrepancy walk rather than random sampling: it covers the volume evenly
## at any budget, and two runs of the same scan look in the same places -- which is
## what makes a scan's result reproducible in a test.
func sample_point(index: int) -> Vector3:
	if samples_total <= 0:
		return region.get_center()
	var t: float = (float(index) + 0.5) / float(samples_total)
	return (
		region.position
		+ Vector3(
			region.size.x * fposmod(t * 0.7548776662, 1.0),
			region.size.y * fposmod(t * 0.5698402909, 1.0),
			region.size.z * fposmod(t * 0.8191725134, 1.0)
		)
	)
