class_name CutsceneEffects
extends Node

## The half of a cutscene that a skip must still run.
##
## Everything you can see is a keyframe and can be discarded; everything a
## subclass of this changes is state, and discarding it leaves the level broken.
## CutscenePlayer knows only these three calls, so the clock never learns what
## any particular cutscene's effects mean.
##
## SUBCLASS BRANCHES SHOULD BE PLAIN ASSIGNMENTS, so every effect is idempotent
## by construction and a dispatch window that fires three at once cannot
## double-anything.


## Back to the state the world is in before the cutscene runs, so a replay is a
## replay rather than a second run on top of the first one's leftovers.
func reset() -> void:
	pass


## One timed effect; a subclass's default arm should push_error, so an unimplemented
## name in the .tres is a named failure rather than silence.
func apply(effect_name: StringName, detail: float) -> void:
	push_error(
		(
			"CutsceneEffects has no branch for '%s' (detail %.2f); this base class implements nothing."
			% [effect_name, detail]
		)
	)


## The end state the effects own, asserted at CLEANUP after the animation has
## stopped writing.
func settle_terminal_state() -> void:
	pass


## A per-frame tick while playing; the elevator intro uses it to carry the player
## rig along with the camera anchor.
func advance(_delta: float) -> void:
	pass
