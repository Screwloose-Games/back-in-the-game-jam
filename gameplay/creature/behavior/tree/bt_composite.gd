class_name BtComposite
extends BtNode

## A node with children, and the bookkeeping both composites share.
##
## NO SIBLING MEMORY, WHICH IS THE WHOLE POINT (fsm.md, "Fully reactive, no sibling
## memory"). `_active` records which child went RUNNING, but it is cleared at the top of
## every `_run`, so it never survives a tick. A memory-BT would keep the alien walking to a
## stale hotspot while a louder, closer lead went unexamined, because the branch that chose
## the stale one is never revisited.

var children: Array[BtNode] = []

var _active: BtNode = null


func _init(p_name: StringName, p_children: Array[BtNode]) -> void:
	node_name = p_name
	children = p_children


## Down the branch that is actually RUNNING, never into a child that merely ticked.
func running_leaf() -> BtNode:
	return _active.running_leaf() if _active != null else null


## Aborts whichever child is holding something. Reaches the leaf through `_active` rather
## than sweeping every child, so a sibling that never ran is never told to give back
## something it does not have.
func abort(ctx) -> void:
	if _active != null:
		_active.abort(ctx)
		_active = null
