extends Node

## Registers the two actions this prototype reads, from inside its own scene, so
## project.godot is untouched.
##
## Same contract as tentacle_crawler/components/marker_pilot/crawler_input_actions.gd
## and the runtime remapping in power_and_lighting_prototype.gd: changes are to the
## running process's InputMap only, nothing is written back to project.godot, and
## on the way out we erase only what we created.
##
## PREFIXED `elevator_`, DELIBERATELY. project.godot's [input] is a flat,
## unprefixed namespace. A global action called `skip` is a name something real
## will want later, and by then two unrelated things would be reading it.
##
## NOT BACKSPACE AND NOT ESCAPE. `reset_player` is already Backspace and
## `toggle_mouse_capture` is already Escape; a skip key that also respawned the
## player would look like the skip teleporting you.
##
## Enter overlaps `ui_accept`, which is harmless here only because every control
## in PrototypeTuningPanel is FOCUS_NONE. That rule in prototypes/AGENTS.md is
## load-bearing for exactly this case: a focused Button would eat the key.

const ACTIONS: Dictionary = {
	&"elevator_skip": [KEY_ENTER, KEY_KP_ENTER],
	&"elevator_replay": [KEY_P],
}

const DEADZONE := 0.2

## Only the actions this node actually created. An action the project already
## defines is left alone and is not erased on the way out.
var _created: Array[StringName] = []


func _ready() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		_created.append(action)
		for keycode: int in ACTIONS[action]:
			var event := InputEventKey.new()
			# Physical, so the binding survives a non-QWERTY layout - which is what
			# every action in project.godot does apart from the one that predates
			# the convention.
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


func _exit_tree() -> void:
	for action: StringName in _created:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_created.clear()
