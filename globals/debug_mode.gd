extends Node

## The one switch every debug readout in the game reads, and the one key that flips it.
##
## An autoload rather than a per-level flag because the things it gates live in three
## different places -- the creature prefab's own Label3D rig, the level's panels, and the
## navigation overlays -- and a flag owned by any one of them cannot reach the other two.
##
## NO `class_name` ON PURPOSE, and it is not a style choice. A global class whose name
## matches an autoload is a parse error -- "Class 'X' hides an autoload singleton" -- so the
## script would fail to compile, the autoload would never instantiate, and every consumer
## would die with it. The autoload name is already a global identifier. Every other autoload
## in globals/ is a bare `extends Node` for the same reason.
##
## F3 IS FREE IN THE INPUT MAP BUT NOT UNUSED. Three prototype scenes read raw `KEY_F3` in
## their own `_unhandled_input` and none of them marks the event handled, so this co-fires
## there. Harmless -- a prototype gates nothing on this flag -- but worth knowing before
## wondering why a brush size changed.

signal changed(enabled: bool)

const TOGGLE_ACTION := &"toggle_debug"

## On for an editor run, off in every export.
##
## DELIBERATELY NOT `OS.is_debug_build()`, which is also true for the debug export template
## that gets handed to playtesters. The export preset ships `all_resources`, so every debug
## script is already in the web build and this default is the only thing between a
## playtester and a screen full of nav graph.
##
## The equality guard makes `changed` idempotent, which matters because listeners rebuild
## ImmediateMesh surfaces on it.
var enabled: bool = OS.has_feature("editor"):
	set(value):
		if enabled == value:
			return
		enabled = value
		changed.emit(enabled)


func _ready() -> void:
	# The numbers are most worth reading while the sim is frozen, so the key has to work
	# with the pause menu up. Same reason scene_transition_manager.gd does this.
	process_mode = PROCESS_MODE_ALWAYS
	if not InputMap.has_action(TOGGLE_ACTION):
		push_warning("No '%s' action; debug mode is code-only." % TOGGLE_ACTION)
		set_process_unhandled_input(false)


## `_unhandled_input` rather than `_input`, so a focused Control gets the key first and F3
## typed into a text field is never stolen.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(TOGGLE_ACTION):
		return
	toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	enabled = not enabled


func set_enabled(value: bool) -> void:
	enabled = value
