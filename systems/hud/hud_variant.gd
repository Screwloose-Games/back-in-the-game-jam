class_name HudVariant
extends CanvasLayer

## The root of one HUD layout. All three prefabs use this script unchanged.
##
## Everything that differs between the variants is either node structure - which
## components exist and where they sit - or an export on an individual widget saying
## which Figma texture it carries. Nothing here branches on which variant it is, and
## nothing here knows any widget's method names: HudVariant hands each widget the
## state and lets it connect itself.
##
## A CanvasLayer root rather than a Control, so the prefab works as-is when dropped
## into a 3D level, which is the contract prefabs/README.md asks of everything under
## prefabs/. The Chrome child exists because CanvasLayer is not a CanvasItem and so
## cannot be the thing widgets are laid out inside.

@onready var chrome: Control = $Chrome


## Connects every widget present to the state, then makes the state announce itself
## so a variant swapped in mid-run shows the truth immediately rather than waiting
## for the next thing to change. Same connect-then-seed order power_hud.gd uses.
func bind(state: HudState) -> void:
	for widget in widgets():
		widget.bind(state)
	state.announce_all()


func widgets() -> Array[HudWidget]:
	var found: Array[HudWidget] = []
	if chrome == null:
		return found
	for node in chrome.find_children("*", "HudWidget", true, false):
		found.append(node as HudWidget)
	return found
