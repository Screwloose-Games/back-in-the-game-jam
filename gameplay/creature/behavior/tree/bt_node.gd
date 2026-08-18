class_name BtNode
extends RefCounted

## The base of the behavior tree framework (fsm.md, "The behavior tree framework").
##
## DOMAIN-FREE, AND THE VERIFIER ENFORCES IT. Nothing under tree/ may name
## CreatureSuspicion, CreatureNavigation or CreaturePerception. A tree that knows what an
## alien is cannot be reused for anything else, and "reusable" that is never checked is a
## claim rather than a property. The context is the only thing crossing the boundary, and
## its type is declared outside this directory.
##
## RefCounted rather than Node: trees are built in code, never in a scene, so the whole
## framework runs in GUT with no tree, no physics and no frames.
##
## SUBCLASSES OVERRIDE `_run`, NOT `tick`. `tick` is the template that records the status,
## which is what lets BehaviorTree find the running leaf afterwards without every leaf
## author remembering to register itself. A leaf that overrode `tick` would vanish from the
## abort bookkeeping and leak whatever it was holding, silently.
##
## Trees are built PER CREATURE and never shared. BtCooldown holds a last-success time and
## BehaviorTree holds a running-leaf reference, so one preloaded `const` tree would couple
## two aliens' cooldowns in a way that reads as a tuning problem.

enum Status { SUCCESS, FAILURE, RUNNING }

## What `action_changed` reports and what the debug line prints. Every node has one, set at
## construction, because retrofitting a name onto a whole framework later never happens.
var node_name: StringName = &"node"

var _last_status: Status = Status.FAILURE


static func status_name(value: Status) -> String:
	match value:
		Status.SUCCESS:
			return "success"
		Status.FAILURE:
			return "failure"
		Status.RUNNING:
			return "running"
	return "?"


## One tick. Do not override -- override `_run`.
func tick(ctx) -> Status:
	_last_status = _run(ctx)
	return _last_status


## Called when this node was RUNNING and the tree did not reach it again, and on state
## change and teardown. Whatever an action took, it gives back here.
##
## NOT OPTIONAL BOOKKEEPING. An action owns a navigation goal; without abort, a chase
## yielding to a lurk leaves the chase goal live and the creature walks to a position
## nothing asked for.
func abort(_ctx) -> void:
	pass


## The leaf currently RUNNING beneath this node, or null. Composites delegate to whichever
## child they ticked into RUNNING this frame; leaves answer for themselves.
func running_leaf() -> BtNode:
	return self if _last_status == Status.RUNNING else null


## The status this node last reported. Debug only -- nothing branches on it.
func last_status() -> Status:
	return _last_status


## The actual work. `ctx` is a BehaviorContext, left untyped so this directory names
## nothing from the creature.
func _run(_ctx) -> Status:
	return Status.FAILURE
