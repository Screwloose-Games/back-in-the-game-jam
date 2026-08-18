class_name NavNode
extends RefCounted

## One navigation anchor (navigation.md section 12.3).
##
## A NODE IS NOT A WAYPOINT THE BODY MUST PASS THROUGH (section 2.2, Invariant 1). It
## is a place the topology is known to be open. Decimation deliberately keeps the
## highest-clearance candidate in each neighbourhood, so in a large chamber the node
## sits near the middle of the empty space while the alien will normally be crawling
## along a wall six metres away. Code that steers the body at `position` rather than
## treating it as a routing anchor produces an alien that leaves the wall to visit the
## centre of every room it crosses.
##
## Nodes carry no semantic label -- no "room", no "tunnel", no "junction" (section
## 12.3). Everything the higher layers need is derivable from `clearance` and the edges
## that survived validation, and a label would be a second source of truth that goes
## stale the moment the player mines.
##
## Section 12.3 also lists `nearby_surface_data`, calculated lazily. It is not declared
## here: it has no reader until surface crawl lands in Phase 3, and an always-empty
## field invites callers to branch on it.

var id: int = -1
var position: Vector3 = Vector3.ZERO
## Free radius measured at `position` (section 5.1), capped at
## NavigationConfig.clearance_ceiling.
##
## APPROXIMATE ON PURPOSE. It ranks candidates and feeds the section 14 comfort term;
## it never decides whether an edge exists. That is the swept shape cast's job, and
## section 5.1 says so.
var clearance: float = 0.0
## Section 25 chunk this node falls in, for local patching and the overlay.
var chunk_id: Vector3i = Vector3i.ZERO


static func make(node_id: int, at: Vector3, free_radius: float, chunk: Vector3i) -> NavNode:
	var node := NavNode.new()
	node.id = node_id
	node.position = at
	node.clearance = free_radius
	node.chunk_id = chunk
	return node


## Which section 25 chunk a world position belongs to.
static func chunk_of(at: Vector3, chunk_size: float) -> Vector3i:
	return Vector3i((at / chunk_size).floor())
