class_name SuspicionEvidence
extends RefCounted

## Positive evidence of meaningful activity, produced by one sense (perception.md
## section 8).
##
## Perception supplies the observation. SUSPICION DECIDES WHAT IT MEANS -- how long
## it persists, how much it contributes, whether it is worth investigating. Nothing
## here is a conclusion, which is why there is no `is_player`, no `threat_level` and
## no `should_investigate`.
##
## `strength` and `confidence` are different axes and mixing them is the easy
## mistake. A loud noise through a wall is HIGH strength and LOW confidence; a
## glimpse of a player at the edge of the vision cone is low strength and high
## confidence. Suspicion needs both to tell "something big happened somewhere over
## there" apart from "I definitely saw a small thing".
##
## This name is shared with the Suspicion module by design -- Godot's global class
## table is flat, so Suspicion's internal decaying record must be a different type
## (SuspicionEvidenceRecord). See the module README.

enum Sense { HEARING, VISION, TOUCH }

var sense: Sense = Sense.HEARING
## Best estimate of where the activity was. Meaningless without uncertainty_radius.
var position: Vector3 = Vector3.ZERO
## How wrong `position` might be, in metres. A weak or distant observation reports a
## LARGER radius rather than a wrong-but-confident point -- that is what lets
## Suspicion reason about areas instead of magically precise coordinates.
var uncertainty_radius: float = 0.0
## How much happened, 0..1.
var strength: float = 0.0
## How sure the sense is that anything happened at all, 0..1.
var confidence: float = 0.0
## Seconds on the owning CreaturePerception's clock. Not wall time -- see
## CreaturePerception.advance().
var observed_at: float = 0.0
## The player this is believed to be, when the sense can attribute it. Hearing
## normally leaves this null: a noise is a noise.
var source_player: Node = null
## How sure the attribution is, 0..1. Separate from `confidence`, which is about the
## observation existing at all.
var source_confidence: float = 0.0
## Pass-through tag from the originating NoiseEvent, or the sense's own label.
var category: StringName = &""


static func make(
	p_sense: Sense,
	p_position: Vector3,
	p_uncertainty_radius: float,
	p_strength: float,
	p_confidence: float,
	p_observed_at: float
) -> SuspicionEvidence:
	var evidence := SuspicionEvidence.new()
	evidence.sense = p_sense
	evidence.position = p_position
	evidence.uncertainty_radius = p_uncertainty_radius
	evidence.strength = p_strength
	evidence.confidence = p_confidence
	evidence.observed_at = p_observed_at
	return evidence


## A deep-enough copy: every value field is duplicated, and the two Node references
## are shared because a copy of a Node is not a thing.
##
## Consumers hold observations for as long as they like, so handing the same
## instance to two subscribers means the second one can mutate what the first is
## still reading. The debug overlay keeps a decaying ring buffer of these.
func duplicate_evidence() -> SuspicionEvidence:
	var copy := SuspicionEvidence.new()
	copy.sense = sense
	copy.position = position
	copy.uncertainty_radius = uncertainty_radius
	copy.strength = strength
	copy.confidence = confidence
	copy.observed_at = observed_at
	copy.source_player = source_player
	copy.source_confidence = source_confidence
	copy.category = category
	return copy


func sense_name() -> String:
	match sense:
		Sense.HEARING:
			return "HEARING"
		Sense.VISION:
			return "VISION"
		_:
			return "TOUCH"


func to_dictionary() -> Dictionary:
	return {
		"sense": sense_name(),
		"position": position,
		"uncertainty_radius": uncertainty_radius,
		"strength": strength,
		"confidence": confidence,
		"observed_at": observed_at,
		"source_confidence": source_confidence,
		"category": category,
	}
