class_name BtAction
extends BtNode

## Any status. The only nodes permitted to command anything.
##
## Two rules an action may not break, both from fsm.md and both enforced by
## `tools/verify_behavior_static.gd` rather than by review:
##
## AN ACTION NEVER WRITES BELIEF. `search_area` does not subtract suspicion -- it makes the
## creature dwell and sweep so that PERCEPTION emits the disconfirmation, which suppresses
## the belief. Suspicion has exactly three doors: evidence, disconfirmation, and the clock.
## Anything here that reached in and lowered a number would work visibly better and destroy
## the design.
##
## AN ACTION NEVER MOVES THE BODY. It commands Navigation, through `ctx.goal`. Movement is
## downstream and owns acceleration, turning and collision response.
##
## Actions may hold node-local state across ticks -- a request they issued, a deadline they
## set. `abort` is where all of it is given back.


func _init(p_name: StringName = &"action") -> void:
	node_name = p_name
