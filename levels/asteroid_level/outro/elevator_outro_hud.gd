class_name ElevatorOutroHud
extends CutsceneHud

## The departure's own chrome: the fade the shot ends on, and the title over it. Sits above
## the gameplay HUD, which it switches off for the duration.

var _gameplay_hud: CanvasLayer

@onready var _fade: ColorRect = $Fade
@onready var _title: Label = $Title


func _ready() -> void:
	_title.text = ElevatorOutroKnobs.HUD_TITLE


## The gameplay HUD belongs to the player, not to this scene, so it arrives by hand.
func bind_gameplay_hud(hud: CanvasLayer) -> void:
	_gameplay_hud = hud


func set_gameplay_visible(is_visible: bool) -> void:
	if _gameplay_hud != null:
		_gameplay_hud.visible = is_visible


## Not skippable, so there is no prompt to show. Overridden rather than left to the base
## no-op so the reason is written down where someone would look for the prompt.
func set_skip_prompt_visible(_is_visible: bool) -> void:
	pass


## Held at black rather than cleared. The level changes scene the moment this cutscene
## ends, and clearing the fade first would show one frame of the asteroid again.
func fade_alpha() -> float:
	return _fade.color.a
