class_name RetreatingMemory
extends UnalertedMemory

## What RETREATING remembers between ticks: the nest it is walking to, and why it is leaving.
##
## EXTENDS UnalertedMemory RATHER THAN SHARING A BASE WITH IT, because a retreat IS a nest
## journey. Same intent field, same nest list, same anti-ping-pong rule, same
## `forget_intent()` -- fsm.md gives both modes one scoring function and differs only in which
## way the distance term's sign points. Factoring a third class out from between them would
## rename UnalertedMemory across six files in order to say exactly that, and `travel_to_nest`
## would still be typed against whatever the base was called.
##
## `dwell_until` IS INHERITED AND UNUSED. There is no idling here: the alien walks until it
## has separation and then the HFSM takes it back to UNALERTED, which chooses afresh.
##
## `disengage_reason` IS LATCHED ON ENTRY AND NEVER RE-READ. The Director rebuilds its
## directive every tick, and `force_disengage` is consumed at the transition -- so by the time
## the tree first runs, the live field has very often reset to NONE. Reading it per tick
## degrades the loud/quiet split to always-quiet, silently, and no guard-level test would
## notice because every guard here passes either way.

var disengage_reason: EncounterDirective.Reason = EncounterDirective.Reason.NONE
