class_name NavKnowledgeState
extends RefCounted

## How well the alien knows one piece of terrain (navigation.md section 27).
##
## A holder for one enum, for the same reason NavLocomotion is: GDScript has no
## free-standing enums, duplicating it per file makes two sources of truth, and hanging it
## off the knowledge graph means the records have to import their own container to name
## their own state.
##
## THE SIX STATES ARE NOT A CONFIDENCE SCALE. Confidence is a separate float that decays;
## these describe the KIND of belief, and two of them exist specifically so the alien can
## be wrong in a way it can act on. SUSPECTED is somewhere it has noticed and not been --
## section 40.6's newly discovered opening, which must not be routed through. STALE is
## somewhere it believed it knew and has been contradicted, which section 29 wants
## inspected rather than silently corrected.

enum State {
	## Never observed. The default for everything, and not the same as empty.
	UNKNOWN,
	## Noticed but not visited. Section 40.6: NOT routable, however inviting it looks.
	SUSPECTED,
	## Observed at a distance or in passing. Routable, at the remembered cost.
	PARTIALLY_EXPLORED,
	## Been there. Routable and trusted.
	KNOWN,
	## Believed known, then contradicted. Still routable, deliberately -- see the note on
	## `stale_edge_cost_multiplier`. An alien that refuses everything it doubts stands
	## still in a cave it has half-forgotten.
	STALE,
	## Confirmed gone. Not routable, and nothing in phases 1-8 produces it: reaching this
	## state requires an observation that terrain the alien remembers is now solid AND an
	## inspection that agrees, which is section 29's chain.
	INVALID,
}


static func state_name(state: State) -> String:
	match state:
		State.UNKNOWN:
			return "unknown"
		State.SUSPECTED:
			return "suspected"
		State.PARTIALLY_EXPLORED:
			return "partially_explored"
		State.KNOWN:
			return "known"
		State.STALE:
			return "stale"
		State.INVALID:
			return "invalid"
	return "unknown"


## Whether a record in this state may appear in a projected graph.
##
## SECTION 40.6 LIVES HERE, as one branch rather than as a guard clause somebody has to
## remember to write. A SUSPECTED opening is not projected, so it is literally unroutable
## no matter what the planner tries -- "do not instantaneously route through it" becomes a
## property of the data structure instead of a rule.
static func is_routable(state: State) -> bool:
	return state == State.KNOWN or state == State.PARTIALLY_EXPLORED or state == State.STALE
