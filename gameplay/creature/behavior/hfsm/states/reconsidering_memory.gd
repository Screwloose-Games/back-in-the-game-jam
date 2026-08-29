class_name ReconsideringMemory
extends RefCounted

## What RECONSIDERING remembers: which lead it walked away from.
##
## KEPT ONLY SO THE STATE CAN BE ASKED WHAT IT GAVE UP ON. The suppression that stops the
## creature re-selecting that lead lives in Suspicion, not here -- an id held on a per-state
## memory would be forgotten the moment the state was left, which is one tick after it is
## written and long before it could do any good.

## The hotspot the creature stopped trying to reach, or -1 if it entered without one.
var hotspot_id: int = -1


func forget() -> void:
	hotspot_id = -1
