class_name BehaviorGoal
extends RefCounted

## The one place Behavior commands Navigation, arbitrated by which node asked.
##
## WHY THIS EXISTS AT ALL. fsm.md wants the outgoing RUNNING leaf aborted "before any new
## leaf ticks", and every action that calls `set_goal` to call `clear_goal` in `abort`. Both
## cannot hold: a reactive tree does not know which leaf will run until it has ticked, so
## the abort necessarily happens afterwards -- and then the outgoing leaf's clear wipes the
## incoming leaf's freshly-set goal. The alien stops moving, holding a route to nowhere,
## with nothing in the log.
##
## `release` is therefore a no-op unless the caller still holds the goal. Ordering stops
## mattering, and fsm.md's rule stays literally true in the action code. A BtSequence can
## also tick two actions in one frame, so two owners can contend inside a single tick; the
## token handles that for free.
##
## IT IS ALSO THE ONLY RECORD OF WHAT WAS COMMITTED. `CreatureNavigation._has_goal` is
## private and there is no public `has_goal()`, so nothing else can answer "did anyone ask
## for anything, and where".
##
## And it owns the re-issue deadband, deliberately in one place rather than in each action:
## `set_goal` nulls the route and resets navigation's stuck watchdog, so an action
## re-issuing every frame disables the watchdog every frame. A new action cannot forget a
## rule it never has to write.

var navigation: CreatureNavigation = null
var config: BehaviorConfig = null

var _owner: BtNode = null
var _committed: Vector3 = Vector3.ZERO
var _has_goal: bool = false


func _init(p_navigation: CreatureNavigation = null, p_config: BehaviorConfig = null) -> void:
	navigation = p_navigation
	config = p_config


## Commands `at`, unless the same owner already asked for somewhere near enough.
##
## A change of owner always re-issues, however small the move: the new owner wants the goal
## in its own name, and the deadband is about route thrash rather than about ownership.
func request(owner: BtNode, at: Vector3) -> void:
	if _has_goal and _owner == owner and _committed.distance_to(at) <= _refresh_distance():
		return
	_owner = owner
	_committed = at
	_has_goal = true
	if navigation != null:
		navigation.set_goal(at)


## Gives the goal back. Does nothing unless `owner` is still holding it, which is the whole
## mechanism -- see the class docstring.
func release(owner: BtNode) -> void:
	if _owner != owner:
		return
	clear()


## Drops the goal whoever holds it. For state exits and teardown, where the HFSM has stopped
## caring about whatever the tree was doing.
func clear() -> void:
	_owner = null
	_committed = Vector3.ZERO
	_has_goal = false
	if navigation != null:
		navigation.clear_goal()


func holder() -> BtNode:
	return _owner


func committed() -> Vector3:
	return _committed


func has_goal() -> bool:
	return _has_goal


## Arrival, with a fallback because there is no signal for it.
##
## `is_finished` is the real answer and covers a PARTIAL route correctly -- it finishes at
## the far end of whatever the alien could actually reach. The distance test is for the case
## where no route attached at all, so the follower has nothing to be finished with.
func is_arrived(at: Vector3) -> bool:
	if not _has_goal:
		return false
	if navigation != null and navigation.route != null and navigation.follower != null:
		if navigation.follower.is_finished(at):
			return true
	return at.distance_to(_committed) <= _arrive_distance()


## Whether the route planner has concluded there is no way there at all. PARTIAL is not
## failure: the alien reaches the far end of what it could reach and acts from there.
func is_unreachable() -> bool:
	if navigation == null or navigation.route == null:
		return false
	return navigation.route.status == NavRoute.Status.UNREACHABLE


func _refresh_distance() -> float:
	if config == null:
		return BehaviorConfig.MINIMUM_GOAL_REFRESH_M
	return maxf(config.goal_refresh_m, BehaviorConfig.MINIMUM_GOAL_REFRESH_M)


func _arrive_distance() -> float:
	return config.arrive_distance if config != null else 3.0
