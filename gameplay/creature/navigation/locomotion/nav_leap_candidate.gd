class_name NavLeapCandidate
extends RefCounted

## One evaluated leap, and when it was rejected, why (navigation.md sections 11, 39).
##
## THE REJECTION REASON IS DATA BECAUSE SECTION 39 ASKS FOR IT ON SCREEN. The leap planner
## is the one part of locomotion whose output is usually "no": most candidates fail, and
## an overlay that draws only the accepted one shows an alien that mysteriously chose to
## crawl. Drawing the rejected trajectories colour-coded by reason turns "why didn't it
## jump?" into a glance.
##
## `crawl_cost` IS CARRIED ALONGSIDE `leap_cost` for the same reason. Section 11.4 wants
## the decision to emerge from a cost comparison rather than a rule, and a comparison you
## cannot see both sides of is a rule with extra steps.

## Why a candidate was not taken. Ordered as they are tested -- cheapest rejection first,
## so most candidates die before anything is cast.
enum Rejection {
	NONE,
	## Section 11.2.1. Not attached, or aimed into the surface being launched from.
	NO_LAUNCH_POSE,
	## Section 11.4. A perfectly good leap that simply loses to walking.
	TOO_EXPENSIVE,
	## Section 11.2.2. The swept body does not fit the whole way.
	BLOCKED_FLIGHT,
	## Section 11.2.3. Nothing grabbable at the far end, so the alien would sail past.
	NO_GRAB,
}

var origin: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var landing_point: Vector3 = Vector3.ZERO
var landing_normal: Vector3 = Vector3.UP
var distance: float = 0.0
var flight_time: float = 0.0
var leap_cost: float = 0.0
## What the same destination costs along the route on foot. Section 11.4's other side.
var crawl_cost: float = 0.0
var accepted: bool = false
var rejection: Rejection = Rejection.NONE
## Which route anchor this candidate was aiming at, or -1 for a fanned destination.
var target_anchor_index: int = -1


static func make(p_origin: Vector3, p_target: Vector3) -> NavLeapCandidate:
	var candidate := NavLeapCandidate.new()
	candidate.origin = p_origin
	candidate.landing_point = p_target
	var offset: Vector3 = p_target - p_origin
	candidate.distance = offset.length()
	if not offset.is_zero_approx():
		candidate.direction = offset.normalized()
	return candidate


## Marks this candidate rejected and returns it, so a planner can `return _reject(c, WHY)`
## in one line and still keep the record for the overlay.
func reject(why: Rejection) -> NavLeapCandidate:
	accepted = false
	rejection = why
	return self


func accept() -> NavLeapCandidate:
	accepted = true
	rejection = Rejection.NONE
	return self


## Section 11.1: zero gravity, so the flight is a straight line at constant speed and the
## velocity is fixed at launch. Nothing recomputes this mid-air -- Invariant 4.
func velocity_at(speed: float) -> Vector3:
	return direction * speed


static func rejection_name(why: Rejection) -> String:
	match why:
		Rejection.NONE:
			return "none"
		Rejection.NO_LAUNCH_POSE:
			return "no_launch_pose"
		Rejection.TOO_EXPENSIVE:
			return "too_expensive"
		Rejection.BLOCKED_FLIGHT:
			return "blocked_flight"
		Rejection.NO_GRAB:
			return "no_grab"
	return "unknown"


func to_dictionary() -> Dictionary:
	return {
		"origin": origin,
		"direction": direction,
		"landing_point": landing_point,
		"landing_normal": landing_normal,
		"distance": distance,
		"flight_time": flight_time,
		"leap_cost": leap_cost,
		"crawl_cost": crawl_cost,
		"accepted": accepted,
		"rejection": rejection_name(rejection),
		"target_anchor_index": target_anchor_index,
	}
