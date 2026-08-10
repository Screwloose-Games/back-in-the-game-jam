class_name MultiplayerInputState
extends Node

## Player-owned controls sampled by ClientPredictor3D.
##
## The player body never changes authority: peer 1 still owns collisions and
## shared outcomes. This node converts local devices into bounded intent; the
## predictor sequences, validates, sends, and replays that intent.

@export var thrust := Vector3.ZERO:
	set(value):
		# A remote player may supply this value, so constrain it at the boundary.
		thrust = value.limit_length(1.0) if value.is_finite() else Vector3.ZERO

@export var look_orientation := Quaternion.IDENTITY:
	set(value):
		# Reject a degenerate quaternion and normalize everything else before the
		# host treats it as a requested facing direction.
		if value.is_finite() and value.length_squared() > 0.0001:
			look_orientation = value.normalized()

@export var stabilizing := false
@export var cranking := false

var _accumulated_mouse_motion := Vector2.ZERO
var _desired_basis := Basis.IDENTITY
var _mouse_captured := false


func begin_local_control(initial_basis: Basis) -> void:
	reset_local_orientation(initial_basis)
	# The demo's explicit Enter/Resume buttons request mouse capture. This keeps
	# browser pointer lock tied to a clear user gesture and makes laptop controls
	# discoverable before the player begins drifting through the room.
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func reset_local_orientation(authoritative_basis: Basis) -> void:
	if not is_multiplayer_authority():
		return
	_desired_basis = authoritative_basis.orthonormalized()
	look_orientation = _desired_basis.get_rotation_quaternion()
	_accumulated_mouse_motion = Vector2.ZERO


func capture_mouse() -> void:
	_set_mouse_captured(true)


## Samples this browser's controls. The player calls it only for the input node
## whose multiplayer authority matches the local peer ID.
func update_from_local(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Shift is an easier laptop fallback for downward thrust than Control. The
	# existing action remains valid, so either key works without project changes.
	var downward_strength := maxf(
		Input.get_action_strength("thrust_down"),
		Input.get_action_strength("sprint"),
	)
	var vertical_thrust := Input.get_action_strength("thrust_up") - downward_strength
	thrust = Vector3(
		Input.get_axis("thrust_left", "thrust_right"),
		vertical_thrust,
		Input.get_axis("thrust_forward", "thrust_back"),
	)
	stabilizing = Input.is_action_pressed("stabilize")
	cranking = Input.is_action_pressed("grab")

	var mouse_motion := _accumulated_mouse_motion
	_accumulated_mouse_motion = Vector2.ZERO
	var roll_input := Input.get_axis("roll_left", "roll_right")
	var pitch := -mouse_motion.y * MovementKnobs.MOUSE_SENSITIVITY
	var yaw := -mouse_motion.x * MovementKnobs.MOUSE_SENSITIVITY
	var roll := -roll_input * MovementKnobs.ROLL_RATE * delta

	_desired_basis = _desired_basis.rotated(_desired_basis.y, yaw)
	_desired_basis = _desired_basis.rotated(_desired_basis.x, pitch)
	_desired_basis = _desired_basis.rotated(_desired_basis.z, roll).orthonormalized()
	look_orientation = _desired_basis.get_rotation_quaternion()


func release_mouse() -> void:
	_set_mouse_captured(false)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Read the engine's actual state instead of assuming a Web pointer-lock
	# request succeeded synchronously.
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and _mouse_captured:
		# screen_relative is raw device movement and does not vary with canvas
		# stretch, which keeps browser window size from changing aim speed.
		_accumulated_mouse_motion += event.screen_relative
	elif event.is_action_pressed("toggle_mouse_capture"):
		_set_mouse_captured(not _mouse_captured)


func _set_mouse_captured(should_capture: bool) -> void:
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
