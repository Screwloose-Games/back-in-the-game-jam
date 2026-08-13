class_name NavKnownEdge
extends RefCounted

## What the alien believes about one connection (navigation.md sections 27, 40.2).
##
## Carries the same copies-not-lookups design as NavKnownNode, and for the same reason: a
## believed edge has to be able to disagree with the real one.
##
## `questionable` IS SEPARATE FROM `state` ON PURPOSE. Section 40.2's crevice grinding is
## not a contradiction -- nothing observed says the passage is gone, and it may well be
## perfectly traversable on a better approach. It is a note that trying this cost the
## alien something, and it should prefer the other way if there is one. Folding it into
## STALE would make a failed squeeze indistinguishable from a wall appearing where a
## tunnel used to be, and section 29 wants those investigated differently.

var from_id: int = -1
var to_id: int = -1
var type: NavEdge.Type = NavEdge.Type.NORMAL_VOLUME
var distance: float = 0.0
var min_clearance: float = 0.0
## The remembered cost in seconds. What the alien plans against, not what is true.
var base_cost: float = 0.0

var state: NavKnowledgeState.State = NavKnowledgeState.State.UNKNOWN
var confidence: float = 0.0
var last_observed_time: float = 0.0
var known_terrain_revision: int = 0
## Section 40.2. Tried and did not work; not disproven.
var questionable: bool = false


static func make(edge: NavEdge, p_state: NavKnowledgeState.State, now: float) -> NavKnownEdge:
	var known := NavKnownEdge.new()
	known.from_id = edge.from_id
	known.to_id = edge.to_id
	known.type = edge.type
	known.distance = edge.distance
	known.min_clearance = edge.min_clearance
	known.base_cost = edge.base_cost
	known.state = p_state
	known.last_observed_time = now
	known.confidence = 1.0 if p_state == NavKnowledgeState.State.KNOWN else 0.5
	return known


func is_routable() -> bool:
	return NavKnowledgeState.is_routable(state)


## What this edge costs the alien to plan through, given how much it trusts it.
##
## A DOUBTED ROUTE IS EXPENSIVE, NOT FORBIDDEN, and section 43's Scenario J is why. An
## alien that refuses every route it is unsure of stands still in a cave it has half
## forgotten; one that prefers what it knows but will still try a doubted way when that is
## all there is reads as an animal rather than as a lookup failure.
func planning_cost(config: NavigationConfig) -> float:
	var cost: float = base_cost
	if state == NavKnowledgeState.State.STALE:
		cost *= config.stale_edge_cost_multiplier
	if questionable:
		cost *= config.stale_edge_cost_multiplier
	return cost


func to_dictionary() -> Dictionary:
	return {
		"from_id": from_id,
		"to_id": to_id,
		"type": NavEdge.type_name(type),
		"state": NavKnowledgeState.state_name(state),
		"confidence": confidence,
		"questionable": questionable,
		"base_cost": base_cost,
	}
