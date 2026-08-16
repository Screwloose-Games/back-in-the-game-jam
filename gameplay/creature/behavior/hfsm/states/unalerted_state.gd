class_name UnalertedState
extends BehaviorState

## Territorial ambient behaviour (fsm.md; behavior.md section 24).
##
## The alien moves between nests, not along a patrol route. Vision is dulled -- alertness 0.0
## is below Perception's vision gate -- and it is not looking for you.
##
## ```text
## Selector
## |-- Sequence
## |   |-- Condition  at_nest
## |   +-- Action     idle_at_nest
## +-- Action         travel_to_nest
## ```
##
## THE TABLE ORDER PUTS INVESTIGATING BEFORE THE DIRECT HUNT, and that is fsm.md's order
## rather than an oversight here. The visible consequence is worth knowing: because a
## touch strong enough to name a player also raises a hotspot well above
## `investigate_threshold`, the investigate row nearly always wins the tick, and the alien
## spends `min_dwell_s` coming to look before it commits to hunting. That reads as a beat --
## "something is coming" before "it is coming for me" -- so it is kept rather than reordered.
## The direct row still fires when a candidate is credible and no hotspot clears the
## threshold.

var memory: UnalertedMemory = null


func _init() -> void:
	memory = UnalertedMemory.new()
	var branch: Array[BtNode] = [BtAtNest.new(memory), BtIdleAtNest.new(memory)]
	var root: Array[BtNode] = [
		BtSequence.new(&"rest", branch),
		BtTravelToNest.new(memory),
	]
	tree = BehaviorTree.new(BtSelector.new(&"unalerted", root))


func state_id() -> CreatureState.State:
	return CreatureState.State.UNALERTED


## Nothing is remembered across a visit to another state: the world has moved on, and the
## nest that scored best two minutes ago is not necessarily the one that scores best now.
func enter(_ctx, _from: BehaviorState) -> void:
	memory.forget_intent()


func next_transition(ctx, _time_in_state: float) -> BehaviorTransition:
	var shift: float = _bias(ctx)
	var threshold: float = ctx.config.investigate_threshold - shift
	# THE STRONGEST HOTSPOT, NOT OVERALL SUSPICION. Overall suspicion is a scalar with no
	# location -- it can cross a threshold while giving Behavior nowhere to walk. Keying off
	# a hotspot guarantees that entering INVESTIGATING comes with a destination.
	var hotspot: SuspicionHotspot = ctx.suspicion.get_strongest_hotspot()
	if hotspot != null and hotspot.suspicion >= threshold:
		return BehaviorTransition.make(
			CreatureState.State.INVESTIGATING, &"hotspot", hotspot.suspicion, threshold
		)
	# Deliberately UNSHIFTED by escalation_bias: fsm.md biases the investigate row and the
	# INVESTIGATING -> HUNTING row, and pointedly not this one. A bored Director may make the
	# alien curious; it may not make it murderous.
	return hunt_transition(ctx, ctx.config.direct_hunt_threshold, &"direct_evidence")


func nest_journey() -> UnalertedMemory:
	return memory


func _bias(ctx) -> float:
	if ctx.directive == null:
		return 0.0
	return ctx.config.threshold_shift(ctx.directive.escalation_bias)
