class_name CreatureAwarenessBehaviour
extends Node

## The behaviour layer, which is the one thing none of the three creature modules ships.
##
## THIS FILE IS THE POINT OF THE PROTOTYPE. Navigation, perception and suspicion are each
## complete and each has its own sandbox, and until now they had never been in one scene:
## nothing anywhere connected a suspicion hotspot to `CreatureNavigation.set_goal`. That gap
## is deliberate on both sides. Navigation's README calls the goal-choosing layer
## "deliberately not stubbed into something that appears to work", and suspicion's says
## "Behavior reads and then acts on its own thresholds -- Suspicion transitions nothing".
## What follows is those thresholds, and nothing else.
##
## SHAPED TO behavior.md SECTIONS 24-25 rather than invented, so it is a stepping stone
## toward the real HFSM instead of a throwaway:
##
##     UNALERTED (section 24)              INVESTIGATING (section 25)
##       choose nest, travel, idle           strongest hotspot still unresolved?
##       "moves between nesting areas          go to its best unresolved location
##        rather than following an            arrived? inspect/search
##        obvious patrol route"               resolved, or nothing left? finish
##
## IT DOES NOT TOUCH BELIEF, AND MUST NOT. Suspicion has exactly three doors -- evidence,
## disconfirmation, and the clock -- and there is no `mark_investigated` among them by
## design. The alien resolves a hotspot by going there and LOOKING, which makes perception
## emit a disconfirmation, which suppresses the belief. Behaviour makes the creature
## investigate; perception observes the result. Anything here that reached in and lowered a
## number would work visibly better and destroy the whole design.
##
## FOUR THINGS THAT WILL COST AN AFTERNOON IF YOU CHANGE THEM:
##
##   1  `get_best_unresolved_location(id)` returns Vector3.ZERO for an id that is no longer
##      live -- NOT the hotspot centre, whatever its docstring says. Unguarded, an alien
##      whose hotspot resolves mid-approach sets off for the world origin.
##   2  There is no `goal_reached` signal on CreatureNavigation. Arrival is the follower's
##      `is_finished`, with a distance fallback for a route that never attaches.
##   3  The scan AABB must enclose a real volume. A degenerate one aborts the scan, and an
##      aborted scan reports a ZERO-strength disconfirmation, which suppresses nothing --
##      so the alien searches, the hotspot never clears, and it looks like disconfirmation
##      is broken when it is the region that is.
##   4  A PARTIAL route still finishes. The alien reaches the far end of what it could
##      reach -- the mouth of the player-only shaft, say -- and searches from there, which
##      correctly fails to resolve a hotspot on the other side. The timeout is what stops
##      it standing there forever.

enum State { IDLE, WANDER, INVESTIGATE, SEARCH }

@export var navigation: CreatureNavigation = null
@export var perception: CreaturePerception = null
@export var suspicion: CreatureSuspicion = null
@export var creature: CreatureAwarenessCreature = null
@export var settings: CreatureAwarenessSettings = null

## Fed from the delta this node is handed, like every clock in the three modules. Never a
## wall clock: `Time.get_ticks_msec()` ignores `get_tree().paused` and `Engine.time_scale`.
var clock: float = 0.0

var _state: State = State.IDLE
var _nests := PackedVector3Array()
var _nest_visited: PackedFloat32Array = PackedFloat32Array()
var _nest_index: int = -1
var _goal: Vector3 = Vector3.ZERO
var _hotspot_id: int = -1
var _state_since: float = 0.0
var _dwell_until: float = 0.0
var _scanning: bool = false


static func state_name(value: State) -> String:
	match value:
		State.IDLE:
			return "idle"
		State.WANDER:
			return "wander"
		State.INVESTIGATE:
			return "investigate"
		State.SEARCH:
			return "search"
	return "?"


func _ready() -> void:
	_nests = CreatureAwarenessMap.nests()
	_nest_visited.resize(_nests.size())
	_nest_visited.fill(-CreatureAwarenessKnobs.NEST_RECENT_PENALTY)
	if perception != null:
		perception.activity_scan_finished.connect(_on_scan_finished)
	if suspicion != null:
		suspicion.hotspot_resolved.connect(_on_hotspot_resolved)


func state() -> State:
	return _state


func current_hotspot_id() -> int:
	return _hotspot_id


func goal() -> Vector3:
	return _goal


## Driven from the prototype rather than `_physics_process`, so the whole tick order --
## perception, suspicion, then behaviour, then navigation -- is written down in one place
## and cannot be reordered by node ordering in the scene tree.
func advance(delta: float) -> void:
	clock += delta
	if navigation == null or suspicion == null:
		return

	if _state != State.INVESTIGATE and _state != State.SEARCH:
		var lead: SuspicionHotspot = _lead()
		if lead != null:
			_begin_investigation(lead)

	match _state:
		State.IDLE:
			_tick_idle()
		State.WANDER:
			_tick_wander()
		State.INVESTIGATE:
			_tick_investigate()
		State.SEARCH:
			_tick_search()

	if creature != null:
		creature.status_line = _status()


## The strongest hotspot the prototype's own threshold says is worth leaving a nest for.
##
## Suspicion offers no such number and should not: it describes belief. `get_hotspots_above`
## already sorts descending, so the first entry is the lead.
func _lead() -> SuspicionHotspot:
	var above: Array[SuspicionHotspot] = suspicion.get_hotspots_above(_threshold())
	if above.is_empty():
		return null
	return above[0]


func _begin_investigation(hotspot: SuspicionHotspot) -> void:
	_hotspot_id = hotspot.id
	_enter(State.INVESTIGATE)
	_aim_at_hotspot()


## Points the alien at wherever inside the hotspot is still unexplained.
##
## Re-asked rather than remembered: the best unresolved location MOVES as the alien searches
## parts of a hotspot, which is section 12's whole "suspicion can be spatially resolved"
## behaviour. Holding the first answer would send it back to a spot it had already cleared.
func _aim_at_hotspot() -> bool:
	var hotspot: SuspicionHotspot = suspicion.get_hotspot(_hotspot_id)
	if hotspot == null:
		_abandon()
		return false
	var target: Vector3 = suspicion.get_best_unresolved_location(_hotspot_id)
	if target.is_zero_approx():
		# Footgun 1. A live hotspot never reports the origin as its best unresolved point in
		# this cave, so this is the "id went stale between the two calls" case.
		_abandon()
		return false
	_goal = target
	navigation.set_goal(_goal)
	return true


func _tick_investigate() -> void:
	if clock - _state_since > CreatureAwarenessKnobs.INVESTIGATE_TIMEOUT:
		_abandon()
		return
	if suspicion.get_hotspot(_hotspot_id) == null:
		_abandon()
		return
	if _arrived():
		_begin_search()


## Asks perception to look, and then stays out of the way.
##
## THE ALIEN DOES NOT DECIDE WHAT IT FINDS. A scan that turns up nothing emits a
## disconfirmation on its own, which suppresses the belief and eventually drops the hotspot;
## a scan that finds something emits evidence instead and suspicion goes UP. Both outcomes
## arrive through `activity_scan_finished`, and neither is this file's to choose.
func _begin_search() -> void:
	_enter(State.SEARCH)
	if perception == null:
		_abandon()
		return
	var half: float = maxf(_search_half_extent(), 0.5)
	var region := AABB(_goal - Vector3.ONE * half, Vector3.ONE * half * 2.0)
	_scanning = true
	perception.request_activity_scan(region, _thoroughness())


func _tick_search() -> void:
	# The scan drives itself from perception.advance; all this has to do is not wander off,
	# and not wait forever if a config flag aborted it.
	if _scanning and clock - _state_since <= CreatureAwarenessKnobs.INVESTIGATE_TIMEOUT:
		return
	_scanning = false
	if suspicion.get_hotspot(_hotspot_id) != null and _lead() != null:
		# Still believes something is here. Re-ask where, because searching moved the answer.
		_enter(State.INVESTIGATE)
		_aim_at_hotspot()
		return
	_abandon()


func _on_scan_finished(_found_evidence: bool) -> void:
	_scanning = false


func _on_hotspot_resolved(hotspot_id: int) -> void:
	if hotspot_id == _hotspot_id:
		_abandon()


func _abandon() -> void:
	_hotspot_id = -1
	_scanning = false
	navigation.clear_goal()
	_enter(State.IDLE)
	_dwell_until = clock


func _tick_idle() -> void:
	if not _wander_enabled() or _nests.is_empty():
		return
	if clock < _dwell_until:
		return
	_nest_index = _choose_nest()
	if _nest_index < 0:
		return
	_goal = _nests[_nest_index]
	navigation.set_goal(_goal)
	_enter(State.WANDER)


func _tick_wander() -> void:
	if not _wander_enabled():
		navigation.clear_goal()
		_enter(State.IDLE)
		return
	if clock - _state_since > CreatureAwarenessKnobs.INVESTIGATE_TIMEOUT:
		# A nest it cannot currently route to should not strand it; pick another.
		_arrive_at_nest()
		return
	if _arrived():
		_arrive_at_nest()


func _arrive_at_nest() -> void:
	if _nest_index >= 0 and _nest_index < _nest_visited.size():
		_nest_visited[_nest_index] = clock
	navigation.clear_goal()
	_enter(State.IDLE)
	_dwell_until = clock + _dwell()


## Least recently visited, excluding the one it is standing on.
##
## Deterministic on purpose. Section 24 asks for "not an obvious patrol route", and with
## three chambers any weighted-random rule is indistinguishable from this one over a short
## watch -- while this one cannot produce the degenerate run of picking the same nest twice
## that makes the wander look broken.
func _choose_nest() -> int:
	var best: int = -1
	var oldest: float = INF
	for index: int in range(_nests.size()):
		if index == _nest_index:
			continue
		if _nest_visited[index] < oldest:
			oldest = _nest_visited[index]
			best = index
	return best


## Arrival, with a fallback because there is no signal for it.
##
## `is_finished` is the real answer and covers a PARTIAL route correctly -- it finishes at
## the far end of whatever the alien could actually reach. The distance test is for the case
## where no route attached at all, so the follower has nothing to be finished with.
func _arrived() -> bool:
	if creature == null:
		return false
	var at: Vector3 = creature.global_position
	if navigation.route != null and navigation.follower.is_finished(at):
		return true
	return at.distance_to(_goal) <= CreatureAwarenessKnobs.ARRIVE_DISTANCE


func _enter(value: State) -> void:
	_state = value
	_state_since = clock


func _status() -> String:
	match _state:
		State.INVESTIGATE:
			var hotspot: SuspicionHotspot = suspicion.get_hotspot(_hotspot_id)
			if hotspot != null:
				return "INVESTIGATE %.2f" % hotspot.suspicion
			return "INVESTIGATE"
		State.SEARCH:
			return "SEARCH"
		State.WANDER:
			return "wander -> nest %d" % (_nest_index + 1)
	return "idle"


func _threshold() -> float:
	if settings == null:
		return CreatureAwarenessKnobs.INVESTIGATE_THRESHOLD
	return settings.investigate_threshold


func _search_half_extent() -> float:
	if settings == null:
		return CreatureAwarenessKnobs.SEARCH_HALF_EXTENT
	return settings.search_half_extent


func _thoroughness() -> float:
	if settings == null:
		return CreatureAwarenessKnobs.SEARCH_THOROUGHNESS
	return settings.search_thoroughness


func _dwell() -> float:
	if settings == null:
		return CreatureAwarenessKnobs.NEST_DWELL
	return settings.nest_dwell


func _wander_enabled() -> bool:
	if settings == null:
		return true
	return settings.wander_enabled
