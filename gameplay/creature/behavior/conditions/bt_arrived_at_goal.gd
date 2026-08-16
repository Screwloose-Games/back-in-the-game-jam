class_name BtArrivedAtGoal
extends BtCondition

## Is the creature standing where it currently wants to be?
##
## TWO CLAUSES, AND DROPPING EITHER BREAKS THE STATE.
##
## "Navigation says we are there" alone loops forever. After a search completes, the best
## unresolved location moves -- that motion is the whole of suspicion.md's spatial
## resolution -- but the body has not moved, so `follower.is_finished` is still true and the
## search branch wins again. The alien searches one spot until the timeout, and the hotspot
## never resolves.
##
## "The body is near the desired location" alone tests arrival against a point navigation was
## never sent to. BehaviorGoal deliberately does not re-issue for moves under
## `goal_refresh_m`, so the committed goal and the desired location are routinely different
## by a couple of metres by design.
##
## So: the committed goal must still BE the desired location, and navigation must say we have
## reached it. When a search moves the answer, the first clause fails, the selector falls
## through to `investigate_location`, and it re-commits.

var memory: InvestigatingMemory = null


func _init(p_memory: InvestigatingMemory) -> void:
	node_name = &"arrived_at_goal"
	memory = p_memory


func _check(ctx) -> bool:
	if memory == null or not memory.has_location or not ctx.goal.has_goal():
		return false
	if ctx.goal.committed().distance_to(memory.desired_location) > ctx.config.goal_refresh_m:
		return false
	return ctx.goal.is_arrived(ctx.body_position)
