class_name InvestigatingState
extends BehaviorState

## Resolve uncertainty about a PLACE (fsm.md; behavior.md section 25).
##
## The alien has a hotspot worth walking to. It travels, searches, and lets Perception's
## disconfirmations resolve or fail to resolve the belief. It does not have a target; it has
## a location.
##
## ```text
## Selector
## |-- Sequence
## |   |-- Condition  arrived_at_goal
## |   +-- Cooldown   search_area
## +-- Action         investigate_location
## ```
##
## `refresh` RUNS BEFORE THE TREE, EVERY TICK, and it is the load-bearing part of this
## state. The best unresolved location MOVES as searching disconfirms sub-regions -- that
## motion is the whole of suspicion.md's spatial resolution, and it is what lets the alien
## work its way into a hotspot rather than standing on the first point it picked. Doing that
## work inside a condition would make the condition side-effecting, which the reactive
## re-tick cannot survive; doing it inside the action would leave the condition testing a
## stale point.
##
## IT ALSO RE-LEADS. behavior.md section 25's first branch is "current hotspot resolved? ->
## select another hotspot", so a lead dying mid-approach picks the next one rather than
## dropping straight back to UNALERTED. Only an empty board ends the state.

var memory: InvestigatingMemory = null

var _search_gate: BtCooldown = null


func _init() -> void:
	memory = InvestigatingMemory.new()
	_search_gate = BtCooldown.new(&"search_gate", 1.0, BtSearchArea.new(memory))
	var branch: Array[BtNode] = [BtArrivedAtGoal.new(memory), _search_gate]
	var root: Array[BtNode] = [
		BtSequence.new(&"search_here", branch),
		BtInvestigateLocation.new(memory),
	]
	tree = BehaviorTree.new(BtSelector.new(&"investigating", root))


func state_id() -> CreatureState.State:
	return CreatureState.State.INVESTIGATING


func enter(ctx, _from: BehaviorState) -> void:
	memory.forget()
	_apply_cooldown(ctx)
	refresh(ctx)


## Drops a lead the moment Suspicion says it is gone, rather than one hotspot rebuild later.
## Wired by CreatureBehavior; the state does not reach for the signal itself.
func on_hotspot_resolved(hotspot_id: int) -> void:
	if hotspot_id == memory.hotspot_id:
		memory.forget()


func refresh(ctx) -> void:
	if ctx.suspicion == null:
		memory.forget()
		return
	if ctx.suspicion.get_hotspot(memory.hotspot_id) == null and not _take_lead(ctx):
		memory.forget()
		return
	# For a LIVE hotspot this always answers with a real point -- the sampler falls back to
	# the hotspot's own position -- so the Vector3.ZERO that a dead id returns is exactly
	# what the liveness check above has already excluded.
	memory.desired_location = ctx.suspicion.get_best_unresolved_location(memory.hotspot_id)
	memory.has_location = true


func next_transition(ctx, time_in_state: float) -> BehaviorTransition:
	var shift: float = 0.0
	if ctx.directive != null:
		shift = ctx.config.threshold_shift(ctx.directive.escalation_bias)
	var threshold: float = ctx.config.hunt_threshold - shift
	var hunt: BehaviorTransition = hunt_transition(ctx, threshold, &"candidate")
	if hunt != null:
		return hunt
	if time_in_state > ctx.config.investigate_timeout_s:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED,
			&"timeout",
			time_in_state,
			ctx.config.investigate_timeout_s
		)
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if leads.is_empty():
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"nothing_left", 0.0, ctx.config.attention_floor
		)
	return null


## The strongest hotspot still worth attention. `get_hotspots_above` already sorts
## descending, so the first entry is the lead.
func _take_lead(ctx) -> bool:
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if leads.is_empty():
		return false
	memory.hotspot_id = leads[0].id
	return true


## The cooldown gating `search_area` is a config number, but BtCooldown takes it at
## construction and the state is built before it has ever seen a config.
func _apply_cooldown(ctx) -> void:
	if ctx.config != null:
		_search_gate.seconds = ctx.config.search_cooldown_s
