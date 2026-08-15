class_name PlayerUi
extends Node

## This player's screen: their HUD and their pause menu. Multiplayer is networked,
## so a remote peer's copy is switched off and only this machine's own player draws
## anything or can pause.

var _is_local := true

@onready var hud_binding: PlayerHudBinding = %HudBinding
@onready var pause_screen: CanvasLayer = %PauseScreen
@onready var input: PlayerInput = %Input
@onready var visibility: PlayerVisibility = %Visibility


func _ready() -> void:
	_is_local = visibility.is_local_player
	if not _is_local:
		_switch_off_for_remote_peer()
		return
	GlobalSignalBus.game_paused.connect(_on_game_paused)
	GlobalSignalBus.game_unpaused.connect(_on_game_unpaused)


## Leaving the level with the cursor still captured would strand the main menu.
func _exit_tree() -> void:
	if _is_local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Runs after the children's own _ready, so the HUD it frees is already instanced.
func _switch_off_for_remote_peer() -> void:
	var hud := hud_binding.hud()
	if hud != null:
		hud.queue_free()
	pause_screen.queue_free()
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_game_paused() -> void:
	input.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_game_unpaused() -> void:
	input.enabled = true
	input.capture_mouse()
