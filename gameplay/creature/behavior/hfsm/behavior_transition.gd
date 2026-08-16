class_name BehaviorTransition
extends RefCounted

## One fired transition: where to, why, and the number that did it.
##
## THE NUMBER IS NOT DECORATION. fsm.md's debug requirement is one line that answers "why is
## it doing that", and it names "the value that fired the last transition" specifically.
## "UNALERTED -> INVESTIGATING (hotspot)" tells you what happened; "at 0.31 against a
## threshold of 0.25" tells you whether it should have.

var to: CreatureState.State = CreatureState.State.UNALERTED
## Named in `state_changed` and in the debug line. A short lowercase slug, not a sentence.
var reason: StringName = &""
## The measured value that satisfied the guard -- a suspicion, an elapsed time, a distance.
var value: float = 0.0
## What `value` had to beat. Together they are the whole story of one transition.
var threshold: float = 0.0


static func make(
	p_to: CreatureState.State, p_reason: StringName, p_value: float, p_threshold: float = 0.0
) -> BehaviorTransition:
	var transition := BehaviorTransition.new()
	transition.to = p_to
	transition.reason = p_reason
	transition.value = p_value
	transition.threshold = p_threshold
	return transition


func describe() -> String:
	return "%s (%s %.2f vs %.2f)" % [CreatureState.state_name(to), reason, value, threshold]
