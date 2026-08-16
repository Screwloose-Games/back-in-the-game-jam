class_name Settings
extends Resource

@export var sfx_volume: float = 1.0
@export var master_volume: float = 1.0
@export var music_volume: float = 1.0
@export var ambient_volume: float = 1.0
@export var dialogue_volume: float = 1.0
@export var voice_chat_volume: float = 1.0
@export var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED

## Off until the player says otherwise. With voice activation as the talk mode,
## enabling this is what opens a hot microphone, so it is the consent gate.
@export var voice_enabled: bool = false
@export var voice_push_to_talk: bool = false
@export var voice_open_dbfs: float = -45.0
@export var voice_input_device: String = "Default"


func set_window_mode(mode: DisplayServer.WindowMode):
	window_mode = mode


func set_voice_enabled(enabled: bool):
	voice_enabled = enabled


func set_voice_push_to_talk(push_to_talk: bool):
	voice_push_to_talk = push_to_talk


func set_voice_open_dbfs(dbfs: float):
	voice_open_dbfs = dbfs


func set_voice_input_device(device: String):
	voice_input_device = device


func set_bus_volume_percent(bus_name: String, percent: float):
	match bus_name:
		"Master":
			master_volume = percent
		"Music":
			music_volume = percent
		"SFX":
			sfx_volume = percent
		"Ambient":
			ambient_volume = percent
		"Dialogue":
			dialogue_volume = percent
		"VoiceChat":
			voice_chat_volume = percent
