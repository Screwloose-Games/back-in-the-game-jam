class_name CutsceneHud
extends CanvasLayer

## What CutscenePlayer is allowed to say to a screen overlay.
##
## FOUR CALLS, ALL NO-OPS HERE. The clock has to hide the crosshair, show a skip
## prompt and force the opening full-screen shot off at CLEANUP, and it must be
## able to do that without knowing whether the overlay behind it is a helmet
## visor, a letterbox or nothing at all. Every cutscene in the project overrides
## the ones it has and ignores the rest, so adding a fifth beat to one cutscene
## does not break the others.


## Hides the overlay that belongs to gameplay rather than to the cutscene.
func set_gameplay_visible(_is_visible: bool) -> void:
	pass


## Forces any full-screen cutscene overlay off at CLEANUP - the one call that is
## not optional, because a stuck opaque overlay is the worst failure here.
func set_monitor_shot_visible(_is_visible: bool) -> void:
	pass


func set_skip_prompt_visible(_is_visible: bool) -> void:
	pass


func set_readout(_text: String) -> void:
	pass
