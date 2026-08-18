class_name BtInvestigateLocation
extends BtAction

## Walks to wherever inside the current hotspot is still unexplained.
##
## Reads the location the state refreshed this tick rather than asking Suspicion itself, so
## the condition above it and this action can never disagree about where "there" is.
##
## FAILURE ON A DEAD LEAD, NOT A WALK TO THE ORIGIN. `get_best_unresolved_location` returns
## `Vector3.ZERO` for an id that is no longer live -- NOT the hotspot centre, whatever its
## docstring says -- so an alien whose hotspot resolves mid-approach sets off for world zero.
## The guard is the state's liveness check rather than a coordinate test: for a LIVE hotspot
## the answer falls back to the hotspot's own position, so the origin is returned only for a
## dead id. Testing the coordinate instead would also falsely condemn a hotspot that
## legitimately sits near the origin, which is a level-shaped assumption rather than a rule.

var memory: InvestigatingMemory = null


func _init(p_memory: InvestigatingMemory) -> void:
	super(&"investigate_location")
	memory = p_memory


func abort(ctx) -> void:
	ctx.goal.release(self)


func _run(ctx) -> Status:
	if memory == null or not memory.has_location:
		return Status.FAILURE

	# The deadband is inside BehaviorGoal, so this is free to run every tick and will not
	# reset navigation's stuck watchdog.
	ctx.goal.request(self, memory.desired_location)

	if ctx.goal.is_unreachable():
		# The alien cannot get there and no amount of walking will change that. Failing lets
		# the state time out or pick another lead instead of standing at a wall; what it must
		# NOT do is decide the hotspot is resolved, because nothing has been checked.
		return Status.FAILURE
	if ctx.goal.is_arrived(ctx.body_position):
		return Status.SUCCESS
	return Status.RUNNING
