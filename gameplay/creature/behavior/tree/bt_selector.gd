class_name BtSelector
extends BtComposite

## Ticks children in order and returns the first non-FAILURE. All failed -> FAILURE.
##
## The priority node. In every tree here the order IS the claim: HUNTING's
## bite-beats-pursue-beats-wait-beats-search, INVESTIGATING's search-here-before-going-
## somewhere-else. Re-entered from child zero every tick, so a higher-priority branch that
## becomes viable takes over on the frame it does.


func _run(ctx) -> Status:
	_active = null
	for child: BtNode in children:
		var status: Status = child.tick(ctx)
		if status == Status.RUNNING:
			_active = child
			return Status.RUNNING
		if status == Status.SUCCESS:
			return Status.SUCCESS
	return Status.FAILURE
