class_name InvestigatingMemory
extends SearchMemory

## What INVESTIGATING remembers between ticks: which hotspot, and where inside it to look.
##
## `desired_location` IS REFRESHED ONCE PER TICK, BEFORE THE TREE RUNS, and that ordering is
## the fix for the loop this state would otherwise fall into. The best unresolved location
## MOVES as searching disconfirms sub-regions -- that motion is the whole of suspicion.md's
## spatial resolution. A condition that recomputed it would be side-effecting, and a tree
## that never recomputed it would search one spot forever.

var hotspot_id: int = -1
## Where inside the hotspot the creature still has reason to look, as of this tick.
var desired_location: Vector3 = Vector3.ZERO
## False when there is no live lead at all, which is what the condition and the action both
## key off rather than testing `desired_location` against zero.
var has_location: bool = false


func forget() -> void:
	hotspot_id = -1
	desired_location = Vector3.ZERO
	has_location = false


func has_search_centre() -> bool:
	return has_location


func search_centre() -> Vector3:
	return desired_location
