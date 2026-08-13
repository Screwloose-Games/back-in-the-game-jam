class_name CreatureVision
extends RefCounted

## Evaluates KNOWN candidate targets for visibility (perception.md section 13).
##
## Sampled periodically rather than event-driven, and gated on alertness -- section
## 14's "low suspicion: vision disabled" is a real state this class supports, not a
## degraded one. `enabled = false` must change nothing anywhere else in the AI.
##
## Vision evaluates candidates it is HANDED. It never searches the world for
## objects, which is what keeps the per-scan cost proportional to the number of
## players rather than to the size of the cave.
##
## Named `CreatureVision` rather than the doc's `Vision`: `Vision` is a plausible
## name for a post-process or camera effect in this project, and a class_name
## collision is a project-wide parse failure. See the module README.

## Visibility multiplier at the very edge of the cone, relative to dead centre.
## Not zero: a target at the rim is seen worse, not not-at-all, and a hard zero at
## the boundary makes the cone edge behave like a wall.
const CONE_EDGE_FALLOFF: float = 0.5
## Visibility multiplier at maximum range, relative to point blank.
const RANGE_EDGE_FALLOFF: float = 0.25
## Confidence of a sighting at the visibility floor. Seeing anything at all is
## fairly conclusive, so this does not start near zero the way hearing's does.
const MIN_SIGHTING_CONFIDENCE: float = 0.6

var enabled: bool = true
var config: PerceptionConfig = null


## cos of the angle between where the creature faces and where the target is.
## 1.0 dead ahead, 0.0 abeam, -1.0 behind. Compared against cos(half_angle) so no
## acos is ever needed.
static func cone_alignment(forward: Vector3, to_target: Vector3) -> float:
	if forward.length_squared() <= 0.0 or to_target.length_squared() <= 0.0:
		return 0.0
	return forward.normalized().dot(to_target.normalized())


## How well the target can be seen, 0..1. ZERO MEANS NOT SEEN.
##
## Every geometric rejection collapses into this one number rather than being an
## early return in evaluate_target(). Two reasons, and the second is the real one:
## gdlint caps a function at six returns and the natural shape of "disabled? out of
## range? out of cone? no LOS? too dim? ok" sits exactly on the limit with no
## headroom -- and a rejection reason expressed as a float is directly assertable in
## a test, where `null` tells you only that something failed.
static func visibility(
	distance: float, alignment: float, has_los: bool, light_level: float, config: PerceptionConfig
) -> float:
	if config == null or not has_los:
		return 0.0
	if config.vision_range <= 0.0 or config.vision_angle <= 0.0:
		return 0.0
	if distance > config.vision_range:
		return 0.0
	var min_alignment: float = cos(config.vision_angle * 0.5)
	if alignment < min_alignment:
		return 0.0

	var reach: float = clampf(distance / config.vision_range, 0.0, 1.0)
	var range_term: float = lerpf(1.0, RANGE_EDGE_FALLOFF, reach)
	var cone_spread: float = 1.0 - min_alignment
	var cone_term: float = 1.0
	if cone_spread > 0.0:
		var centredness: float = clampf((alignment - min_alignment) / cone_spread, 0.0, 1.0)
		cone_term = lerpf(CONE_EDGE_FALLOFF, 1.0, centredness)
	return clampf(range_term * cone_term * clampf(light_level, 0.0, 1.0), 0.0, 1.0)


## Which candidates to evaluate. An explicitly wired list always wins; the group is
## the fallback so a level can drop a creature in without wiring anything.
static func choose_targets(explicit: Array[Node3D], from_group: Array[Node3D]) -> Array[Node3D]:
	if not explicit.is_empty():
		return explicit
	return from_group


## `target_position` is passed in rather than read off the node, so this is callable
## on a target that is not in the scene tree. Node3D.global_position needs a tree,
## and requiring one here would push every vision test into the slow suite.
func evaluate_target(
	target: Node3D,
	target_position: Vector3,
	eye: Transform3D,
	has_los: bool,
	light_level: float,
	now: float
) -> SuspicionEvidence:
	if not enabled or config == null or not config.vision_enabled:
		return null
	var to_target: Vector3 = target_position - eye.origin
	var distance: float = to_target.length()
	var seen: float = visibility(
		distance, cone_alignment(-eye.basis.z, to_target), has_los, light_level, config
	)
	if seen < config.vision_min_visibility or seen <= 0.0:
		return null

	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION,
		target_position,
		lerpf(config.vision_max_uncertainty, config.vision_min_uncertainty, seen),
		seen,
		lerpf(MIN_SIGHTING_CONFIDENCE, 1.0, seen),
		now
	)
	# Vision DOES attribute -- unlike hearing. Seeing a thing is what tells you which
	# thing it was. Section 8's vision example names Player 1 at confidence .98.
	evidence.source_player = target
	evidence.source_confidence = seen
	evidence.category = &"sighting"
	return evidence
