@tool
class_name HazardLabel
extends Label3D

## A name floating over a hazard while its art is still a coloured primitive, so a gas
## pod is tellable from a blockage at four metres. Gated on DebugMode like every other
## readout here, so F3 hides them and an export never draws one.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	DebugMode.changed.connect(_apply_debug_mode)
	# Built long after the autoload settled on a value, so the first sync is explicit.
	_apply_debug_mode(DebugMode.enabled)


func _apply_debug_mode(enabled: bool) -> void:
	visible = enabled
