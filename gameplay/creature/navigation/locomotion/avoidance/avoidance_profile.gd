class_name AvoidanceProfile
extends Resource

## Every number `avoidance/` steers by (navigation.md sections 8.1, 9.2, 21).

## THE KNOBS LIVE WITH THE CODE THEY TUNE. These were four entries in a forty-field
## `LocomotionProfile`, between the crawl weights and the wiggle timings, and a retune of
## avoidance meant knowing which four of the forty were the avoidance ones. A body that
## drifts off its wall and a body that corners into one are the same subsystem
## misconfigured, and now they are the same resource.
##
## THE `crawl_` AND `tunnel_` PREFIXES ARE GONE BECAUSE THEY WERE WRONG. `hold_distance`
## was named `crawl_hold_distance` and is read by the swimmer's exit pull;
## `retry_attempts` was named `tunnel_avoid_attempts` and counts re-asks of the solver,
## not anything about tunnels. Nested under `LocomotionProfile.avoidance`, the prefix the
## old names were reaching for is now the path.
##
## A bare `AvoidanceProfile.new()` is fully usable, like the other two profiles -- the
## shipped defaults are the ones the demo cave was tuned against.

## How close terrain has to be before steering treats it as something to avoid.
##
## Read off the same fan `NavSurfaceField` already takes, so this costs no rays -- see
## `NavAvoidance`. Deliberately its own number rather than a reuse of
## `tunnel_enclosure_reach`, which happens to share this value today and answers the
## unrelated question of whether the body is in a tunnel at all.
@export_range(0.2, 20.0, 0.1, "or_greater", "suffix:m") var margin: float = 3.0
## The stand-off a body tries to keep from the surface it is holding (section 8.1).
##
## MUST SIT BETWEEN THE BODY'S OWN ENVELOPE AND ITS REACH, and the two enclosing profiles
## assert one end each because either mistake is fatal and silent. Below
## `ClearanceProfile.normal_clearance()` -- checked by `NavigationConfig`, which is the
## only place that can see both resources -- the body adheres into its own collision
## radius and every swept cast fails from the origin overlap. Above
## `crawl_surface_reach - crawl_step_distance`, checked by `LocomotionProfile`, a body at
## the hold distance can still step out of reach in one tick, which is the drift this
## exists to stop.
@export_range(0.1, 12.0, 0.1, "or_greater", "suffix:m") var hold_distance: float = 1.6
## Fraction of the excess distance adhesion closes per step. At 1 the body snaps back to
## the hold distance in a single tick and reads as magnetic; at 0 adhesion is off and the
## alien drifts off its surface until the fan goes blind.
@export_range(0.0, 1.0, 0.05) var adhesion_gain: float = 0.6
## How many progressively firmer avoidance corrections the swimmer tries before handing the
## tick back. The swim mode has no fan of alternatives to fall back on -- one blocked cast
## used to be the end of it -- so this is where its second opinion comes from.
@export_range(1, 8, 1) var retry_attempts: int = 3


## The checks that need only this resource. The two that span it and its neighbours are
## in `LocomotionProfile` and `NavigationConfig`, because those are the only places that
## can see both sides of them.
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if margin <= 0.0:
		failures.append("avoidance.margin must be positive, or nothing is ever avoided")
	if hold_distance <= 0.0:
		failures.append("avoidance.hold_distance must be positive")
	if retry_attempts < 1:
		failures.append("avoidance.retry_attempts must be at least 1")
	return failures
