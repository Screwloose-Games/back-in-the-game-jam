class_name ZeroGPlayer
extends CharacterBody3D

## Six-degrees-of-freedom suit-thruster controller for zero gravity.
##
## Thrust is applied along the body's own axes and momentum persists, so the
## player coasts until they counter-thrust or hit something. Nothing here reads
## a world "up": the body may end up at any orientation and stay there.
##
## Every tunable value lives in prototype_knobs.gd.

## Tumble rate about the body's own axes: x pitch, y yaw, z roll. Only ever
## non-zero in INERTIAL rotation mode; impacts do not impart spin.
var angular_velocity := Vector3.ZERO
## True while the stabilizers are held. Read by the debug HUD.
var stabilizers_engaged := false

var _spawn_transform: Transform3D
var _accumulated_mouse_motion := Vector2.ZERO
var _was_touching_surface := false
var _is_mouse_captured := false

@onready var _head_camera: Camera3D = $HeadCamera
@onready var _helmet_lamp: SpotLight3D = $HeadCamera/HelmetLamp


func _ready() -> void:
	_spawn_transform = global_transform
	_head_camera.far = PrototypeKnobs.CAMERA_FAR
	_helmet_lamp.spot_range = PrototypeKnobs.HELMET_LAMP_RANGE
	capture_mouse()


# Aiming is read in _input rather than _unhandled_input: while the mouse is
# captured the cursor sits at screen centre, so any Control there would eat the
# motion events before unhandled input ran.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _is_mouse_captured:
			# screen_relative is the raw device delta. relative is divided by
			# the canvas_items stretch scale, which would tie look sensitivity
			# to the window size.
			_accumulated_mouse_motion += event.screen_relative
	elif event.is_action_pressed("toggle_mouse_capture"):
		toggle_mouse_capture()
	elif event.is_action_pressed("reset_player"):
		respawn()


func _physics_process(delta: float) -> void:
	stabilizers_engaged = Input.is_action_pressed("stabilize")
	_update_orientation(delta)
	_update_velocity(delta)
	move_and_slide()
	_resolve_surface_contact(delta)


## Returns the current drift speed in metres per second.
func get_drift_speed() -> float:
	return velocity.length()


## Returns the player to their starting pose, fully at rest.
func respawn() -> void:
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_accumulated_mouse_motion = Vector2.ZERO
	_was_touching_surface = false
	global_transform = _spawn_transform


func capture_mouse() -> void:
	_set_mouse_captured(true)


func toggle_mouse_capture() -> void:
	_set_mouse_captured(not _is_mouse_captured)


func _set_mouse_captured(should_capture: bool) -> void:
	_is_mouse_captured = should_capture
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE
	)


func _update_orientation(delta: float) -> void:
	var mouse_motion := _accumulated_mouse_motion
	_accumulated_mouse_motion = Vector2.ZERO
	var roll_input := Input.get_axis("roll_left", "roll_right")

	if PrototypeKnobs.ROTATION_MODE == PrototypeKnobs.RotationMode.DIRECT:
		_rotate_about_own_axes(
			-mouse_motion.y * PrototypeKnobs.MOUSE_SENSITIVITY,
			-mouse_motion.x * PrototypeKnobs.MOUSE_SENSITIVITY,
			-roll_input * PrototypeKnobs.ROLL_RATE * delta
		)
		return

	var aim_gain := PrototypeKnobs.MOUSE_SENSITIVITY * PrototypeKnobs.ANGULAR_ACCELERATION
	angular_velocity.x += -mouse_motion.y * aim_gain
	angular_velocity.y += -mouse_motion.x * aim_gain
	angular_velocity.z += -roll_input * PrototypeKnobs.ROLL_RATE * delta
	angular_velocity = angular_velocity.limit_length(PrototypeKnobs.MAX_ANGULAR_SPEED)

	# Passive drag runs whether or not anything is held. It is what keeps a
	# flick from spinning you indefinitely; stabilizers then brake on top.
	angular_velocity = angular_velocity.lerp(
		Vector3.ZERO, minf(PrototypeKnobs.ANGULAR_DRAG * delta, 1.0)
	)

	if stabilizers_engaged:
		angular_velocity = angular_velocity.lerp(
			Vector3.ZERO, minf(PrototypeKnobs.ANGULAR_STABILIZER_RATE * delta, 1.0)
		)

	_rotate_about_own_axes(
		angular_velocity.x * delta, angular_velocity.y * delta, angular_velocity.z * delta
	)


## Applies successive rotations about the body's current local axes, so the
## result never depends on a world reference direction.
func _rotate_about_own_axes(pitch_delta: float, yaw_delta: float, roll_delta: float) -> void:
	var body_basis := global_transform.basis
	body_basis = body_basis.rotated(body_basis.y, yaw_delta)
	body_basis = body_basis.rotated(body_basis.x, pitch_delta)
	body_basis = body_basis.rotated(body_basis.z, roll_delta)
	# Repeated incremental rotations accumulate skew without this.
	global_transform.basis = body_basis.orthonormalized()


func _update_velocity(delta: float) -> void:
	var thrust_input := Vector3(
		Input.get_axis("thrust_left", "thrust_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_forward", "thrust_back")
	).limit_length(1.0)

	velocity += (
		global_transform.basis * thrust_input * PrototypeKnobs.THRUST_ACCELERATION * delta
	)

	if stabilizers_engaged:
		velocity = velocity.lerp(
			Vector3.ZERO, minf(PrototypeKnobs.LINEAR_STABILIZER_RATE * delta, 1.0)
		)

	velocity = velocity.limit_length(PrototypeKnobs.MAX_SPEED)


## Costs the player speed for touching the hull: a one-off hit when an impact
## starts, then steady friction for as long as they keep scraping. Neither
## imparts any spin - contact only affects linear velocity.
func _resolve_surface_contact(delta: float) -> void:
	var is_touching := get_slide_collision_count() > 0
	if is_touching and not _was_touching_surface:
		velocity *= PrototypeKnobs.COLLISION_ENERGY_RETAINED
	elif is_touching:
		velocity = velocity.lerp(Vector3.ZERO, minf(PrototypeKnobs.SCRAPE_FRICTION * delta, 1.0))
	_was_touching_surface = is_touching
