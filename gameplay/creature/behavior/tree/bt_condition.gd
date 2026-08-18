class_name BtCondition
extends BtNode

## SUCCESS or FAILURE only. Never RUNNING, never side-effecting.
##
## THE NO-SIDE-EFFECTS RULE IS WHAT MAKES THE REACTIVE RE-TICK SOUND (fsm.md's design
## invariants). Every condition is re-evaluated from the root every frame, including while a
## deeper leaf is RUNNING. A condition that mutated anything would therefore mutate it once
## per frame, forever, and the tree's cheapness would become the creature's bug.
##
## Subclasses implement `_check`, not `_run`, so a condition physically cannot report
## RUNNING however it is written.


## Never overridden. `_check` is the seam.
func _run(ctx) -> Status:
	return Status.SUCCESS if _check(ctx) else Status.FAILURE


## The question. Pure: reads belief, position and config, and writes nothing.
func _check(_ctx) -> bool:
	return false
