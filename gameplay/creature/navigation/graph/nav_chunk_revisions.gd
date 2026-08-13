class_name NavChunkRevisions
extends RefCounted

## Per-chunk terrain revision counters (navigation.md section 25).
##
## A SEPARATE CLASS RATHER THAN FOUR METHODS ON NavGraph, which is already near gdlint's
## twenty-public-method cap and would have to grow a getter, a setter, a lister and a
## maximum to hold what is really one small map.
##
## SECTION 24.1 MEANS THESE CANNOT INVALIDATE AN EDGE, and it is worth being explicit
## about that because a revision counter looks exactly like a cache-busting mechanism.
## Mining is subtractive, so an edge that was traversable stays traversable; what a bump
## invalidates is FRESHNESS -- whether the alien's memory of a chunk predates the change,
## whether a cached leap query was computed before it, whether the overlay should redraw.
## Nothing in `graph/` may act on one by removing anything.

var _revisions: Dictionary = {}
## The highest any chunk has reached, so a caller with one number to compare can.
var _highest: int = 0


func revision_of(chunk: Vector3i) -> int:
	return _revisions.get(chunk, 0)


## Bumps a chunk and returns its new revision.
func bump(chunk: Vector3i) -> int:
	var next: int = revision_of(chunk) + 1
	_revisions[chunk] = next
	_highest = maxi(_highest, next)
	return next


func highest() -> int:
	return _highest


## Every chunk that has ever changed. Section 39 draws these as dirty regions.
func touched() -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for chunk: Vector3i in _revisions:
		found.append(chunk)
	return found


func to_dictionary() -> Dictionary:
	return {"chunks": _revisions.size(), "highest": _highest}
