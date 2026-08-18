class_name BtLurkAtTunnelMouth
extends BtAction

## Waits outside a gap the creature cannot fit through. RUNNING until a randomised deadline.
##
## THE STANDOFF IS FREE, AND THAT IS THE POINT. behavior.md section 29 asks for "a reachable
## position nearby", which is exactly what a PARTIAL route already produces -- nav_route.gd
## terminates a route it cannot complete "at the nearest useful reachable location rather than
## produce an empty path". So this asks for the estimate itself, navigation stops the alien at
## the mouth of the gap, and there is no standoff distance to tune and no position to compute.
##
## THE DURATION MUST VARY, AND THAT IS A MECHANIC RATHER THAN A FLOURISH. A fixed wait is
## something the player counts, and a gap with a known safe interval stops being a gamble.
## `BehaviorConfig.invariant_failures` rejects a range with no width in it, and the draw comes
## off the context's seeded generator so a test can pin one and the game cannot.
##
## IT DOES NOT CARE WHETHER THE ESTIMATE IS FRESH. Section 29's whole trigger is evidence
## disappearing near such a gap -- waiting is what the alien does once it has stopped knowing.
## New evidence moves the estimate, `target_beyond_reach` goes false the moment the graph can
## route there again, and the chase branch above takes the tick back.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	super(&"lurk_at_tunnel_mouth")
	memory = p_memory


## Gives the goal back AND drops the deadline, so an interrupted lurk does not resume
## part-served. A creature that was pulled away and came back has learned something in
## between; the wait it owes is a fresh draw, not the remainder of an old one.
func abort(ctx) -> void:
	ctx.goal.release(self)
	if memory != null:
		memory.lurk_until = 0.0


func _run(ctx) -> Status:
	if memory == null or not memory.has_target_estimate:
		return Status.FAILURE

	ctx.goal.request(self, memory.last_credible_target_position)

	if memory.lurk_until <= 0.0:
		memory.lurk_until = ctx.clock + ctx.config.lurk_duration(ctx.rng)
	if ctx.clock < memory.lurk_until:
		return Status.RUNNING

	# Cleared on the way out so the next lurk draws again. Leaving it armed would make every
	# wait after the first one instantaneous.
	memory.lurk_until = 0.0
	return Status.SUCCESS
