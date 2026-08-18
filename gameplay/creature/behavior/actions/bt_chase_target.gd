class_name BtChaseTarget
extends BtAction

## Runs at the best current estimate of where the target is. RUNNING while it closes.
##
## RE-ISSUES THE GOAL EVERY TICK, ON PURPOSE. fsm.md asks chase to re-issue "only when the
## estimate has moved more than `goal_refresh_m`", and that deadband exists -- inside
## BehaviorGoal, where every action gets it for free and none of them can forget it. A second
## copy here would be a second place for the one rule that stops `set_goal` nulling the route
## and resetting navigation's stuck watchdog every frame.
##
## A ROUTE THAT STOPS SHORT IS NOT THIS NODE'S PROBLEM. `is_unreachable` is UNREACHABLE only;
## a PARTIAL route is handled a whole branch up by `target_beyond_reach`, because a creature
## that discovers the gap mid-chase should go and wait at the mouth rather than fail here and
## be asked again next tick.
##
## FAILURE ON ARRIVAL, WHICH IS THE ONE SURPRISING LINE. fsm.md's table gives chase no SUCCESS
## terminator at all, and the reason shows up the moment you write one: a selector stops at
## its first non-FAILURE child, so succeeding here would swallow the tick and the search
## branch below would never run. Arriving at the estimate and finding nobody is precisely the
## case behavior.md section 28 hands to a sweep of the last credible region. The goal is left
## committed rather than released -- the alien is standing on it, navigation has nothing left
## to do with it, and releasing then re-requesting it every tick is the route thrash the
## deadband exists to prevent.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	super(&"chase_target")
	memory = p_memory


func abort(ctx) -> void:
	ctx.goal.release(self)


func _run(ctx) -> Status:
	if memory == null or not memory.has_target_estimate:
		return Status.FAILURE

	ctx.goal.request(self, memory.last_credible_target_position)

	if ctx.goal.is_unreachable():
		# No amount of running changes this, and there is nothing else to chase. Failing lets
		# the sweep below take over; what it must NOT do is decide the target is gone,
		# because hunt sustain is the only thing allowed to end a hunt.
		return Status.FAILURE
	if ctx.goal.is_arrived(ctx.body_position):
		return Status.FAILURE
	return Status.RUNNING
