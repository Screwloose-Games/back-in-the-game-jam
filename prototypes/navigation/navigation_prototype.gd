extends Node3D

## Pushes the values from prototype_knobs.gd onto the scene at startup, so that
## file stays the single place worth editing.

@onready var _world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	_apply_draw_distance()


func _apply_draw_distance() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = PrototypeKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = PrototypeKnobs.FOG_DEPTH_END
	scene_environment.fog_density = PrototypeKnobs.FOG_DENSITY

	if PrototypeKnobs.CAMERA_FAR <= PrototypeKnobs.FOG_DEPTH_END:
		push_warning(
			(
				"PrototypeKnobs.CAMERA_FAR (%.1f) is not past FOG_DEPTH_END (%.1f): "
				+ "geometry will pop at the clip plane before fog hides it."
			)
			% [PrototypeKnobs.CAMERA_FAR, PrototypeKnobs.FOG_DEPTH_END]
		)
