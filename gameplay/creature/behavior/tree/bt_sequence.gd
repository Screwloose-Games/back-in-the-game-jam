class_name BtSequence
extends BtComposite

## Ticks children in order and returns the first non-SUCCESS. All succeeded -> SUCCESS.
##
## RE-RUN FROM CHILD ZERO EVERY TICK, INCLUDING THE CONDITIONS. That is what makes
## `Sequence[condition, action]` mean "do this while the condition still holds" rather than
## "the condition was true once, so run to completion". A sequence with sibling memory
## would keep an alien searching a spot whose reason to search it evaporated two seconds
## ago, and every individual decision would still look correct.


func _run(ctx) -> Status:
	_active = null
	for child: BtNode in children:
		var status: Status = child.tick(ctx)
		if status == Status.RUNNING:
			_active = child
			return Status.RUNNING
		if status == Status.FAILURE:
			return Status.FAILURE
	return Status.SUCCESS
