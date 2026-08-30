class_name CreatureState
extends RefCounted

## The five HFSM modes (fsm.md, "The states"), and nothing else.
##
## ITS OWN FILE SO THE DIRECTOR CAN NAME IT. `EncounterReport.state` is typed on this enum,
## and `gameplay/director/` must not depend on the Behavior facade to say so. Godot has no
## free-standing enums, so the enum needs a class, and this is the smallest one that works.
##
## These stay explicit states rather than collapsing into one large tree because they change
## the RULES, not merely the chosen action. A hunting alien evaluates noise differently,
## commits to a target across perception gaps, and is subject to Director pacing -- none of
## which is expressible as "a different branch fired this frame".

enum State {
	## Territorial ambient behaviour. Vision is dulled. It is not looking for you.
	UNALERTED,
	## Resolve uncertainty about a PLACE. It does not have a target; it has a location.
	INVESTIGATING,
	## Pursue a credible PLAYER. You investigate a where; you hunt a who.
	HUNTING,
	## End the encounter legibly. The player has to KNOW it is over.
	RETREATING,
	## Stop, because what it was trying to do is not working. It holds still, writes the lead
	## off and goes back to wandering -- see ReconsideringState.
	RECONSIDERING,
}


static func state_name(value: State) -> String:
	match value:
		State.UNALERTED:
			return "unalerted"
		State.INVESTIGATING:
			return "investigating"
		State.HUNTING:
			return "hunting"
		State.RETREATING:
			return "retreating"
		State.RECONSIDERING:
			return "reconsidering"
	return "?"
