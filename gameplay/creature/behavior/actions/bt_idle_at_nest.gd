class_name BtIdleAtNest
extends BtAction

## Loiters at the nest it travelled to. RUNNING until `nest_dwell_s`, then SUCCESS.
##
## Commands nothing at all -- no goal, no scan. It is the only action in either tree that
## takes nothing, which is why its `abort` has nothing to give back but the timer. Animation
## is downstream and reads the running action's name.
##
## THE DWELL IS WHAT MAKES WANDERING READ AS TERRITORIAL. Without it the alien arrives,
## immediately scores the next nest and leaves, which looks like patrolling -- the one thing
## behavior.md section 24 asks this state not to look like.

var memory: UnalertedMemory = null


func _init(p_memory: UnalertedMemory) -> void:
	super(&"idle_at_nest")
	memory = p_memory


## Drops the deadline but keeps the target, so an interrupted idle resumes as an arrival
## rather than restarting a dwell the creature has mostly served.
func abort(_ctx) -> void:
	if memory != null:
		memory.dwell_until = 0.0


func _run(ctx) -> Status:
	if memory == null:
		return Status.FAILURE
	if memory.dwell_until <= 0.0:
		memory.dwell_until = ctx.clock + ctx.config.nest_dwell_s
		# Stamped on ARRIVAL rather than on departure. A nest the alien is sitting in is the
		# most recently used one there is, and waiting until it leaves would let the very
		# next choice land on the nest it is standing in.
		memory.nests.mark_visited(memory.travel_target, ctx.clock)
	if ctx.clock < memory.dwell_until:
		return Status.RUNNING
	# Clearing the intent is what turns `at_nest` false next tick and lets the selector fall
	# through to travel. Without it the two nodes agree the creature is home and it never
	# leaves again.
	memory.forget_intent()
	return Status.SUCCESS
