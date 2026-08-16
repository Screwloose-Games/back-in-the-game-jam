class_name BtDecorator
extends BtNode

## A node wrapping exactly one child. Shared by BtInverter and BtCooldown.
##
## A decorator is never itself the running leaf -- it delegates, so `running_leaf()` reaches
## the action underneath and `abort` reaches the thing actually holding a goal. A decorator
## that answered for itself would have the tree abort a wrapper while the action inside kept
## its navigation goal.

var child: BtNode = null


func _init(p_name: StringName, p_child: BtNode) -> void:
	node_name = p_name
	child = p_child


func running_leaf() -> BtNode:
	return child.running_leaf() if child != null else null


func abort(ctx) -> void:
	if child != null:
		child.abort(ctx)
