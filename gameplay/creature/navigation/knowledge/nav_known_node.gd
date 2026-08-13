class_name NavKnownNode
extends RefCounted

## What the alien believes about one navigation node (navigation.md section 27).
##
## IT STORES COPIES OF `position` AND `clearance`, NOT LOOKUPS, AND THAT IS THE WHOLE
## DESIGN. A record holding only a world node id would have to read the geometry back off
## the authoritative graph, which means the alien would silently see the world's CURRENT
## shape through its own memory -- and stale knowledge would be unrepresentable, because
## there would be nowhere for a wrong belief to live. Copying is what makes Invariant 9
## mechanical rather than aspirational: what the alien believes is stored, so it can
## differ, so it can be wrong.
##
## The id is still carried, because section 27 keys memory by world node id and a route
## planned against a believed graph has to name nodes the world graph would recognise.
## That is also why a rebake is so destructive to knowledge and a patch is not.

var world_node_id: int = -1
var state: NavKnowledgeState.State = NavKnowledgeState.State.UNKNOWN
## 0..1. Decays with time, drops on contradiction, rises on observation.
var confidence: float = 0.0
## On the knowledge holder's clock, not perception's -- see NavKnowledgeGraph.
var last_observed_time: float = 0.0
## Section 25. Which revision of its chunk this belief was formed against, so "my memory
## predates the change" is answerable without re-observing anything.
var known_terrain_revision: int = 0

## The BELIEVED geometry. Allowed to be wrong; that is the point.
var position: Vector3 = Vector3.ZERO
var clearance: float = 0.0


static func make(node: NavNode, p_state: NavKnowledgeState.State, now: float) -> NavKnownNode:
	var known := NavKnownNode.new()
	known.world_node_id = node.id
	known.state = p_state
	known.position = node.position
	known.clearance = node.clearance
	known.last_observed_time = now
	known.confidence = 1.0 if p_state == NavKnowledgeState.State.KNOWN else 0.5
	return known


## A node the alien has noticed but not visited. Section 40.6: never routable.
static func suspected(at: Vector3, now: float) -> NavKnownNode:
	var known := NavKnownNode.new()
	known.state = NavKnowledgeState.State.SUSPECTED
	known.position = at
	known.last_observed_time = now
	known.confidence = 0.25
	return known


func is_routable() -> bool:
	return NavKnowledgeState.is_routable(state)


func to_dictionary() -> Dictionary:
	return {
		"world_node_id": world_node_id,
		"state": NavKnowledgeState.state_name(state),
		"confidence": confidence,
		"last_observed_time": last_observed_time,
		"known_terrain_revision": known_terrain_revision,
		"position": position,
		"clearance": clearance,
	}
