extends Node

## Every scene the game changes between. The screens load at boot; the level does not.

const MAIN_LEVEL_PATH := "res://levels/asteroid_level/asteroid_level.tscn"

# load(), not const preload(): several of these scenes carry scripts that reference this
# autoload back, and a preload chain resolved at parse time makes that a cyclic reference.
var main_menu = load("res://common/ui/main_menu/main_menu.tscn")
var options_menu = load("res://common/ui/options_menu/options_menu.tscn")
var pause_menu = load("res://common/ui/pause_menu/pause_menu.tscn")
var circle_transition = load("res://common/ui/scene_transitions/circle_transition.tscn")
var fade_transition = load("res://common/ui/scene_transitions/fade_transition.tscn")
var loading_screen = load("res://common/ui/loading_screen/loading_screen.tscn")
var credits = load("res://common/ui/screens/credits.tscn")

## The level, loaded on the spot if nothing warmed it first.
##
## Deliberately not one of the eager vars above. Loading it at autoload time meant the
## whole asteroid was read off disk before the main menu drew its first frame, and
## nothing could show the player that was happening. AsyncLoader warms it in the
## background instead, which makes this a cache hit by the time Start is pressed - so
## pass MAIN_LEVEL_PATH to SceneTransitionManager.change_scene_to_path rather than
## reading this, which is the one path that can still block.
var main_level: PackedScene:
	get:
		if _main_level == null:
			_main_level = load(MAIN_LEVEL_PATH)
		return _main_level

var _main_level: PackedScene = null
