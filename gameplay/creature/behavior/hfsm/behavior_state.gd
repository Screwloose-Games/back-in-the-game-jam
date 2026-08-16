class_name BehaviorState
extends RefCounted

## One HFSM mode: a tree, whatever memory outlives a tick, and the rows out of it.
##
## THE STATE OWNS THE MEMORY, NOT THE CONTEXT (fsm.md, "Typed context, not a blackboard").
## The active hotspot id, the chosen nest, the lurk deadline, the last credible target
## position -- all of it lives on a subclass of this, typed, so the context stays a pure
## per-tick view and nothing is addressed by string.
##
## ONLY THE HFSM CHANGES STATE. A state answers `next_transition` with what it would do; it
## does not do it, and neither does its tree. A tree returns actions, and having nothing
## useful to do is a fact the HFSM reads rather than a transition the tree performs.
##
## Rows are grouped by source state here rather than kept in one global table. That is
## equivalent to fsm.md's "table order, first match wins" because the table is already
## grouped by From, and it keeps each state's rows next to the memory they read.

var tree: BehaviorTree = null


func state_id() -> CreatureState.State:
	return CreatureState.State.UNALERTED


## Called once on entry, before the first tick. `from` is null on the very first entry.
func enter(_ctx, _from: BehaviorState) -> void:
	pass


## Refresh whatever memory the tree is about to read, then tick the tree.
##
## THE REFRESH GOES FIRST, AND IT MATTERS. INVESTIGATING recomputes where it wants to be
## before its conditions are asked; doing it inside a condition instead would make the
## condition side-effecting, which is what the reactive re-tick cannot survive.
func tick(ctx) -> void:
	refresh(ctx)
	if tree != null:
		tree.tick(ctx)


## Per-tick state memory update. Pure with respect to the world -- it reads belief and
## writes only to this object.
func refresh(_ctx) -> void:
	pass


## Tears down the tree and gives back anything the state itself took.
func exit(ctx) -> void:
	if tree != null:
		tree.abort(ctx)


## The first row out of this state whose guard holds, or null. Ordered.
func next_transition(_ctx, _time_in_state: float) -> BehaviorTransition:
	return null


## The `-> HUNTING` guard, which both UNALERTED and INVESTIGATING carry with different
## thresholds and different reasons.
##
## HUNTING REQUIRES A PERSON, NOT A PLACE. It keys off a PlayerSuspicionCandidate rather
## than a hotspot, and that is the whole distinction between the two states: you investigate
## a where, you hunt a who. `source_confidence` is the second half of it -- only vision and
## touch ever set it, and hearing deliberately never does, so a noise can bring the alien
## looking for you but cannot make it hunt you by name.
static func hunt_transition(ctx, threshold: float, reason: StringName) -> BehaviorTransition:
	if ctx.directive != null and not ctx.directive.permit_hunt:
		return null
	var candidate: PlayerSuspicionCandidate = ctx.suspicion.get_best_player_candidate()
	if candidate == null or candidate.suspicion < threshold:
		return null
	if candidate.source_confidence < ctx.config.hunt_confidence:
		return null
	return BehaviorTransition.make(
		CreatureState.State.HUNTING, reason, candidate.suspicion, threshold
	)


## What Perception is told to do with its attention while this state runs.
func alertness(config: BehaviorConfig) -> float:
	return config.alertness_for(state_id()) if config != null else 0.0


func running_action() -> StringName:
	return tree.running_action() if tree != null else &"none"
