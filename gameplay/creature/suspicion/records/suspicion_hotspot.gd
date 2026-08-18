class_name SuspicionHotspot
extends RefCounted

## A place the creature currently considers worth attention (suspicion.md, "Hotspot
## State").
##
## Hotspots are DERIVED, but they are not disposable. Position, radius and suspicion
## are recomputed from the live evidence on every update, while `id` survives across
## those recomputes -- matched by shared contributing evidence -- because
## `hotspot_created` / `hotspot_updated` / `hotspot_resolved` mean nothing if the id
## changes every tick. A listener would see one continuous suspicion rebuilt from
## scratch five times a second.
##
## Several of these exist at once, on purpose. The creature does not have to forget
## the eastern tunnel because the generator room just got interesting; that is the
## difference between this and a `last_noise_position` variable.
##
## Nothing here is stored per-sample. Which parts of the hotspot have been searched is
## answered from the disconfirmation records at query time (see
## CreatureSuspicion.get_best_unresolved_location), so a moving or growing hotspot
## cannot drag stale "already searched" marks around with it.

var id: int = 0

## Weighted estimate from the contributing evidence, smoothed toward its target so a
## new loud noise MOVES the hotspot rather than teleporting it.
var position: Vector3 = Vector3.ZERO
var radius: float = 0.0

## 0..1, saturating. How much the creature currently cares about this place.
var suspicion: float = 0.0
## 0..1. How sure it is that anything is here at all -- the confidence-weighted mean
## of the contributors. Distinct from `suspicion`: a single loud unattributed bang is
## high suspicion at low confidence.
var confidence: float = 0.0

var created_at: float = 0.0
var last_updated_at: float = 0.0

var contributing_evidence_ids: Array[int] = []

## The player this is probably about, or null while it is still anonymous. Moves
## toward a contributor's attribution at SuspicionConfig.source_association_gain, so
## an anonymous hotspot can become "probably Player 1" once a sighting lands in it.
var likely_source: Node = null
var source_confidence: float = 0.0

## 0..1. How much of this hotspot's raw support has been searched away. Derived from
## the disconfirmation records each update -- NOT a counter Behavior increments, which
## would let Behavior declare a place searched without looking.
var investigation_progress: float = 0.0


## Consumers are handed the live object. Take a copy if you intend to hold one past
## the current frame -- otherwise it mutates under you on the next update.
func duplicate_hotspot() -> SuspicionHotspot:
	var copy := SuspicionHotspot.new()
	copy.id = id
	copy.position = position
	copy.radius = radius
	copy.suspicion = suspicion
	copy.confidence = confidence
	copy.created_at = created_at
	copy.last_updated_at = last_updated_at
	copy.contributing_evidence_ids = contributing_evidence_ids.duplicate()
	copy.likely_source = likely_source
	copy.source_confidence = source_confidence
	copy.investigation_progress = investigation_progress
	return copy


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"position": position,
		"radius": radius,
		"suspicion": suspicion,
		"confidence": confidence,
		"evidence": contributing_evidence_ids.size(),
		"source_confidence": source_confidence,
		"investigation_progress": investigation_progress,
		"last_updated_at": last_updated_at,
	}
