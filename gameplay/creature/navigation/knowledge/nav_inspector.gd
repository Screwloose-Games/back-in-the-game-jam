class_name NavInspector
extends RefCounted

## Section 29's chain: notice, stop, look, learn, replan.
##
## THE DELAY IS THE FEATURE. Section 29 is unusually explicit about it -- the alien "should
## not instantly consume authoritative navigation information and continue moving", and
## the pause exists so the animation and behaviour systems have somewhere to put stopping,
## orienting, probing with tentacles and cautiously entering. An inspection that resolved
## in one frame would be correct, would pass every test written against knowledge, and
## would look exactly like omniscience.
##
## KNOWLEDGE IS APPLIED AT THE END OF `RELEARNING`, NOT ON ENTRY TO IT. That single
## ordering choice is the whole of section 41's "delayed knowledge acquisition", and it is
## what Scenario J asserts: part-way through an inspection the believed graph must still be
## byte-identical to what it was before.
##
## DEDUPE IS NOT AN OPTIMISATION, IT IS A BUG FIX. Before this class existed,
## `CreatureNavigation._replan` raised an inspection request on every non-COMPLETE route
## -- twice a second, forever, at the same spot, for a goal that was simply unreachable.
## Anything listening would have been asked to investigate the same wall until the level
## ended.
##
## `inspection_timeout` IS LOAD-BEARING. Section 30 hands the inspection to the behaviour
## system, which decides what it looks like and calls back when it is done. Every project
## today has no behaviour system, so without a timeout the alien wedges in INSPECTING and
## never moves again.

enum State {
	## Nothing to investigate. The overwhelmingly common case.
	MOVING,
	## Something was noticed. The body stops here.
	GEOMETRY_MISMATCH,
	## Section 30's request is outstanding, and behaviour owns what it looks like.
	INSPECTING,
	## Behaviour is finished. Knowledge is applied at the END of this beat.
	RELEARNING,
	## One tick, so the facade replans against what was just learned.
	REPLANNING,
}

var _state: State = State.MOVING
var _pending: NavInspectionRequest = null
var _elapsed: float = 0.0
var _relearn_ready: bool = false
var _last_at: Vector3 = Vector3.ZERO
var _last_time: float = 0.0
var _has_last: bool = false


## Section 30. Returns whether the request was accepted -- false means deduped or busy,
## both of which are normal and neither of which is an error.
func report(request: NavInspectionRequest, now: float, config: NavigationConfig) -> bool:
	if request == null or _state != State.MOVING:
		return false
	if _is_duplicate(request.position, now, config):
		return false
	_pending = request
	_state = State.GEOMETRY_MISMATCH
	_elapsed = 0.0
	_last_at = request.position
	_last_time = now
	_has_last = true
	return true


## One tick of the chain. Returns the state after advancing.
func advance(delta: float, config: NavigationConfig) -> State:
	_relearn_ready = false
	if _state == State.MOVING:
		return _state
	_elapsed += delta
	match _state:
		State.GEOMETRY_MISMATCH:
			if _elapsed >= config.mismatch_pause_time:
				_enter(State.INSPECTING)
		State.INSPECTING:
			# The backstop, not the normal path. Behaviour calling complete() is.
			if _elapsed >= config.inspection_timeout:
				_enter(State.RELEARNING)
		State.RELEARNING:
			if _elapsed >= config.relearn_time:
				# THE ONE TICK ON WHICH KNOWLEDGE MAY BE APPLIED.
				_relearn_ready = true
				_enter(State.REPLANNING)
		State.REPLANNING:
			_enter(State.MOVING)
			_pending = null
	return _state


## Section 30: "when inspection completes, it informs the knowledge system which nearby
## world-navigation data may now be learned". Called by BEHAVIOUR, not by navigation.
func complete() -> void:
	if _state != State.INSPECTING:
		return
	_enter(State.RELEARNING)


## True on the single tick where `learn_connected_region` should be called. Read once per
## tick by the facade; nothing else should act on it.
func is_relearn_ready() -> bool:
	return _relearn_ready


func is_busy() -> bool:
	return _state != State.MOVING


## Section 29: the alien stops rather than absorbing new terrain mid-stride.
func should_hold_still() -> bool:
	return (
		_state == State.GEOMETRY_MISMATCH
		or _state == State.INSPECTING
		or _state == State.RELEARNING
	)


func state() -> State:
	return _state


func pending() -> NavInspectionRequest:
	return _pending


## Where the completed inspection licenses knowledge to be updated.
func relearn_at() -> Vector3:
	return _pending.position if _pending != null else _last_at


static func state_name(value: State) -> String:
	match value:
		State.MOVING:
			return "moving"
		State.GEOMETRY_MISMATCH:
			return "geometry_mismatch"
		State.INSPECTING:
			return "inspecting"
		State.RELEARNING:
			return "relearning"
		State.REPLANNING:
			return "replanning"
	return "unknown"


func debug_state() -> Dictionary:
	var reason: String = "-"
	if _pending != null:
		reason = NavInspectionRequest.reason_name(_pending.reason)
	return {"state": state_name(_state), "elapsed": _elapsed, "reason": reason}


# ----- internals -----


func _enter(next: State) -> void:
	_state = next
	_elapsed = 0.0


func _is_duplicate(at: Vector3, now: float, config: NavigationConfig) -> bool:
	if not _has_last:
		return false
	if now - _last_time > config.inspection_dedupe_time:
		return false
	return at.distance_to(_last_at) <= config.inspection_dedupe_radius
