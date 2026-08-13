class_name SuspicionDisconfirmation
extends RefCounted

## "The creature adequately checked this area and found nothing." Suspicion's own
## decaying copy of a DisconfirmationObservation (suspicion.md, "Investigation State").
##
## THIS IS A RECORD, NOT A `searched` FLAG, and the spec is emphatic about the
## difference. A flag is permanent; this expires at `recovery_rate`, so an area the
## creature swept clean twenty seconds ago slowly becomes worth reconsidering. A
## creature that can permanently rule places out eventually rules out the whole level
## and stands still.
##
## What it reduces is CURRENT LOCAL SUSPICION -- "whatever made that noise is probably
## still here" -- never the historical fact that a noise happened. That is why
## disconfirmation is stored alongside evidence and subtracted at query time, rather
## than being allowed to delete or weaken the evidence records themselves.
##
## Decay runs from `received_at` on Suspicion's clock, for the same reason
## SuspicionEvidenceRecord's does. See that file.

var id: int = 0

var position: Vector3 = Vector3.ZERO
var radius: float = 0.0

## Already scaled by how many senses took part. See from_observation().
var strength: float = 0.0

## Perception's clock. Data.
var observed_at: float = 0.0
## Suspicion's clock, at submission. The decay origin.
var received_at: float = 0.0
## Per-second exponential rate at which a searched area becomes interesting again.
var recovery_rate: float = 0.0

## Bitmask over SuspicionEvidence.Sense, carried through from the observation. Kept
## for the overlay and for debugging; the magnitude it implies is already folded into
## `strength`.
var evidence_mask: int = 0


## Wrap an observation Perception emitted.
##
## `strength` is scaled by how many senses actually took part, which is what
## DisconfirmationObservation's bitmask is for: a region checked by hearing alone
## clears less than one checked by hearing and vision. An aborted scan arrives at
## strength 0.0 and stays there -- it reached FINISHED so Behavior would not hang, but
## it never looked, and it must clear nothing.
static func from_observation(
	p_id: int,
	observation: DisconfirmationObservation,
	p_received_at: float,
	config: SuspicionConfig
) -> SuspicionDisconfirmation:
	var record := SuspicionDisconfirmation.new()
	record.id = p_id
	record.position = observation.position
	record.radius = observation.radius
	record.strength = (
		clampf(observation.strength, 0.0, 1.0)
		* config.disconfirmation_sense_scale(observation.sense_count())
		* config.disconfirmation_strength_multiplier
	)
	record.observed_at = observation.observed_at
	record.received_at = p_received_at
	record.recovery_rate = config.searched_area_recovery_rate
	record.evidence_mask = observation.senses_checked
	return record


func effective_strength(now: float) -> float:
	var age: float = maxf(now - received_at, 0.0)
	return strength * exp(-recovery_rate * age)


## How thoroughly this search covered a given point: full at the centre, nothing at
## the edge.
##
## Falling off rather than being a hard sphere is what makes the spec's worked example
## work -- searching one side of a hotspot leaves the far side almost untouched, so
## get_best_unresolved_location moves there instead of declaring the whole hotspot
## resolved.
func coverage_at(point: Vector3) -> float:
	if radius <= 0.0:
		return 0.0
	var normalized: float = position.distance_to(point) / radius
	if normalized >= 1.0:
		return 0.0
	return 1.0 - normalized * normalized


## How much this search suppresses belief at a point, right now.
func suppression_at(point: Vector3, now: float) -> float:
	return effective_strength(now) * coverage_at(point)


func to_dictionary(now: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"radius": radius,
		"strength": strength,
		"effective_strength": effective_strength(now),
		"age": maxf(now - received_at, 0.0),
		"evidence_mask": evidence_mask,
	}
