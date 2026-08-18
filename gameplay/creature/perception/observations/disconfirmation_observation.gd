class_name DisconfirmationObservation
extends RefCounted

## "I meaningfully checked this area and found no evidence supporting the current
## hypothesis." (perception.md section 9.)
##
## THIS IS NOT THE SAME AS "NOTHING HAPPENED". Absence of evidence only counts when
## the creature actually looked, which is why `strength` exists: a thorough sweep of
## a dead end reports 0.90 and a glance in passing reports 0.20. Suspicion uses that
## to decide how much unresolved suspicion the search is allowed to clear.
##
## Without this type a searching creature can never rule anywhere out, so it
## re-investigates the same empty hotspot forever.

var position: Vector3 = Vector3.ZERO
## How much space was actually examined, in metres.
var radius: float = 0.0
## How thorough the examination was, 0..1. Scales what Suspicion may clear.
var strength: float = 0.0
## Seconds on the owning CreaturePerception's clock.
var observed_at: float = 0.0
## Bitmask over SuspicionEvidence.Sense -- which senses took part. A region checked
## by hearing alone disconfirms less than one checked by hearing and vision, and
## Suspicion cannot tell those apart without this.
var senses_checked: int = 0


static func make(
	p_position: Vector3,
	p_radius: float,
	p_strength: float,
	p_observed_at: float,
	p_senses_checked: int = 0
) -> DisconfirmationObservation:
	var observation := DisconfirmationObservation.new()
	observation.position = p_position
	observation.radius = p_radius
	observation.strength = p_strength
	observation.observed_at = p_observed_at
	observation.senses_checked = p_senses_checked
	return observation


static func sense_bit(sense: SuspicionEvidence.Sense) -> int:
	return 1 << int(sense)


func has_sense(sense: SuspicionEvidence.Sense) -> bool:
	return (senses_checked & sense_bit(sense)) != 0


func sense_count() -> int:
	var total: int = 0
	for bit: int in [
		sense_bit(SuspicionEvidence.Sense.HEARING),
		sense_bit(SuspicionEvidence.Sense.VISION),
		sense_bit(SuspicionEvidence.Sense.TOUCH),
	]:
		if (senses_checked & bit) != 0:
			total += 1
	return total


func to_dictionary() -> Dictionary:
	return {
		"position": position,
		"radius": radius,
		"strength": strength,
		"observed_at": observed_at,
		"senses_checked": senses_checked,
		"sense_count": sense_count(),
	}
