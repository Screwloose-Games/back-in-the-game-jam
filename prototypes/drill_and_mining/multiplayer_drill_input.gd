class_name MultiplayerDrillInput
extends Node

## Player-owned controls sampled by ClientPredictor3D.
##
## This adapter owns devices, not game state. Movement and the held drill
## trigger become bounded predictor commands; only ready_to_play is replicated
## directly so the host knows when this peer has entered the chamber.

@export var thrust := Vector3.ZERO:
	set(value):
		thrust = value.limit_length(1.0) if value.is_finite() else Vector3.ZERO

@export var look_orientation := Quaternion.IDENTITY:
	set(value):
		if value.is_finite() and value.length_squared() > 0.0001:
			look_orientation = value.normalized()

@export var stabilizing := false
@export var drilling := false
@export var ready_to_play := false

var _accumulated_mouse_motion := Vector2.ZERO
var _desired_basis := Basis.IDENTITY
var _mouse_captured := false


func begin_local_control(initial_basis: Basis) -> void:
	reset_local_orientation(initial_basis)
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func reset_local_orientation(authoritative_basis: Basis) -> void:
	if not is_multiplayer_authority():
		return
	_desired_basis = authoritative_basis.orthonormalized()
	look_orientation = _desired_basis.get_rotation_quaternion()
	_accumulated_mouse_motion = Vector2.ZERO


func capture_mouse() -> void:
	_set_mouse_captured(true)
	ready_to_play = true


func release_mouse() -> void:
	_set_mouse_captured(false)


func update_from_local(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Keep the settled drill-prototype movement axes. Sprint is intentionally
	# absent from this networking proof; Space/Ctrl remain vertical thrust.
	thrust = Vector3(
		Input.get_axis("thrust_left", "thrust_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_forward", "thrust_back"),
	)
	stabilizing = Input.is_action_pressed("stabilize")
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	drilling = (_mouse_captured and Input.is_mouse_button_pressed(DrillKnobs.DRILL_MOUSE_BUTTON))

	var mouse_motion := _accumulated_mouse_motion
	_accumulated_mouse_motion = Vector2.ZERO
	var roll_input := Input.get_axis("roll_left", "roll_right")
	var pitch := -mouse_motion.y * DrillMovementKnobs.MOUSE_SENSITIVITY
	var yaw := -mouse_motion.x * DrillMovementKnobs.MOUSE_SENSITIVITY
	var roll := -roll_input * DrillMovementKnobs.ROLL_RATE * delta

	_desired_basis = _desired_basis.rotated(_desired_basis.y, yaw)
	_desired_basis = _desired_basis.rotated(_desired_basis.x, pitch)
	_desired_basis = _desired_basis.rotated(_desired_basis.z, roll).orthonormalized()
	look_orientation = _desired_basis.get_rotation_quaternion()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and _mouse_captured:
		_accumulated_mouse_motion += event.screen_relative
	elif event.is_action_pressed("toggle_mouse_capture"):
		_set_mouse_captured(not _mouse_captured)


func _set_mouse_captured(should_capture: bool) -> void:
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
