class_name ReconsideringState
extends BehaviorState

## Stop, because what it was trying to do is not working.
##
## ```text
## Action  reconsider          (BtDoNothing -- holds still, RUNNING forever)
## ```
##
## THE TREE IS EMPTY ON PURPOSE AND THAT IS THE ENTIRE STATE. Every other mode answers "what
## should I do"; this one answers "nothing, and stop asking". The creature holds no navigation
## goal here -- the outgoing state's `exit` aborted its tree, which released the goal, and
## nothing in here takes another -- so it genuinely stands still rather than walking somewhere
## quieter. `CreatureAgent` parks its leash marker on the body the moment the route is gone.
##
## `BtDoNothing` reports RUNNING rather than SUCCESS for the reason its own docstring gives: a
## state whose tree succeeds looks finished, and this one is not finished, it has nothing to
## do. The exit is a transition, which is the only thing allowed to end a state.
##
## GIVING UP HAPPENS ON ENTRY, NOT ON EXIT. `enter` is the moment the decision was made, and
## the id it needs is on the outgoing state object -- which is handed in as `from`, and is the
## same trick `RetreatingState._anchor` uses to read the hunt's last credible position. Waiting
## until exit would mean the lead is still live for the whole dwell, so a creature knocked out
## of RECONSIDERING early -- by a player walking into view -- would have written nothing off.
##
## IT DOES NOT TELL SUSPICION THE PLACE IS EMPTY. `mark_unreachable` is a claim about the
## creature: it could not get there. The belief is untouched, and the alien goes on being
## exactly as afraid of that place as it was -- it has simply stopped walking at it. Saying
## anything stronger would be Behavior declaring a room searched without ever going there,
## which is the one thing suspicion.md forbids outright.

var memory: ReconsideringMemory = null


func _init() -> void:
	memory = ReconsideringMemory.new()
	tree = BehaviorTree.new(BtDoNothing.new(&"reconsider"))


func state_id() -> CreatureState.State:
	return CreatureState.State.RECONSIDERING


func enter(ctx, from: BehaviorState) -> void:
	memory.forget()
	var investigating := from as InvestigatingState
	if investigating == null or investigating.memory.hotspot_id < 0:
		return
	memory.hotspot_id = investigating.memory.hotspot_id
	if ctx.suspicion != null:
		ctx.suspicion.mark_unreachable(memory.hotspot_id)


func next_transition(ctx, time_in_state: float) -> BehaviorTransition:
	# A credible player beats standing around, always. The creature stopped walking at a PLACE
	# it could not reach; a PERSON it can see is a different question, and `hunt_transition`
	# already refuses when the Director has withdrawn permission.
	var shift: float = 0.0
	if ctx.directive != null:
		shift = ctx.config.threshold_shift(ctx.directive.escalation_bias)
	var hunt: BehaviorTransition = hunt_transition(
		ctx, ctx.config.hunt_threshold - shift, &"candidate"
	)
	if hunt != null:
		return hunt
	if time_in_state >= ctx.config.reconsider_dwell_s:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED,
			&"reconsidered",
			time_in_state,
			ctx.config.reconsider_dwell_s
		)
	return null
