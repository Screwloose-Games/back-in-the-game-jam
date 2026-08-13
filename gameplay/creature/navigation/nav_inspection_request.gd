class_name NavInspectionRequest
extends RefCounted

## "Something here does not match what I expected -- go and look" (navigation.md
## section 30).
##
## NAVIGATION ISSUES THE REQUEST AND NOTHING ELSE. Section 30 is explicit that the
## behaviour and animation systems decide what an inspection looks like -- stopping,
## orienting, probing with tentacles, cautiously entering -- and that navigation's only
## job is to say where and why. When inspection completes, the knowledge system is told
## what it may now learn.
##
## The delay this creates is the feature, not a cost (section 29). An alien that
## instantly absorbs authoritative geometry and reroutes is indistinguishable from an
## omniscient one, however carefully the graph underneath it was separated. Scenario J
## fails on exactly that: the player expects to watch the creature notice.
##
## ONLY ONE EMITTER EXISTS IN PHASES 1-2 -- CreatureNavigation, when a plan comes back
## PARTIAL or UNREACHABLE. Sections 29's geometry-mismatch detection and 40.2's
## crevice-grinding abort are the other two callers the spec names, and both need
## locomotion (Phase 3+) to detect their trigger. The type exists now so those land as
## an emit rather than as a new contract.

enum Reason { UNKNOWN_OPENING, GEOMETRY_MISMATCH, STALE_ROUTE, FAILED_TRAVERSAL }

var position: Vector3 = Vector3.ZERO
var reason: Reason = Reason.GEOMETRY_MISMATCH
## Section 25 chunk, so a consumer can invalidate cached local geometry without
## recomputing which chunk a point falls in.
var affected_chunk: Vector3i = Vector3i.ZERO


static func make(at: Vector3, why: Reason, chunk_size: float) -> NavInspectionRequest:
	var request := NavInspectionRequest.new()
	request.position = at
	request.reason = why
	request.affected_chunk = NavNode.chunk_of(at, chunk_size)
	return request


static func reason_name(why: Reason) -> String:
	match why:
		Reason.UNKNOWN_OPENING:
			return "unknown_opening"
		Reason.GEOMETRY_MISMATCH:
			return "geometry_mismatch"
		Reason.STALE_ROUTE:
			return "stale_route"
		Reason.FAILED_TRAVERSAL:
			return "failed_traversal"
	return "unknown"
