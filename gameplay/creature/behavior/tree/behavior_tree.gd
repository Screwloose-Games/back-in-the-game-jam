class_name BehaviorTree
extends RefCounted

## A root, and the abort bookkeeping that fsm.md calls "not optional".
##
## THE TREE IS RE-ENTERED FROM THE ROOT EVERY TICK. Conditions are re-evaluated even while a
## deeper leaf is RUNNING, and no composite remembers which child succeeded last tick. That
## costs a few condition evaluations per frame and buys an alien that changes its mind the
## instant the evidence does.
##
## THE ABORT CONTRACT, AND WHY IT IS ORDERED THE WAY IT IS. fsm.md asks for the outgoing
## leaf to be aborted "before any new leaf ticks". That is unimplementable: a reactive tree
## cannot know which leaf will run until it has ticked, so the abort necessarily happens
## after. The hazard that ordering creates -- the outgoing leaf's `clear_goal` wiping the
## incoming leaf's freshly-set goal -- is closed by BehaviorGoal instead: `release` is a
## no-op unless the caller still holds the goal. Actions therefore never call
## `navigation.set_goal` directly, and the order stops mattering.
##
## Trees are per creature and never shared. See BtNode.

## Fires when the running leaf changes, including to and from nothing. `CreatureBehavior`
## forwards it as `action_changed`, which is half of "why is it doing that".
signal running_leaf_changed(from: StringName, to: StringName)

var root: BtNode = null

var _running_leaf: BtNode = null


func _init(p_root: BtNode = null) -> void:
	root = p_root


func tick(ctx) -> BtNode.Status:
	if root == null:
		return BtNode.Status.FAILURE
	var previous: BtNode = _running_leaf
	var status: BtNode.Status = root.tick(ctx)
	_set_running_leaf(root.running_leaf())
	# After the tick, deliberately. See the class docstring.
	if previous != null and previous != _running_leaf and _was_abandoned(previous):
		previous.abort(ctx)
	return status


## Tears the whole branch down. Called on every state change and on teardown, which is the
## other half of fsm.md's abort contract -- a leaf holding a goal when its state exits would
## keep the creature walking somewhere the HFSM has stopped caring about.
func abort(ctx) -> void:
	if root != null:
		root.abort(ctx)
	_set_running_leaf(null)


func running_leaf() -> BtNode:
	return _running_leaf


func running_action() -> StringName:
	return _running_leaf.node_name if _running_leaf != null else &"none"


## ABANDONED IS NOT THE SAME AS "NO LONGER RUNNING", and conflating them makes every
## completed action undo itself.
##
## `previous` was RUNNING at the end of last tick, so its recorded status is RUNNING unless
## something overwrote it this tick. Reached and still going: it is the running leaf, handled
## above. Reached and finished: its status is now SUCCESS or FAILURE, and it was not
## abandoned -- it was told to do a thing and it did it. Never reached: the status is stale
## RUNNING, which is exactly the case fsm.md wants aborted.
##
## Only one leaf can be RUNNING per tick here -- every composite stops at its first RUNNING
## child and both decorators pass RUNNING through -- so a stale RUNNING is unambiguous.
func _was_abandoned(previous: BtNode) -> bool:
	return previous.last_status() == BtNode.Status.RUNNING


func _set_running_leaf(leaf: BtNode) -> void:
	if leaf == _running_leaf:
		return
	var before: StringName = _running_leaf.node_name if _running_leaf != null else &"none"
	_running_leaf = leaf
	running_leaf_changed.emit(before, running_action())
