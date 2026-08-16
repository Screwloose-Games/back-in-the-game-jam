class_name RetreatingState
extends BehaviorState

## End the encounter legibly (fsm.md; behavior.md section 30).
##
## THE TREE IS NOT BUILT. Retreating needs the nest scoring with its distance term inverted
## and a loud-versus-quiet split on `directive.disengage_reason`; the placeholder holds
## still. Both guards out of the state are real.
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


func _init() -> void:
	tree = BehaviorTree.new(BtDoNothing.new(&"retreat_placeholder"))


func state_id() -> CreatureState.State:
	return CreatureState.State.RETREATING


func enter(ctx, from: BehaviorState) -> void:
	separation_from = _anchor(ctx, from)


func next_transition(ctx, time_in_state: float) -> BehaviorTransition:
	var separation: float = ctx.body_position.distance_to(separation_from)
	if time_in_state >= ctx.config.retreat_min_s and separation >= ctx.config.retreat_separation_m:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"separated", separation, ctx.config.retreat_separation_m
		)
	# NOT IN fsm.md, and a workaround rather than a fix. `retreat_to_nest` has no UNREACHABLE
	# failure clause where `travel_to_nest` does, so an unreachable far nest plus unmet
	# separation leaves this state with no reachable exit at all. See BehaviorConfig.
	if time_in_state >= ctx.config.retreat_max_s:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"gave_up", time_in_state, ctx.config.retreat_max_s
		)
	return null


## The hunt's last credible target position, then the strongest hotspot, then where the
## creature is standing. Every one is belief-derived or its own state; none is a truth.
func _anchor(ctx, from: BehaviorState) -> Vector3:
	var hunt := from as HuntingState
	if hunt != null and hunt.has_target_estimate:
		return hunt.last_credible_target_position
	if ctx.suspicion != null:
		var hotspot: SuspicionHotspot = ctx.suspicion.get_strongest_hotspot()
		if hotspot != null:
			return hotspot.position
	return ctx.body_position
