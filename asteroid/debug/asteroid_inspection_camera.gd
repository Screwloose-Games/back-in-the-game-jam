class_name AsteroidInspectionCamera
extends Node3D


@export var fly_speed: float = 8.0
@export var fast_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.0025

var mouse_captured := false
var camera_pitch := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_build_toolbar()
	go_outside()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.screen_relative.x * mouse_sensitivity)
		camera_pitch = clampf(
			camera_pitch - event.screen_relative.y * mouse_sensitivity,
			-deg_to_rad(89.0),
			deg_to_rad(89.0)
		)
		camera.rotation.x = camera_pitch
	elif event.is_action_pressed(&"toggle_mouse_capture"):
		_set_mouse_captured(not mouse_captured)
	elif event.is_action_pressed(&"reset_player"):
		go_outside()


func _process(delta: float) -> void:
	var movement := Vector3(
		Input.get_axis(&"thrust_left", &"thrust_right"),
		Input.get_axis(&"thrust_down", &"thrust_up"),
		Input.get_axis(&"thrust_forward", &"thrust_back")
	).limit_length(1.0)

	var current_speed := fly_speed
	if Input.is_action_pressed(&"stabilize"):
		current_speed *= fast_multiplier

	global_position += global_basis * movement * current_speed * delta


func go_outside() -> void:
	_teleport_and_look(Vector3(0.0, 5.0, 45.0), Vector3.ZERO)


func go_to_entrance() -> void:
	_teleport_and_look(
		AsteroidLayout.ENTRANCE_START + Vector3(0.0, 0.0, 2.5),
		AsteroidLayout.BLUE_ROOM_CENTER
	)


func go_to_blue_room() -> void:
	_teleport_and_look(
		AsteroidLayout.BLUE_ROOM_CENTER,
		AsteroidLayout.PURPLE_ROOM_CENTER
	)


func go_to_purple_room() -> void:
	_teleport_and_look(
		AsteroidLayout.PURPLE_ROOM_CENTER,
		AsteroidLayout.CORE_ROOM_CENTER
	)


func go_to_core_room() -> void:
	_teleport_and_look(
		AsteroidLayout.CORE_ROOM_CENTER,
		AsteroidLayout.YELLOW_DEPOSIT_CENTER
	)


func _teleport_and_look(new_position: Vector3, target: Vector3) -> void:
	global_position = new_position
	camera.rotation = Vector3.ZERO
	look_at(target, Vector3.UP)
	camera_pitch = 0.0


func _set_mouse_captured(should_capture: bool) -> void:
	mouse_captured = should_capture
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED
		if should_capture
		else Input.MOUSE_MODE_VISIBLE
	)


func _build_toolbar() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(252.0, 16.0)
	toolbar.add_theme_constant_override(&"separation", 6)
	canvas.add_child(toolbar)

	_add_toolbar_button(toolbar, "Outside", go_outside)
	_add_toolbar_button(toolbar, "Entrance", go_to_entrance)
	_add_toolbar_button(toolbar, "Blue Room", go_to_blue_room)
	_add_toolbar_button(toolbar, "Purple Room", go_to_purple_room)
	_add_toolbar_button(toolbar, "Core", go_to_core_room)
	_add_toolbar_button(toolbar, "Capture Mouse (Tab)", _toggle_mouse_from_button)


func _add_toolbar_button(
	toolbar: HBoxContainer,
	button_text: String,
	callback: Callable
) -> void:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(92.0, 42.0)
	button.pressed.connect(callback)
	toolbar.add_child(button)


func _toggle_mouse_from_button() -> void:
	_set_mouse_captured(not mouse_captured)
