class_name NavKnowledgeUpdate
extends RefCounted

## What one batch of observations changed (navigation.md sections 27, 29).
##
## RETURNED RATHER THAN SIGNALLED FROM INSIDE, the same shape `NavPatchResult` and
## `SuspicionHotspotField.rebuild` use: emitting mid-ingest would let a listener re-enter
## the knowledge graph part-way through a batch, and re-entrancy is the one hazard a store
## this simple has no defence against.
##
## THE TWO POSITION LISTS ARE WHAT SECTION 29 ACTS ON. A contradiction is somewhere the
## alien believed it could go and something says otherwise; a suspected opening is
## somewhere it never knew about. Both become inspection requests, and they are kept apart
## because they are different questions -- "was I wrong?" and "what is that?" -- and
## section 30 gives them different reasons.

## World node ids whose belief changed.
var changed_nodes: PackedInt32Array = PackedInt32Array()
## Section 29's geometry mismatch: observed solid where passage was believed.
var contradictions: PackedVector3Array = PackedVector3Array()
## Section 40.6: observed free where nothing was believed at all.
var suspected_openings: PackedVector3Array = PackedVector3Array()
## Whether a connected relearn hit its bounds and left connected geometry unlearned.
##
## NOT PART OF `is_empty`. A truncated flood that learned nothing is still an empty update;
## this says how the flood ENDED, not whether it changed anything. It exists so a bound
## being hit is visible in the debug state rather than silently reading as "that was all
## the geometry there was".
var truncated: bool = false


func is_empty() -> bool:
	return changed_nodes.is_empty() and contradictions.is_empty() and suspected_openings.is_empty()


## Whether anything here is worth stopping and looking at (section 29).
func wants_inspection() -> bool:
	return not contradictions.is_empty() or not suspected_openings.is_empty()


func to_dictionary() -> Dictionary:
	return {
		"changed_nodes": changed_nodes.size(),
		"contradictions": contradictions.size(),
		"suspected_openings": suspected_openings.size(),
		"truncated": truncated,
	}
