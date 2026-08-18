class_name CreatureTouch
extends RefCounted

## Immediate physical interaction (perception.md section 15). Collision-driven.
##
## Touch is the one sense with almost no uncertainty: high strength, high
## confidence, a very small radius. That is the point of it -- it is the sense that
## cannot be fooled, and therefore the one the fiction has to keep short-ranged.
##
## The behavioural inference ("the player is probably hiding in there") belongs to
## Suspicion and Behavior. Touch reports contact and stops.
##
## Pure by construction: the impure part is the Area3D signal wiring, which lives on
## CreaturePerception where the scene tree lives -- the same physics-in-the-scene,
## logic-in-RefCounted split as PerceptionProbe.

var enabled: bool = true
var config: PerceptionConfig = null


## Direct contact. Section 15's worked example, in code.
func perceive_contact(body: Node, contact_position: Vector3, now: float) -> SuspicionEvidence:
	if not enabled or config == null or not config.touch_enabled:
		return null
	# The radius is not zero. Touching something is not the same as knowing its exact
	# centre, and a zero radius is a claim of perfect knowledge that section 31
	# forbids every sense from making.
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.TOUCH,
		contact_position,
		config.touch_uncertainty,
		clampf(config.touch_strength, 0.0, 1.0),
		1.0,
		now
	)
	evidence.source_player = body
	evidence.source_confidence = 1.0
	evidence.category = &"contact"
	return evidence


## Very-short-range proximity sensing: something is close but not touching.
## Degrades with distance, unlike contact.
func perceive_proximity(
	body: Node, body_position: Vector3, distance: float, now: float
) -> SuspicionEvidence:
	if not enabled or config == null or not config.touch_enabled:
		return null
	if config.proximity_detection_range <= 0.0 or distance > config.proximity_detection_range:
		return null

	var nearness: float = clampf(1.0 - distance / config.proximity_detection_range, 0.0, 1.0)
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.TOUCH,
		body_position,
		maxf(config.touch_uncertainty, distance),
		clampf(config.touch_strength * nearness, 0.0, 1.0),
		nearness,
		now
	)
	# Proximity attributes less confidently than contact: something is there, and
	# how sure we are which body it is scales with how close it got.
	evidence.source_player = body
	evidence.source_confidence = nearness
	evidence.category = &"proximity"
	return evidence
