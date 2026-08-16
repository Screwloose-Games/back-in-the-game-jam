class_name SearchMemory
extends RefCounted

## The two questions `search_area` asks its state, and nothing else.
##
## WIDENED RATHER THAN DUPLICATED, WHICH WAS THE CHOICE. `BtSearchArea` was typed against
## `InvestigatingMemory` and reads exactly two things off it, and HUNTING needs the same node
## aimed at the last credible target region (behavior.md section 28). The alternative was
## giving `HuntingMemory` fields called `desired_location` and `has_location` -- but that
## stores the estimate twice under two names on one object, and two copies of a value that is
## refreshed every tick drift the moment one refresh path is added and the other is not.
##
## ACCESSORS RATHER THAN SHARED FIELDS, so each state keeps its own vocabulary. INVESTIGATING
## searches a `desired_location` inside a hotspot; HUNTING searches around
## `last_credible_target_position`. Those are different claims about the world and the code
## should keep saying so; the only thing they have in common is that a sweep needs a centre.
##
## Both are virtual and both answer safely, so a memory that has not been refreshed yet
## reports "nowhere to look" rather than the world origin.


func has_search_centre() -> bool:
	return false


func search_centre() -> Vector3:
	return Vector3.ZERO
