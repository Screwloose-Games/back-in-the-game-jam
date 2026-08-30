class_name InteractionPrompt
extends Label3D

## The floating word over an interactable. Hang one under an Interactable and it shows
## while that thing is focused and hides the moment it is not.

## Bound to focus rather than to overlap, which is the whole point: two interactables you
## are standing between overlap you at once, and only one of them is being addressed.
@export var interactable: Interactable

## Shown while the interactable answers a hold, appended to its prompt.
@export var hold_suffix: String = ""


func _ready() -> void:
	visible = false
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Without a cutout the label draws through as a transparent quad that sorts badly
	# against the thing it is labelling.
	alpha_cut = ALPHA_CUT_DISCARD
	if interactable == null:
		interactable = get_parent() as Interactable
	if interactable == null:
		push_warning("InteractionPrompt at %s has no Interactable to follow." % get_path())
		return
	interactable.focus_gained.connect(_on_focus_gained.unbind(1))
	interactable.focus_lost.connect(_on_focus_lost.unbind(1))
	interactable.availability_changed.connect(_on_availability_changed)


func _on_focus_gained() -> void:
	text = _prompt_text()
	visible = true


func _on_focus_lost() -> void:
	visible = false


func _on_availability_changed(available: bool) -> void:
	if not available:
		visible = false


func _prompt_text() -> String:
	var prompt_text := interactable.prompt_text()
	if not prompt_text.is_empty():
		return prompt_text
	if hold_suffix.is_empty() or not interactable.supports_hold():
		return interactable.prompt
	return "%s\n%s" % [interactable.prompt, hold_suffix]
