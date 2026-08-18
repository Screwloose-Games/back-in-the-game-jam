class_name PlayerSuspicionCandidate
extends RefCounted

## What the Director gets when it asks who the creature is most suspicious of
## (suspicion.md, "Director -> Suspicion").
##
## It is a CANDIDATE, not a target. Suspicion has no idea about target stickiness,
## retarget thresholds or multiplayer encounter pacing, and returning something called
## `get_target()` would invite the Director to skip all three. Picking is the
## Director's job; this is the evidence it picks from.
##
## `suspicion` and `source_confidence` are different axes and the Director needs both.
## "I am very sure Player 2 is the one making all this faint noise" and "something
## alarming is happening and it might be Player 1" are different situations, and a
## single blended number cannot tell them apart.

var player: Node = null
## 0..1, saturating. How much activity is attributed to this player.
var suspicion: float = 0.0
## 0..1. How sure the attribution is.
var source_confidence: float = 0.0
## Suspicion's clock, at the last piece of evidence naming this player.
var last_evidence_at: float = 0.0


static func make(
	p_player: Node, p_suspicion: float, p_source_confidence: float, p_last_evidence_at: float
) -> PlayerSuspicionCandidate:
	var candidate := PlayerSuspicionCandidate.new()
	candidate.player = p_player
	candidate.suspicion = p_suspicion
	candidate.source_confidence = p_source_confidence
	candidate.last_evidence_at = p_last_evidence_at
	return candidate


func to_dictionary() -> Dictionary:
	return {
		"player": player.name if is_instance_valid(player) else "<freed>",
		"suspicion": suspicion,
		"source_confidence": source_confidence,
		"last_evidence_at": last_evidence_at,
	}
