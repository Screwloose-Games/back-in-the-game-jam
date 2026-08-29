class_name SceneMenu
extends Control

## The scene launcher: the levels and test rooms worth reaching from a running build.
## Always available, in every build -- the deployed web build is where playtesting happens,
## and a button behind DebugMode is not reachable there.

signal back_pressed

## Display name -> res:// path, in the order shown. Paths, never preload()ed PackedScenes:
## a const preload resolves at parse time, and this script is parsed when SceneManager
## load()s main_menu.tscn at boot, so every level would load before the title screen drew.
const SCENES := {
	"Asteroid Level": "res://levels/asteroid_level/asteroid_level.tscn",
	"Hazard Sandbox": "res://levels/hazard_sandbox/hazard_sandbox.tscn",
	"Art Sandbox": "res://levels/art_sandbox/art_sandbox.tscn",
	"Elevator Cutscene": "res://prototypes/elevator_cutscene/elevator_cutscene_prototype.tscn",
}

var _first_button: Button = null

@onready var _list: VBoxContainer = %List
@onready var _back_button: Button = %BackButton
@onready var _audio: Control = %AudioControl


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_build_list()


## Shown by the main menu, which needs a button focused or the keyboard is dead.
func open() -> void:
	visible = true
	if _first_button != null:
		_first_button.grab_focus()


## Built rather than authored, the way extraction_report.gd builds its breakdown rows.
func _build_list() -> void:
	for display_name: String in SCENES:
		var button := _make_button(display_name, SCENES[display_name])
		_list.add_child(button)
		if _first_button == null and not button.disabled:
			_first_button = button


## Disabled rather than left to fail mid-transition: change_scene_to_path fades out first,
## so a path that no longer loads leaves a black screen with no way back.
func _make_button(display_name: String, path: String) -> Button:
	var button := Button.new()
	button.text = display_name
	button.tooltip_text = path
	if not ResourceLoader.exists(path):
		button.text = "%s  (missing)" % display_name
		button.disabled = true
		return button
	button.pressed.connect(_on_scene_pressed.bind(path))
	# Callable(), not _audio._on_hover: main_menu_audio.gd declares no class_name, so a
	# Control-typed reference has no member of that name and would not compile.
	button.mouse_entered.connect(Callable(_audio, &"_on_hover"))
	button.pressed.connect(Callable(_audio, &"_on_open"))
	return button


## Solo always: the pause menu only pauses the tree while OnlineSession is solo, and
## asteroid_level.gd acts on a queued host/join intent that a test launch never wanted.
func _on_scene_pressed(path: String) -> void:
	OnlineSession.queue_solo()
	SceneTransitionManager.change_scene_to_path(path, SceneManager.fade_transition)


func _on_back_pressed() -> void:
	back_pressed.emit()
