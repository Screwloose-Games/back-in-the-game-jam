extends CanvasLayer

var main_menu_scene: PackedScene = SceneManager.main_menu
var options_menu_scene: PackedScene = SceneManager.options_menu

@onready var continue_button = %ContinueButton
@onready var options_button = %OptionsButton
@onready var main_menu_button = %MainMenuButton
@onready var pause_menu_body = %PauseMenuBody
@onready var quit_button: Button = %QuitButton
@onready var pause_title: Label = %PauseTitleLabel
@onready var session_status_label: Label = %SessionStatusLabel
@onready var session_code_row: HBoxContainer = %SessionCodeRow
@onready var session_code_input: LineEdit = %SessionCodeInput
@onready var copy_session_code_button: Button = %CopySessionCodeButton
@onready var voice_peer_list: VoicePeerList = %VoicePeerList


func _ready():
	visible = false
	continue_button.pressed.connect(on_continue_pressed)
	main_menu_button.pressed.connect(on_main_menu_pressed)
	options_button.pressed.connect(on_options_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	copy_session_code_button.pressed.connect(_on_copy_session_code_pressed)
	_refresh_session_status()
	if OS.has_feature("web"):
		quit_button.hide()


func _on_quit_button_pressed():
	get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause()


func pause():
	var should_pause := not visible if OnlineSession.is_online() else not get_tree().paused
	if not OnlineSession.is_online():
		get_tree().paused = should_pause
	visible = should_pause

	if should_pause:
		_refresh_session_status()
		GlobalSignalBus.game_paused.emit()
	else:
		GlobalSignalBus.game_unpaused.emit()


func unpause():
	if not OnlineSession.is_online():
		get_tree().paused = false
	visible = false
	GlobalSignalBus.game_unpaused.emit()


func on_continue_pressed():
	unpause()


func on_main_menu_pressed():
	unpause()
	OnlineSession.leave("Player returned to the main menu.")
	SceneTransitionManager.change_scene_with_transition(
		main_menu_scene, SceneManager.fade_transition
	)


func on_options_pressed():
	var options_menu_instance = options_menu_scene.instantiate()
	options_menu_instance.back_pressed.connect(on_options_back_pressed.bind(options_menu_instance))
	pause_menu_body.visible = false
	add_child(options_menu_instance)


func on_options_back_pressed(options_menu: OptionsMenu):
	pause_menu_body.visible = true
	options_menu.queue_free()


func _refresh_session_status() -> void:
	if not OnlineSession.is_online():
		pause_title.text = "Paused"
		session_status_label.visible = false
		session_code_row.visible = false
		voice_peer_list.visible = false
		return
	pause_title.text = "Session Menu"
	# Rebuilt on every open: who you can hear changes with the session, and
	# muting somebody has to be one interaction away from gameplay.
	voice_peer_list.refresh()
	session_status_label.visible = true
	session_code_row.visible = true
	session_code_input.text = OnlineSession.session_code()
	copy_session_code_button.text = "Copy"
	if OnlineSession.is_host():
		session_status_label.text = "Join code"
	else:
		session_status_label.text = "Session code"


func _on_copy_session_code_pressed() -> void:
	if session_code_input.text.is_empty():
		return
	DisplayServer.clipboard_set(session_code_input.text)
	session_code_input.select_all()
	copy_session_code_button.text = "Copied!"
