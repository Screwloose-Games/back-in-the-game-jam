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
## How many times the goal was commanded, and how many of those were a change of holder.
##
## NOT DERIVABLE FROM OUTSIDE, which is the only reason a debug counter lives in gameplay
## code. A BtSequence can tick two actions in one frame and a selector can fall through from
## one goal-setting leaf to another inside a single tick -- `BtChaseTarget` returns FAILURE
## on arrival WITHOUT releasing (see its docstring), and whatever runs next requests the same
## point in its own name. Both `request` calls land between any two samples an external
## poller could take, and `holder()` shows only the last winner. `route_changed` undercounts
## them too, because `set_goal` coalesces the pair into one replan.
##
## Never reset here. Whoever reads them owns the windowing.
var commands: int = 0
var owner_flips: int = 0

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
	if _has_goal and _owner != owner:
		owner_flips += 1
	commands += 1
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


## The route reaches as far as it can and stops short. NOT a failure -- it is the alien
## discovering the gap is too tight for it, which is the whole of Invariant 5 seen from the
## inside, and the far end of the route is where it waits.
##
## `NavRoute` has no `is_partial()` of its own; the status is the test.
func is_partial() -> bool:
	if navigation == null or navigation.route == null:
		return false
	return navigation.route.status == NavRoute.Status.PARTIAL


func _refresh_distance() -> float:
	if config == null:
		return BehaviorConfig.MINIMUM_GOAL_REFRESH_M
	return maxf(config.goal_refresh_m, BehaviorConfig.MINIMUM_GOAL_REFRESH_M)


func _arrive_distance() -> float:
	return config.arrive_distance if config != null else 3.0
