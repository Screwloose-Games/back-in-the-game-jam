class_name ElevatorIntroHud
extends CutsceneHud

## The intro's own screen chrome: the opening full-screen shot of the quota tube,
## the title card, the skip prompt and a debug readout.
##
## IT IS NOT THE GAME'S HUD. prefab_hud_04 is, and it arrives on its own at the
## match cut through HudBootCrt. This layer is only the things that exist for the
## duration of the cutscene and are gone afterwards, which is why it sits above
## the gameplay HUD rather than replacing it.
##
## THIS SCRIPT DOES NOT OWN MonitorShot.shot_alpha OR Title.modulate. The
## animation does, as value tracks, so a scrub to any time yields exactly the
## right alpha and a skip's seek lands them where playing through would have.
## Two authorities on "is the overlay showing" is how one of them ends up stale
## after a skip. The exceptions are the set_*() calls below, which assert the
## FINAL state at CLEANUP - by which point the animation has stopped writing.

## The player's real HUD, handed over by elevator_intro.gd once a player exists.
## Null in a scene with no player, which is the case the prototype's capture
## tooling runs in.
var _gameplay_hud: CanvasLayer

@onready var _monitor_shot: ElevatorMonitorShot = $MonitorShot
@onready var _title: Label = $Title
@onready var _skip_prompt: Label = $SkipPrompt
@onready var _readout: Label = $Readout


func _ready() -> void:
	# Copy comes from the knobs file rather than the .tscn, because it is the
	# thing most likely to change and it should change in one place.
	_title.text = ElevatorIntroKnobs.HUD_TITLE
	_skip_prompt.text = ElevatorIntroKnobs.HUD_SKIP_PROMPT


## Points the overlay at the HUD the cutscene has to get out of the way of.
func bind_gameplay_hud(hud: CanvasLayer) -> void:
	_gameplay_hud = hud


func set_gameplay_visible(is_visible: bool) -> void:
	if _gameplay_hud != null:
		_gameplay_hud.visible = is_visible


## Belt and braces over the shot_alpha keyframe: a stuck opaque overlay is the
## worst failure here, and the verifier checks the keyframe separately.
func set_monitor_shot_visible(is_visible: bool) -> void:
	_monitor_shot.shot_alpha = 1.0 if is_visible else 0.0


## How much of the terminal's glass the opening shot holds.
func set_monitor_framing(distance: float, fov: float) -> void:
	_monitor_shot.set_framing(distance, fov)


func set_skip_prompt_visible(is_visible: bool) -> void:
	_skip_prompt.visible = is_visible


## The title card is a beat, not a state: over by the end of the clip whether you
## watched it or skipped it.
func clear_title() -> void:
	_title.modulate.a = 0.0


func set_readout(text: String) -> void:
	_readout.text = text
