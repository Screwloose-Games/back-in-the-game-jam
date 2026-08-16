class_name BehaviorContext
extends RefCounted

## Everything a tree node is allowed to see, typed (fsm.md, "Typed context, not a
## blackboard").
##
## A string-keyed Dictionary blackboard is the conventional choice and the wrong one here:
## it defeats autocomplete, hides typos as silent nulls, and gives gdlint nothing to check.
## Per-state memory that outlives a tick -- the active hotspot id, the chosen nest, the lurk
## deadline -- lives on the STATE OBJECT, not here, so this stays a per-tick view.
##
## `body_position` IS A VECTOR3 AND NOT `body.global_position`, WHICH IS NOT A STYLE
## PREFERENCE. Reading global_position off a Node3D that was never added to a tree makes the
## engine log "Condition !is_inside_tree() is true", and GUT counts that as an unexpected
## error and FAILS THE TEST -- see test_navigation_invariants.gd, which documents the same
## trap. The whole behavior suite builds its facades with .new() and never parents them, so
## an action reaching through `body` would take the suite down. CreatureBehavior resolves
## the position once, with the same guard CreaturePerception._own_position() uses.
##
## `goal` and the three subsystems are long-lived service references rather than per-tick
## values. That is the same thing `navigation` already is, and it is what lets the context
## be rebuilt cheaply every tick without losing the goal ownership token.

var suspicion: CreatureSuspicion = null
var navigation: CreatureNavigation = null
var perception: CreaturePerception = null
var goal: BehaviorGoal = null
var config: BehaviorConfig = null
var directive: EncounterDirective = null
## The machine a state is running inside. States reach it only to consume the
## `force_disengage` latch -- the one piece of transition state that outlives a directive
## and therefore cannot live on the directive. NOTHING MAY CALL A TRANSITION THROUGH IT:
## only the HFSM changes state, and a state that transitioned itself would make the table
## a suggestion.
var hfsm: CreatureHfsm = null

## Kept for facing and for anything that needs the node itself. NOTHING MAY READ
## `global_position` OFF IT -- use `body_position`. See the class docstring.
var body: Node3D = null
var body_position: Vector3 = Vector3.ZERO

## Behavior's own clock, fed from the delta it is handed. Never a wall clock:
## Time.get_ticks_msec() ignores get_tree().paused and Engine.time_scale, and cannot be
## driven from a test. Not the same clock as Suspicion's or Perception's, which start when
## their own nodes are constructed.
var clock: float = 0.0


## True when every subsystem a tree needs is present. Actions guard on this rather than
## null-checking one reference each, so a half-wired creature fails visibly at the tree
## rather than at a random leaf.
func is_wired() -> bool:
	return suspicion != null and navigation != null and goal != null and config != null
