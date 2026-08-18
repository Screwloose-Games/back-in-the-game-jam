class_name UnalertedMemory
extends RefCounted

## What UNALERTED remembers between ticks: which nest it is heading for, and until when it
## is happy where it is.
##
## A SEPARATE OBJECT FROM THE STATE, so the tree's leaves can be typed against it without
## the state and its actions referring to each other in a circle. It is fsm.md's "per-state
## memory lives on the state object" with one indirection, and the indirection is what makes
## `travel_to_nest` unit-testable against three positions and no HFSM.
##
## `travel_target` MEANS INTENT, NOT LOCATION, and keeping those apart is what stops the
## state looping. `at_nest` asks "am I at the nest I set out for", so once idling finishes
## and clears the intent, the condition goes false while the alien is still standing in the
## nest -- which is exactly when it should start choosing another. A single field serving as
## both "where I am" and "where I am going" instead re-arms the dwell every tick and the
## alien never leaves.

## Index into `nests`, or -1 for "no intent". Cleared when a dwell completes.
var travel_target: int = -1
## Behavior-clock time at which idling is done. Zero means "not started".
var dwell_until: float = 0.0

var nests: CreatureNestMemory = null


func _init() -> void:
	nests = CreatureNestMemory.new()


func forget_intent() -> void:
	travel_target = -1
	dwell_until = 0.0
