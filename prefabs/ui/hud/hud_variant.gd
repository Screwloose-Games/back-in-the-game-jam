class_name HudVariant
extends CanvasLayer

@onready var chrome: Control = $Chrome


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
