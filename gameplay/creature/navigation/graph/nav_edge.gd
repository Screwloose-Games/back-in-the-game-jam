class_name NavEdge
extends RefCounted

## A validated connection between two nodes (navigation.md section 13.3).
##
## An edge exists only because a SWEPT COLLISION SHAPE got from one node to the other
## (section 13.2). Never because a raycast did -- a ray is a zero-radius body and will
## happily thread a two-metre alien through a ten-centimetre crack.
##
## THE TWO TYPES ARE THE WHOLE OF INVARIANT 5. A passage the normal body clears is
## NORMAL_VOLUME; one only the compressed body clears is WIGGLE; one neither clears
## produces NO EDGE AT ALL, which is how a player-only tunnel excludes the alien
## without a single flag, marker or special case (sections 10.3, 13.2, Scenario G).
##
## LEAP IS DELIBERATELY ABSENT (sections 11.3, 13.3). Baking leaps as edges is an
## O(n^2) set of permanent connections across every open sightline in the cave, and it
## would also assert something the graph is not allowed to assert -- that unsupported
## flight between two points is executable. Leaps are queried by the local planner at
## the moment of use, in Phase 6.
##
## Surface crawl versus tunnel swim is likewise not encoded (section 13.3). Both
## consume a NORMAL_VOLUME edge and the choice is local geometry's, made at execution
## time.

enum Type { NORMAL_VOLUME, WIGGLE }

var from_id: int = -1
var to_id: int = -1
var type: Type = Type.NORMAL_VOLUME
var distance: float = 0.0
## The tighter of the two endpoint clearances. Feeds the section 14 comfort term.
##
## An endpoint sample, NOT the true minimum along the edge -- measuring that would mean
## the dense clearance field this module deliberately does not build. It is a hint for
## cost only; the swept cast already proved the body fits the whole way.
var min_clearance: float = 0.0
## Seconds, per section 14. See NavigationConfig for why the unit matters.
var base_cost: float = 0.0


static func make(
	from: int, to: int, edge_type: Type, length: float, clearance: float, cost: float
) -> NavEdge:
	var edge := NavEdge.new()
	edge.from_id = from
	edge.to_id = to
	edge.type = edge_type
	edge.distance = length
	edge.min_clearance = clearance
	edge.base_cost = cost
	return edge


## The endpoint that is not `id`. Edges are stored once and read from both directions.
func other(id: int) -> int:
	return to_id if id == from_id else from_id


static func type_name(edge_type: Type) -> String:
	return "wiggle" if edge_type == Type.WIGGLE else "normal_volume"
