class_name CutsceneTimedEffect
extends Resource

## One entry in a cutscene's effects list: what happens, and when.
##
## TIME LIVES ON THE WRAPPER, NOT ON THE EFFECT. The effect is a fact about the
## world; the timestamp is a fact about this cutscene. Merge them and the same
## effect cannot be reused at two times, which is the first thing anyone asks for.
##
## ZERO RUNTIME STATE. There is no _has_fired here, deliberately: resources are
## shared by reference, so a flag on one would survive across playbacks and
## silently make every run after the first a no-op. Fired-tracking is an index on
## the player, reset on enter.
##
## This is the walking-skeleton shape. The full spec makes each effect a
## CutsceneEffect SUBCLASS with typed @export properties, so the inspector renders
## real widgets and a non-programmer picks one from a dropdown. That is build-order
## step 3 proper; a name and one float covers every effect the intro actually has,
## and pretending otherwise would be building the tool rather than testing it.

## Seconds from the start of the cutscene.
@export var time: float = 0.0

## Which branch of elevator_effects.gd runs.
@export var effect_name: StringName = &""

## The one generic parameter.
@export var detail: float = 0.0


func describe() -> String:
	return "%.2fs %s" % [time, effect_name]
