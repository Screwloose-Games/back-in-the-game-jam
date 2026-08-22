class_name ElevatorMonitorShot
extends Control

## The cutscene's opening shot: the car's quota terminal, full-screen, through a
## canvas_item port of the same CRT the 3D plate wears.
##
## A CAMERA POINTED AT A SCREEN, NOT A SECOND SCREEN. It samples the very
## ViewportTexture the plate composites, so there is one readout in the whole scene
## and the words on it cannot drift. Two rules follow, and undoing either re-opens
## that drift: this never reads ElevatorIntroKnobs for copy, and it never calls a
## setter on the readout.

## What is on screen, 0 to 1. ANIMATED, and the only authority for it - see
## set_shot_alpha.
@export_range(0.0, 1.0) var shot_alpha := 0.0:
	set = set_shot_alpha

## The terminal this is a close-up of. Needs node_paths= on the .tscn node block or
## it silently stays null.
@export var quota_screen: ElevatorScreen

var _material: ShaderMaterial

@onready var _crt: ColorRect = $Crt


func _ready() -> void:
	_material = _crt.material as ShaderMaterial
	if _material == null:
		push_warning("ElevatorMonitorShot has no ShaderMaterial on Crt; the shot will be blank.")
		return
	if quota_screen == null:
		push_error("ElevatorMonitorShot has no quota_screen; the opening shot has nothing to show.")
		return
	# Pushed, never authored, for the reason elevator_screen.gd:74 gives: a
	# ViewportTexture written into a .tscn resolves against the scene it was saved
	# in, and this one lives in a different scene from the viewport entirely.
	_material.set_shader_parameter("content_tex", quota_screen.get_content_texture())
	set_shot_alpha(shot_alpha)
	_push_frame_aspect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_push_frame_aspect()


func set_shot_alpha(value: float) -> void:
	shot_alpha = clampf(value, 0.0, 1.0)
	# Derived, not decided. A fullscreen twelve-tap gather is not free for the twenty
	# seconds after the prologue, and a second animated property saying "showing" is
	# how one of them ends up stale after a skip.
	visible = shot_alpha > 0.001
	if _material != null:
		_material.set_shader_parameter("shot_alpha", shot_alpha)


## How much of the terminal's glass this shot holds, so the crop matches the frame
## the 3D close-up will cut to. Pushed from the prototype root with the same distance
## the camera pose is baked from and whatever fov the tuning panel is currently on.
func set_framing(distance: float, fov: float) -> void:
	if _material == null or quota_screen == null:
		return
	var glass := _glass_size()
	if glass.y <= 0.0:
		return
	var seen := 2.0 * distance * tan(deg_to_rad(fov) * 0.5)
	_material.set_shader_parameter("frame_height", seen / glass.y)
	_material.set_shader_parameter("content_aspect", glass.x / glass.y)


## The lit rectangle of the terminal in metres, measured off the live plate rather
## than copied: the quad, its screen_rect and the car's scale all feed it.
func _glass_size() -> Vector2:
	var plate := quota_screen.plate
	var quad := plate.mesh as QuadMesh
	var material := plate.material_override as ShaderMaterial
	if quad == null or material == null:
		return Vector2.ZERO
	var rect: Vector4 = material.get_shader_parameter("screen_rect")
	var scale := plate.global_transform.basis.get_scale()
	return Vector2(quad.size.x * rect.z * scale.x, quad.size.y * rect.w * scale.y)


func _push_frame_aspect() -> void:
	if _material == null or size.y <= 0.0:
		return
	_material.set_shader_parameter("frame_aspect", size.x / size.y)
