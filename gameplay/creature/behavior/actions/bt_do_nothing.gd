class_name BtDoNothing
extends BtAction

## Holds still and reports RUNNING, forever.
##
## THE PLACEHOLDER TREE FOR HUNTING AND RETREATING, and it is deliberately not a stub that
## pretends to work. Neither of those trees exists yet: hunting needs a target estimate, an
## attack and crevices, and retreating needs a nest-scoring pass with the distance term
## inverted. What DOES exist is every transition guard into and out of both states, so the
## HFSM is complete and testable while the trees are owed.
##
## RUNNING rather than SUCCESS, because a state whose tree succeeds looks finished. This one
## is not finished; it has nothing to do, which is a fact the HFSM reads.


func _run(_ctx) -> Status:
	return Status.RUNNING
