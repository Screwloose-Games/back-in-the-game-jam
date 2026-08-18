class_name RetreatingState
extends BehaviorState

## End the encounter legibly (fsm.md; behavior.md section 30).
##
## ```text
## Selector
## |-- Sequence[disengage_was_sated, retreat_to_nest(distant, loud)]
## +-- retreat_to_nest(distant, quiet)
## ```
##
## ONE ACTION, TWO NAMES. There is no separate retreat action: `travel_to_nest` already takes
## the far-nest scoring and already renames itself, and it already carries the UNREACHABLE
## clause that stops the alien standing at a wall for the rest of the session. Writing a
## second copy of it to change one StringName would be two files to keep in step for no
## behaviour at all.
##
## THE TWO LEAVES CANNOT CONTEND, because the reason is latched on entry and never re-read --
## so for the whole of one visit to this state, exactly one of them is ever ticked. That is
## what makes it safe for both to share `travel_target`.
##
## RETREATING HAS EXACTLY ONE EXIT, AND IT IS NOT HUNTING. There is no path back at any
## suspicion level, for any evidence type. The Director cannot reliably terminate an
## encounter otherwise, and an encounter that cannot be terminated has no rhythm. The
## visible consequence is real: an alien walking away will ignore a player who shoots it in
## the back, and that should read as a predator that has lost interest.
##
## SEPARATION IS MEASURED FROM BELIEF, AND EUCLIDEAN. fsm.md does not say from what, and
## Behavior may not know a real player position. `directive.roam_anchor` is deliberately NOT
## in the chain even though it is the obvious candidate: it is derived from real player
## positions, so a Director whose anchor tracked the party could hold the alien in this state
## indefinitely by moving it. The floor of the chain is the creature's own position on entry,
## which is always defined, unspoofable, and reads plainly as "I have walked far enough from
## where I gave up".

## Where the retreat is measured from. Captured ONCE on entry -- hotspots are recomputed in
## place and smoothed toward a moving estimate, so a live read would make separation shrink
## as belief drifted and the alien would never get away.
var separation_from: Vector3 = Vector3.ZERO

var memory: RetreatingMemory = null


func _init() -> void:
	memory = RetreatingMemory.new()
	var exhale: Array[BtNode] = [
		BtDisengageWasSated.new(memory),
		BtTravelToNest.new(memory, true, true),
	]
	var root: Array[BtNode] = [
		BtSequence.new(&"exhale", exhale),
		BtTravelToNest.new(memory, true),
	]
	tree = BehaviorTree.new(BtSelector.new(&"retreating", root))


func state_id() -> CreatureState.State:
	return CreatureState.State.RETREATING


## Both latches happen here, and for the same reason: what they read has moved on by the time
## the tree could ask.
func enter(ctx, from: BehaviorState) -> void:
	separation_from = _anchor(ctx, from)
	memory.disengage_reason = _reason(ctx)
	memory.forget_intent()


func next_transition(ctx, time_in_state: float) -> BehaviorTransition:
	var separation: float = ctx.body_position.distance_to(separation_from)
	if time_in_state >= ctx.config.retreat_min_s and separation >= ctx.config.retreat_separation_m:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"separated", separation, ctx.config.retreat_separation_m
		)
	# NOT IN fsm.md, and it is a backstop rather than a workaround. Reusing `travel_to_nest`
	# closed the asymmetry fsm.md left -- the retreat now carries the same UNREACHABLE clause
	# the wander does -- but that clause is narrower than it reads: against a baked graph a
	# target outside it comes back PARTIAL, not UNREACHABLE, because a partial route is not a
	# failure. So an alien sent to a nest it can only get halfway to walks at rock quite
	# happily, and so does one whose every known nest sits inside `retreat_separation_m` of
	# where it gave up. Neither is a per-nest failure and neither can be made into one.
	# Something still has to end the encounter.
	if time_in_state >= ctx.config.retreat_max_s:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"gave_up", time_in_state, ctx.config.retreat_max_s
		)
	return null


## The hunt's last credible target position, then the strongest hotspot, then where the
## creature is standing. Every one is belief-derived or its own state; none is a truth.
func _anchor(ctx, from: BehaviorState) -> Vector3:
	var hunt := from as HuntingState
	if hunt != null and hunt.memory.has_target_estimate:
		return hunt.memory.last_credible_target_position
	if ctx.suspicion != null:
		var hotspot: SuspicionHotspot = ctx.suspicion.get_strongest_hotspot()
		if hotspot != null:
			return hotspot.position
	return ctx.body_position


## Read once, here, because the Director rebuilds its directive every tick and the latch that
## brought the creature into this state was consumed at the transition. A tree leaf asking per
## tick would see NONE and the loud exit would quietly never happen.
func _reason(ctx) -> EncounterDirective.Reason:
	if ctx.directive == null:
		return EncounterDirective.Reason.NONE
	return ctx.directive.disengage_reason


## A retreat that never received the nest list has nowhere to walk, and would sit out its
## whole commitment period looking exactly like the placeholder it replaced.
func nest_journey() -> UnalertedMemory:
	return memory
