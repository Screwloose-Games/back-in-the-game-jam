class_name NavRoute
extends RefCounted

## The result of a global path query (navigation.md section 17).
##
## THE ANCHORS ARE NOT WAYPOINTS THE BODY MUST VISIT (sections 2.2, 15, Invariant 1).
## They are "topological route anchors" -- an ordered list of places the topology is
## known to connect. In a large chamber the anchor sits near the middle of the empty
## space because decimation kept the highest-clearance candidate there, while the alien
## will normally be crawling along a wall. Steering at these points produces an alien
## that detours to the centre of every room it crosses.
##
## `anchors[0]` is the querying body's own position and `anchors[-1]` is the true target
## when the route is COMPLETE, so the polyline runs end to end rather than starting and
## stopping at graph nodes. Both of those hops were proved by the same swept cast
## section 16 uses for attachment, which is why they are safe to include and why they
## have segments like every other hop.
##
## A PARTIAL ROUTE IS THE NORMAL FAILURE, NOT AN ERROR (sections 17, 40.4). "A partial
## route should terminate at the nearest useful reachable location rather than produce
## an empty path whenever possible" -- an alien that stops dead because the player is
## behind a wall it cannot pass reads as broken; one that moves to the closest place it
## can reach and then looks around reads as an animal.

enum Status { COMPLETE, PARTIAL, UNREACHABLE }

## Body position, then graph nodes, then the true target if COMPLETE.
var anchors := PackedVector3Array()
## One per consecutive anchor pair, so `segments.size() == anchors.size() - 1`.
var segments: Array[NavRouteSegment] = []
## Graph nodes the route passes through, without the two attachment endpoints. Empty
## for UNREACHABLE.
var node_ids := PackedInt32Array()
## Where the caller ASKED to go, which is not `anchors[-1]` on a partial route. The
## difference is what the behaviour layer needs to decide whether to keep trying.
var target_position: Vector3 = Vector3.ZERO
var status: Status = Status.UNREACHABLE
## Seconds, summed from the traversed edges. Zero for the attachment hops, which have
## no baked cost. Comparable between routes, which is what section 35 needs to choose
## probabilistically among plausible alternatives.
var cost: float = 0.0


static func unreachable(target: Vector3) -> NavRoute:
	var route := NavRoute.new()
	route.target_position = target
	route.status = Status.UNREACHABLE
	return route


func is_usable() -> bool:
	return status != Status.UNREACHABLE and anchors.size() >= 2


## Whether any hop needs the body compressed. The behaviour layer reads this to decide
## whether a route is worth the exposure before committing to it.
func requires_squeeze() -> bool:
	for segment: NavRouteSegment in segments:
		if segment.requires_squeeze():
			return true
	return false


func status_name() -> String:
	match status:
		Status.COMPLETE:
			return "complete"
		Status.PARTIAL:
			return "partial"
	return "unreachable"
