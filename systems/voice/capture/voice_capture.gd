class_name VoiceCapture
extends RefCounted

## The seam between the microphone and everything downstream of it.
##
## This base class is also the null implementation: it starts, reports itself
## inactive and returns no frames, so the editor, the automated tests and a
## player who denied microphone permission all take the same path.

var _config: VoiceConfig


func _init(config: VoiceConfig) -> void:
	_config = config


func config() -> VoiceConfig:
	return _config


func start() -> Error:
	return OK


func stop() -> void:
	pass


func is_active() -> bool:
	return false


## Empty while the capture is idle or unavailable; never an error.
func poll() -> Array[PackedFloat32Array]:
	return []


## Player-facing explanation of why capture is unavailable, or an empty string.
func unavailable_reason() -> String:
	return ""


func source_rate() -> int:
	return _config.sample_rate
