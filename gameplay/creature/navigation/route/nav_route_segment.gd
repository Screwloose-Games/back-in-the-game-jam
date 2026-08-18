class_name NavRouteSegment
extends RefCounted

## One hop of a planned route (navigation.md section 17's `AlienRouteSegment`).
##
## Carries the edge TYPE forward out of the graph, because that is the one thing the
## local planner cannot re-derive cheaply. Whether a hop needs the body compressed
## (section 10) was decided by a swept cast at bake time; making the locomotion layer
## rediscover it per frame would mean re-casting the same geometry the builder already
## proved.
##
## Segments exist for the attachment hops too -- body to first node, last node to true
## target -- which are not graph edges and have no NavEdge behind them. That is why
## this is a small value type rather than a reference to one.

var from: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO
var type: NavEdge.Type = NavEdge.Type.NORMAL_VOLUME
var distance: float = 0.0


static func make(start: Vector3, end: Vector3, segment_type: NavEdge.Type) -> NavRouteSegment:
	var segment := NavRouteSegment.new()
	segment.from = start
	segment.to = end
	segment.type = segment_type
	segment.distance = start.distance_to(end)
	return segment


## Whether the body must compress to execute this hop (section 10.1).
func requires_squeeze() -> bool:
	return type == NavEdge.Type.WIGGLE
