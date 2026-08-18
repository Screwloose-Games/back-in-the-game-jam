class_name BtInverter
extends BtDecorator

## Swaps SUCCESS and FAILURE. Passes RUNNING through unchanged.
##
## RUNNING IS NOT A RESULT TO INVERT -- it means "ask me again next frame", and a decorator
## that turned it into SUCCESS would report a half-finished action as complete. Neither
## shipped tree uses this node; it is built and tested because fsm.md's table lists it, and
## a framework that does not match its own documentation is worse than one missing a node.


func _run(ctx) -> Status:
	if child == null:
		return Status.FAILURE
	var status: Status = child.tick(ctx)
	if status == Status.RUNNING:
		return Status.RUNNING
	return Status.FAILURE if status == Status.SUCCESS else Status.SUCCESS
