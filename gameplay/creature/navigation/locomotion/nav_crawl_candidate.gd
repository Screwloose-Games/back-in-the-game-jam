class_name NavCrawlCandidate
extends RefCounted

## One scored direction the crawler considered this tick (navigation.md section 21).
##
## KEPT AS A RECORD RATHER THAN COLLAPSED TO A FLOAT, for two reasons that are both about
## being able to see what happened. Section 39 requires the overlay to draw what the
## locomotion layer wanted, and a fan of scored arrows is the only picture of a steering
## decision that means anything. And a test that can only assert the winner can tell you
## the alien turned the wrong way, but not which of six weighted terms was responsible.

var direction: Vector3 = Vector3.ZERO
## Where this direction would put the body, one `crawl_step_distance` along.
var step_point: Vector3 = Vector3.ZERO
## Surface found under the step point, or a miss. A miss is what disqualifies a
## direction: section 8.2 says an unreachable surface means considering a leap instead.
var surface: NavSurfaceSample = null

var goal_alignment: float = 0.0
var surface_quality: float = 0.0
var clearance_score: float = 0.0
var orientation_continuity: float = 0.0
var turning_penalty: float = 0.0
var collision_penalty: float = 0.0
var score: float = 0.0
## Set once a swept cast has actually been paid for. Only the shortlist is proven, so an
## unvalidated candidate carries the geometry's opinion and not the physics server's.
var validated: bool = false


static func make(
	p_direction: Vector3, p_step_point: Vector3, p_surface: NavSurfaceSample
) -> NavCrawlCandidate:
	var candidate := NavCrawlCandidate.new()
	candidate.direction = p_direction
	candidate.step_point = p_step_point
	candidate.surface = p_surface
	return candidate


func to_dictionary() -> Dictionary:
	return {
		"direction": direction,
		"step_point": step_point,
		"hit": surface != null and surface.hit,
		"goal_alignment": goal_alignment,
		"surface_quality": surface_quality,
		"clearance_score": clearance_score,
		"orientation_continuity": orientation_continuity,
		"turning_penalty": turning_penalty,
		"collision_penalty": collision_penalty,
		"score": score,
		"validated": validated,
	}
