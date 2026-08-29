extends Control

@onready var start_button: Button = %StartButton
@onready var host_button: Button = %HostButton
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var join_button: Button = %JoinButton
@onready var online_status: Label = %OnlineStatus
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var scenes_button: Button = %ScenesButton
@onready var quit_button: Button = %QuitButton
@onready var shell: Control = %Shell
@onready var pointer: MainMenuPointer = %Pointer
@onready var options_menu: OptionsMenu = %OptionsMenu
@onready var scene_menu: SceneMenu = %SceneMenu


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_code_input.text_submitted.connect(_on_join_code_submitted)
	options_button.pressed.connect(_on_options_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	scenes_button.pressed.connect(_on_scenes_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	options_menu.back_pressed.connect(_on_options_back_pressed)
	options_menu.visible = false
	scene_menu.back_pressed.connect(_on_scene_menu_back_pressed)
	scene_menu.visible = false
	online_status.text = OnlineSession.consume_last_error()
	online_status.visible = not online_status.text.is_empty()

	if OS.has_feature("web"):
		quit_button.visible = false

	var items: Array[Button] = [
		start_button,
		host_button,
		join_button,
		options_button,
		credits_button,
		scenes_button,
		quit_button
	]
	pointer.follow(items.filter(func(item: Button) -> bool: return item.visible))

	# Nothing else wants these seconds, and a level warmed while the player reads the
	# menu is a level that starts the moment they press the button.
	AsyncLoader.request(SceneManager.MAIN_LEVEL_PATH)


func _on_start_pressed():
	OnlineSession.queue_solo()
	_start_level()


func _on_host_pressed() -> void:
	OnlineSession.queue_host()
	_start_level()


func _on_join_pressed() -> void:
	var result: Error = OnlineSession.queue_join(join_code_input.text)
	if result != OK:
		online_status.text = "Enter a valid six-character session code."
		online_status.visible = true
		join_code_input.grab_focus()
		return
	_start_level()


func _on_join_code_submitted(_submitted_code: String) -> void:
	_on_join_pressed()


func _start_level() -> void:
	SceneTransitionManager.change_scene_to_path(
		SceneManager.MAIN_LEVEL_PATH, SceneManager.fade_transition
	)


func _on_credits_pressed():
	GlobalSignalBus.credits_screen_started.emit()
	SceneTransitionManager.change_scene_with_transition(
		SceneManager.credits, SceneManager.fade_transition
	)


func _on_options_pressed():
	shell.visible = false
	options_menu.visible = true


func _on_options_back_pressed():
	options_menu.visible = false
	shell.visible = true


func _on_scenes_pressed() -> void:
	shell.visible = false
	scene_menu.open()


func _on_scene_menu_back_pressed() -> void:
	scene_menu.visible = false
	shell.visible = true
	# Puts the pointer back beside the button that opened the list; the options menu
	# skips this and leaves its pointer stranded wherever it last was.
	scenes_button.grab_focus()


func _on_quit_pressed():
	get_tree().quit()
