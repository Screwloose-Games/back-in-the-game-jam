class_name SuspicionEvidenceRecord
extends RefCounted

## One remembered observation, decaying on its own schedule (suspicion.md, "Evidence
## Memory").
##
## THIS IS NOT SuspicionEvidence. That name belongs to Perception, which declares it
## at perception/observations/suspicion_evidence.gd as the wire DTO it emits. Godot's
## class_name table is flat and project-wide, so a second declaration is a hard parse
## error at project scan that takes the whole project down -- not a warning. Suspicion
## consumes Perception's type and wraps it in this one.
##
## The split is not just about the name. Perception reports WHAT IT SENSED; how long
## that stays believable is Suspicion's business, so `decay_rate`, `weight`,
## `received_at` and `id` live here and nowhere else.
##
## Decay is measured from `received_at`, on the owning CreatureSuspicion's clock --
## NOT from `observed_at`, which is stamped on Perception's clock. The two clocks both
## start at 0.0 when their node is constructed, so they only agree if the two nodes
## were built on the same frame. Nothing guarantees that, and the failure mode is
## silent: evidence arrives already half-decayed, or with negative age, and the alien
## is subtly deaf for reasons no test would explain. `observed_at` is kept as data.

## What kind of thing happened, as opposed to which sense noticed it. Currently 1:1
## with Sense, and separate anyway because evidence that no sense produces -- a
## Director-injected hint, a tampered-with door found later -- is the obvious next
## entry, and it would have no sense to name.
enum EvidenceType { NOISE, SIGHTING, CONTACT }

## Floor on the kernel width, in metres. A record with zero uncertainty is a delta
## function: it contributes to a point sample only if the sample lands exactly on it,
## which never happens, so the hotspot it belongs to would read as empty and
## get_best_unresolved_location would return its own centre forever.
const MIN_KERNEL_RADIUS: float = 0.5

var id: int = 0
var evidence_type: EvidenceType = EvidenceType.NOISE
var sense: SuspicionEvidence.Sense = SuspicionEvidence.Sense.HEARING

var position: Vector3 = Vector3.ZERO
## Copied from the observation. Suspicion spreads this record's support over this
## radius rather than treating `position` as a fact -- see support_at().
var uncertainty_radius: float = 0.0

var initial_strength: float = 0.0
var confidence: float = 0.0
## Per-sense influence multiplier from SuspicionConfig, resolved at ingest so the
## record stays evaluable without one.
var weight: float = 1.0

## Perception's clock. Data, not the decay origin. See the class docstring.
var observed_at: float = 0.0
## Suspicion's clock, at the moment this was submitted. The decay origin.
var received_at: float = 0.0
## Per-second exponential rate. Half-life is ln(2) / decay_rate.
var decay_rate: float = 0.0

var source_player: Node = null
var source_confidence: float = 0.0
var category: StringName = &""


## Wrap an observation Perception emitted. `p_received_at` is the CONSUMER's clock.
static func from_observation(
	p_id: int, observation: SuspicionEvidence, p_received_at: float, config: SuspicionConfig
) -> SuspicionEvidenceRecord:
	var record := SuspicionEvidenceRecord.new()
	record.id = p_id
	record.sense = observation.sense
	record.evidence_type = type_for_sense(observation.sense)
	record.position = observation.position
	# A zero radius would claim perfect knowledge, which is the one thing Perception
	# exists to avoid saying. Its senses never report zero; a hand-built observation
	# in a test might.
	record.uncertainty_radius = (
		observation.uncertainty_radius
		if observation.uncertainty_radius > 0.0
		else config.default_uncertainty_radius
	)
	record.initial_strength = clampf(observation.strength, 0.0, 1.0)
	record.confidence = clampf(observation.confidence, 0.0, 1.0)
	record.observed_at = observation.observed_at
	record.received_at = p_received_at
	record.decay_rate = config.decay_rate_for(observation.sense)
	record.weight = config.weight_for(observation.sense)
	record.source_player = observation.source_player
	record.source_confidence = clampf(observation.source_confidence, 0.0, 1.0)
	record.category = observation.category
	return record


static func type_for_sense(sense: SuspicionEvidence.Sense) -> EvidenceType:
	match sense:
		SuspicionEvidence.Sense.VISION:
			return EvidenceType.SIGHTING
		SuspicionEvidence.Sense.TOUCH:
			return EvidenceType.CONTACT
		_:
			return EvidenceType.NOISE


## How much this record still contributes at all, ignoring where. Exponential rather
## than linear-to-zero: it never goes negative, never needs clamping, and never has to
## be deleted at an arbitrary timeout -- it just stops mattering, which is what
## suspicion.md asks for under "Effective Evidence Strength".
func effective_strength(now: float) -> float:
	var age: float = maxf(now - received_at, 0.0)
	return initial_strength * confidence * weight * exp(-decay_rate * age)


## This record's contribution AT A POINT. The whole spatial model rests on this.
##
## A noise heard through a wall arrives with a 12 m uncertainty radius and spreads its
## support over a wide, shallow area; a clear sighting arrives with 0.25 m and
## concentrates it. Read `position` and ignore `uncertainty_radius` and the alien gets
## magically precise coordinates for free -- the exact failure perception/README.md
## warns about when it compares the near-drill and far-footstep sandbox shots.
##
## The peak is 1.0 regardless of radius, deliberately. Uncertainty means "somewhere
## around here", not "less happened" -- how much happened is already `strength`, which
## Perception has already attenuated by distance and obstruction. Dividing the peak by
## the radius as well would make a distant drill produce almost no suspicion, and a
## creature that ignores distant drilling is not the creature this is for.
func support_at(point: Vector3, now: float) -> float:
	return effective_strength(now) * spatial_weight(point)


func spatial_weight(point: Vector3) -> float:
	var sigma: float = maxf(uncertainty_radius, MIN_KERNEL_RADIUS)
	var distance: float = position.distance_to(point)
	return exp(-(distance * distance) / (2.0 * sigma * sigma))


func to_dictionary(now: float) -> Dictionary:
	return {
		"id": id,
		"sense": sense,
		"position": position,
		"uncertainty_radius": uncertainty_radius,
		"initial_strength": initial_strength,
		"confidence": confidence,
		"effective_strength": effective_strength(now),
		"age": maxf(now - received_at, 0.0),
		"source_confidence": source_confidence,
		"category": category,
	}
