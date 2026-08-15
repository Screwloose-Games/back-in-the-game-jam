class_name PlayerView
extends Node

## Applies the camera's lens and clip planes and the fog that sets how far the
## player can see. Draw distance is a player-side setting here because light is
## a resource in this game and the two have to agree.

@export var settings: PlayerSettings

## The environment fog is written only when this player owns the world
## environment. Off on a remote peer's instance, which shares the same
## environment and would otherwise write it a second time.
@export var applies_fog: bool = true

@onready var camera: Camera3D = %HeadCamera


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerView has no settings; running on PlayerSettings defaults.")
	for failure: String in settings.invariant_failures():
		push_warning("PlayerSettings: %s" % failure)
	apply()


## Pushes the lens and the fog onto the scene. Safe to call again after a
## settings change; it writes nothing back.
func apply() -> void:
	camera.fov = settings.camera_fov
	camera.near = settings.camera_near
	camera.far = settings.camera_far
	if applies_fog:
		_apply_fog()


func _apply_fog() -> void:
	var environment := camera.get_world_3d().environment
	if environment == null:
		return
	environment.fog_enabled = true
	environment.fog_depth_begin = settings.fog_depth_begin
	environment.fog_depth_end = settings.fog_depth_end
	environment.fog_density = settings.fog_density
	environment.ambient_light_energy = settings.ambient_energy
