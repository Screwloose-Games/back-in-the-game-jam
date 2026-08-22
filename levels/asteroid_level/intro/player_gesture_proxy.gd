class_name PlayerGestureProxy
extends Node

## A keyable property inside the cutscene that writes the player's gesture blend.
##
## THE PLAYER IS NOT IN THIS SCENE. AnimationPlayer resolves track paths against
## its root_node, which is the intro's root; the player is spawned by the level
## into Players/Player and a path that walked out to it would resolve to nothing,
## silently. One node with one setter, keyed like any other value track, and the
## arm scrubs and skips exactly like the doors do.

## The gesture layer's weight, 0 (arm down) to 1 (pressing). ANIMATED.
@export_range(0.0, 1.0) var press_blend := 0.0:
	set = set_press_blend

var _rig: CutscenePlayerRig


func bind(rig: CutscenePlayerRig) -> void:
	_rig = rig
	set_press_blend(press_blend)


func set_press_blend(value: float) -> void:
	press_blend = clampf(value, 0.0, 1.0)
	if _rig != null:
		_rig.set_gesture_blend(press_blend)
