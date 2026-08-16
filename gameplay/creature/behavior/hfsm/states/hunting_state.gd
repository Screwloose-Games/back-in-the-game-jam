class_name HuntingState
extends BehaviorState

## Pursue a credible PLAYER (fsm.md; behavior.md section 26).
##
## THE TREE IS NOT BUILT. Hunting needs an attack, a crevice model and a target estimate,
## none of which exist; what is here is every guard into and out of the state, and the
## commitment machinery those guards need. The placeholder tree holds still and reports
## RUNNING, which is honest -- a state with nothing to do is a fact, not a success.
##
## HUNT SUSTAIN IS WHAT MAKES HUNTING A COMMITMENT, and it is the reason this state carries
## memory at all. It is lost only when BOTH hold: no candidate above
## `hunt_sustain_threshold` for a continuous `hunt_sustain_grace_s`, AND no unresolved
## suspicion within `hunt_sustain_radius` of the last credible target position. Losing sight
## of the player does not end a hunt -- the alien searches where it last believed you were.
##
## `last_credible_target_position` IS BELIEF, NEVER TRUTH. It is read off the hotspot the
## creature attributes to its target, so it is wrong exactly as often as the creature is.
## RETREATING borrows it as the point separation is measured from, which is the only other
## consumer.

var last_credible_target_position: Vector3 = Vector3.ZERO
var has_target_estimate: bool = false

## Behavior-clock time at which the candidate first fell below the sustain threshold, or
## -1.0 while it is above. The grace is measured from here.
var _starved_since: float = -1.0


func _init() -> void:
	tree = BehaviorTree.new(BtDoNothing.new(&"hunt_placeholder"))


func state_id() -> CreatureState.State:
	return CreatureState.State.HUNTING


func enter(ctx, _from: BehaviorState) -> void:
	_starved_since = -1.0
	has_target_estimate = false
	refresh(ctx)


func refresh(ctx) -> void:
	if ctx.suspicion == null:
		return
	var hotspot: SuspicionHotspot = _credible_hotspot(ctx)
	if hotspot != null:
		last_credible_target_position = hotspot.position
		has_target_estimate = true
	_track_starvation(ctx)


func next_transition(ctx, _time_in_state: float) -> BehaviorTransition:
	# The latch, not the live field. director.md has the HFSM consume force_disengage "at its
	# next transition check", and min_dwell_s routinely means that check is several ticks
	# after the Director asked.
	if ctx.hfsm != null and ctx.hfsm.disengage_pending():
		ctx.hfsm.consume_disengage()
		return BehaviorTransition.make(CreatureState.State.RETREATING, &"director", 1.0, 1.0)
	if _sustain_lost(ctx):
		return BehaviorTransition.make(
			CreatureState.State.RETREATING,
			&"lost",
			ctx.clock - _starved_since,
			ctx.config.hunt_sustain_grace_s
		)
	return null


## The hotspot the creature attributes to whoever it is hunting, preferring the Director's
## arbitrated target when there is one. Falls back to the strongest lead, because an alien
## that has lost the attribution has not necessarily lost the trail.
func _credible_hotspot(ctx) -> SuspicionHotspot:
	var target: Node = ctx.directive.target if ctx.directive != null else null
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if target != null:
		for hotspot: SuspicionHotspot in leads:
			if hotspot.likely_source == target:
				return hotspot
	return leads[0] if not leads.is_empty() else null


func _track_starvation(ctx) -> void:
	var candidate: PlayerSuspicionCandidate = ctx.suspicion.get_best_player_candidate()
	var fed: bool = candidate != null and candidate.suspicion >= ctx.config.hunt_sustain_threshold
	if fed:
		_starved_since = -1.0
	elif _starved_since < 0.0:
		_starved_since = ctx.clock


## BOTH conditions, and the `and` is the whole design. Either one alone ends a hunt the
## moment the player breaks line of sight, which is precisely what behavior.md section 26
## says must not happen.
func _sustain_lost(ctx) -> bool:
	if _starved_since < 0.0:
		return false
	if ctx.clock - _starved_since < ctx.config.hunt_sustain_grace_s:
		return false
	if not has_target_estimate:
		return true
	var nearby: float = ctx.suspicion.get_suspicion_near(
		last_credible_target_position, ctx.config.hunt_sustain_radius
	)
	return nearby <= ctx.config.attention_floor
