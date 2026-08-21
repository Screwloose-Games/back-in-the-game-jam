class_name CutsceneData
extends Resource

## A cutscene's data half: the effects list and the playback flags.
##
## SAVED AS ITS OWN .tres, SEPARATE FROM BOTH THE LEVEL AND THE KEYFRAMES. That is
## the arrangement the spec asks for and the one this prototype is testing: the
## level file holds a node and two resource paths, the animation holds everything
## you can see, and this holds everything that changes the game. Three files, three
## owners, and the two that change daily are not the one people merge.

## Which clip in the AnimationPlayer's library is the presentation half.
@export var animation_name: StringName = &"elevator_intro"

## What changes the world, and when. Order in the array does not matter -
## sorted_effects() is what the dispatcher uses.
@export var effects: Array[CutsceneTimedEffect] = []

## Whether the skip key does anything.
@export var skippable: bool = true


## The list in timestamp order, which the dispatch window requires and the author
## should not have to maintain by hand in the inspector.
func sorted_effects() -> Array[CutsceneTimedEffect]:
	var ordered := effects.duplicate()
	ordered.sort_custom(
		func(a: CutsceneTimedEffect, b: CutsceneTimedEffect) -> bool: return a.time < b.time
	)
	return ordered


## Problems an author can fix, checked against the clip this data is paired with.
##
## The timestamped-past-the-end case is the one worth having. Such an effect never
## fires on a normal playthrough - the clock stops before it - and then fires on
## every skip, because skip flushes the remaining window. So it works, silently,
## until someone watches the whole thing, and then it does not.
func validate(animation_length: float) -> PackedStringArray:
	var failures := PackedStringArray()
	if effects.is_empty():
		failures.append("no effects; the cutscene changes nothing about the world")
	for timed: CutsceneTimedEffect in effects:
		if timed == null:
			failures.append("an effects entry is null")
			continue
		if timed.effect_name.is_empty():
			failures.append("effect at %.2fs has no name" % timed.time)
		if timed.time < 0.0:
			failures.append("%s is at a negative time" % timed.describe())
		if timed.time > animation_length:
			var detail := (
				"%s is past the end of a %.2fs clip; it would never fire normally, then fire on every skip"
				% [timed.describe(), animation_length]
			)
			failures.append(detail)
	return failures
