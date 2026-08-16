class_name OptionsMenu
extends Node

## Display and audio options, including the voice chat controls.
##
## Instanced fresh by the pause menu on every open, so _ready() and the device
## enumeration run again each time - which is what keeps a headset plugged in
## mid-session from being invisible until the next launch.

signal back_pressed

const TALK_MODE_VOICE_ACTIVATED := 0
const TALK_MODE_PUSH_TO_TALK := 1

var previous_ui: Node

@onready var window_button = %WindowButton as Button
@onready var master_slider = %MasterSlider
@onready var sfx_slider = %SFXSlider
@onready var music_slider = %MusicSlider
@onready var ambient_slider = %AmbientSlider
@onready var dialogue_slider = %DialogueSlider
@onready var voice_chat_slider = %VoiceChatSlider
@onready var back_button = %BackButton
@onready var audio_input_option_button: OptionButton = %AudioInputOptionButton
@onready var voice_enabled_button: Button = %VoiceEnabledButton
@onready var talk_mode_option_button: OptionButton = %TalkModeOptionButton
@onready var mic_level_bar: ProgressBar = %MicLevelBar
@onready var mic_threshold_slider: HSlider = %MicThresholdSlider


func _ready():
	back_button.pressed.connect(on_back_pressed)
	window_button.pressed.connect(on_window_button_pressed)
	master_slider.value_changed.connect(on_audio_slider_changed.bind("Master"))
	sfx_slider.value_changed.connect(on_audio_slider_changed.bind("SFX"))
	music_slider.value_changed.connect(on_audio_slider_changed.bind("Music"))
	ambient_slider.value_changed.connect(on_audio_slider_changed.bind("Ambient"))
	dialogue_slider.value_changed.connect(on_audio_slider_changed.bind("Dialogue"))
	voice_chat_slider.value_changed.connect(on_audio_slider_changed.bind("VoiceChat"))

	audio_input_option_button.item_selected.connect(_on_audio_input_selected)
	voice_enabled_button.pressed.connect(_on_voice_enabled_pressed)
	talk_mode_option_button.item_selected.connect(_on_talk_mode_selected)
	mic_threshold_slider.value_changed.connect(_on_mic_threshold_changed)
	VoiceService.local_level_changed.connect(_on_local_level_changed)
	VoiceService.voice_unavailable.connect(_on_voice_unavailable)

	_fill_talk_modes()
	update_display()


func update_display():
	window_button.text = "Windowed"
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		window_button.text = "Fullscreen"
	master_slider.value = get_bus_volume_percent("Master")
	sfx_slider.value = get_bus_volume_percent("SFX")
	music_slider.value = get_bus_volume_percent("Music")
	ambient_slider.value = get_bus_volume_percent("Ambient")
	dialogue_slider.value = get_bus_volume_percent("Dialogue")
	voice_chat_slider.value = get_bus_volume_percent("VoiceChat")
	_fill_audio_inputs()
	_refresh_voice_controls()


func get_bus_volume_percent(bus_name: String):
	var bus_index = AudioServer.get_bus_index(bus_name)
	var volume_db = AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(volume_db)


func set_bus_volume_percent(bus_name: String, percent: float):
	var bus_index = AudioServer.get_bus_index(bus_name)
	var volume_db = linear_to_db(percent)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	GameSettings.write_back_volume_setting(bus_name, percent)


func on_window_button_pressed():
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		GameSettings.set_window_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		GameSettings.set_window_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	GameSettings.write_back_display_settings(DisplayServer.window_get_mode())
	update_display()


func on_audio_slider_changed(value: float, bus_name: String):
	set_bus_volume_percent(bus_name, value)


func on_back_pressed():
	back_pressed.emit()


func _fill_talk_modes() -> void:
	talk_mode_option_button.clear()
	talk_mode_option_button.add_item("Voice Activated", TALK_MODE_VOICE_ACTIVATED)
	talk_mode_option_button.add_item("Push to Talk", TALK_MODE_PUSH_TO_TALK)


## On web the engine can only ever see the system default, so a single entry is
## shown greyed out rather than pretending to offer a choice.
func _fill_audio_inputs() -> void:
	var devices := AudioServer.get_input_device_list()
	audio_input_option_button.clear()
	for device in devices:
		audio_input_option_button.add_item(device)
	audio_input_option_button.select(maxi(devices.find(AudioServer.input_device), 0))
	audio_input_option_button.disabled = devices.size() <= 1


func _refresh_voice_controls() -> void:
	voice_enabled_button.text = "On" if VoiceService.voice_enabled else "Off"
	talk_mode_option_button.select(
		TALK_MODE_PUSH_TO_TALK if VoiceService.push_to_talk else TALK_MODE_VOICE_ACTIVATED
	)
	mic_threshold_slider.set_value_no_signal(VoiceService.open_dbfs)
	mic_level_bar.value = VoiceService.local_loudness()


func _on_audio_input_selected(index: int) -> void:
	var device := audio_input_option_button.get_item_text(index)
	GameSettings.set_audio_input_device(device)
	GameSettings.write_back_audio_input_device(device)


func _on_voice_enabled_pressed() -> void:
	VoiceService.voice_enabled = not VoiceService.voice_enabled
	GameSettings.write_back_voice_enabled(VoiceService.voice_enabled)
	_refresh_voice_controls()


func _on_talk_mode_selected(index: int) -> void:
	VoiceService.push_to_talk = index == TALK_MODE_PUSH_TO_TALK
	GameSettings.write_back_voice_push_to_talk(VoiceService.push_to_talk)


func _on_mic_threshold_changed(value: float) -> void:
	VoiceService.open_dbfs = value
	GameSettings.write_back_voice_open_dbfs(value)


## Green while the gate is open, so the threshold can be set by talking and
## watching rather than by knowing what a decibel is.
func _on_local_level_changed(level: float) -> void:
	mic_level_bar.value = level
	mic_level_bar.modulate = Color.LIME_GREEN if VoiceService.is_transmitting() else Color.WHITE


func _on_voice_unavailable(reason: String) -> void:
	voice_enabled_button.text = "Unavailable"
	voice_enabled_button.tooltip_text = reason
