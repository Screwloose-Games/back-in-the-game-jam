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
## True while sprint is held. Read by the debug HUD.
var sprint_engaged := false

var _spawn_transform: Transform3D
var _current_speed_cap := PrototypeKnobs.MAX_SPEED
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
	sprint_engaged = Input.is_action_pressed("sprint")
	_update_orientation(delta)
	_update_velocity(delta)
	# move_and_slide reports what was hit but resolves contact its own way, so
	# the approach velocity has to be kept to compute the bounce afterwards.
	var approach_velocity := velocity
	move_and_slide()
	_resolve_surface_contact(delta, approach_velocity)


## Returns the current drift speed in metres per second.
func get_drift_speed() -> float:
	return velocity.length()


## Returns the player to their starting pose, fully at rest.
func respawn() -> void:
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_accumulated_mouse_motion = Vector2.ZERO
	_current_speed_cap = PrototypeKnobs.MAX_SPEED
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

	var is_inertial := PrototypeKnobs.ROTATION_MODE == PrototypeKnobs.RotationMode.INERTIAL
	if is_inertial:
		var aim_gain := PrototypeKnobs.MOUSE_SENSITIVITY * PrototypeKnobs.ANGULAR_ACCELERATION
		angular_velocity.x += -mouse_motion.y * aim_gain
		angular_velocity.y += -mouse_motion.x * aim_gain
		angular_velocity.z += -roll_input * PrototypeKnobs.ROLL_RATE * delta
		angular_velocity = angular_velocity.limit_length(PrototypeKnobs.MAX_ANGULAR_SPEED)

	_damp_angular_velocity(delta)

	# Both modes carry angular_velocity, because impacts write to it. DIRECT
	# additionally steers straight from the mouse on top of whatever spin a
	# collision has left you with; INERTIAL has already folded aim into it.
	var aim_pitch := 0.0
	var aim_yaw := 0.0
	var aim_roll := 0.0
	if not is_inertial:
		aim_pitch = -mouse_motion.y * PrototypeKnobs.MOUSE_SENSITIVITY
		aim_yaw = -mouse_motion.x * PrototypeKnobs.MOUSE_SENSITIVITY
		aim_roll = -roll_input * PrototypeKnobs.ROLL_RATE * delta

	_rotate_about_own_axes(
		aim_pitch + angular_velocity.x * delta,
		aim_yaw + angular_velocity.y * delta,
		aim_roll + angular_velocity.z * delta
	)


## Passive drag runs whether or not anything is held; it is what stops a flick
## or an impact spinning you indefinitely. Stabilizers brake on top of it.
func _damp_angular_velocity(delta: float) -> void:
	if angular_velocity.is_zero_approx():
		return
	angular_velocity = angular_velocity.lerp(
		Vector3.ZERO, minf(PrototypeKnobs.ANGULAR_DRAG * delta, 1.0)
	)
	if stabilizers_engaged:
		angular_velocity = angular_velocity.lerp(
			Vector3.ZERO, minf(PrototypeKnobs.ANGULAR_STABILIZER_RATE * delta, 1.0)
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

	var thrust_acceleration := PrototypeKnobs.THRUST_ACCELERATION
	if sprint_engaged:
		thrust_acceleration *= PrototypeKnobs.SPRINT_ACCELERATION_MULTIPLIER

	velocity += global_transform.basis * thrust_input * thrust_acceleration * delta

	if stabilizers_engaged:
		velocity = velocity.lerp(
			Vector3.ZERO, minf(PrototypeKnobs.LINEAR_STABILIZER_RATE * delta, 1.0)
		)

	_update_speed_cap(delta)
	velocity = velocity.limit_length(_current_speed_cap)


## Tracks the ceiling the speed is clamped to. Sprint raises it immediately, so
## the boost is there the moment Shift goes down, and lowers it gradually, so
## releasing sprint coasts back down to MAX_SPEED instead of snapping.
##
## The cap stays a hard clamp throughout - easing the clamp itself rather than
## the speed is what keeps thrust from outrunning the ceiling on the way down.
func _update_speed_cap(delta: float) -> void:
	var target_speed_cap := PrototypeKnobs.MAX_SPEED
	if sprint_engaged:
		target_speed_cap *= PrototypeKnobs.SPRINT_SPEED_MULTIPLIER

	if target_speed_cap >= _current_speed_cap:
		_current_speed_cap = target_speed_cap
	else:
		_current_speed_cap = move_toward(
			_current_speed_cap, target_speed_cap, PrototypeKnobs.SPRINT_FALLOFF_RATE * delta
		)


## Resolves a hull contact as an impulse rather than a flat speed penalty.
##
## The approach velocity is split into the part driving into the surface and
## the part running along it. The first is thrown back out scaled by
## restitution, which is what deflects your heading; the second is scrubbed by
## friction, and that same friction acts at the contact point rather than at
## the centre of mass, so it also twists the body.
##
## Only the frame an impact begins gets this treatment. Once you are already
## riding a surface, re-applying restitution every frame would buzz you off a
## wall you are deliberately thrusting against, so sustained contact falls
## through to plain friction.
func _resolve_surface_contact(delta: float, approach_velocity: Vector3) -> void:
	var contact_count := get_slide_collision_count()
	if contact_count == 0:
		_was_touching_surface = false
		return

	var was_already_touching := _was_touching_surface
	_was_touching_surface = true

	# Immovable hull and loose debris need completely different answers, so
	# split the frame's contacts before resolving either.
	var hull_normal := Vector3.ZERO
	var hull_point := Vector3.ZERO
	var hull_contact_count := 0
	var debris_contacts: Array[KinematicCollision3D] = []

	for index in contact_count:
		var contact := get_slide_collision(index)
		if contact.get_collider() is RigidBody3D:
			debris_contacts.append(contact)
		else:
			hull_normal += contact.get_normal()
			hull_point += contact.get_position()
			hull_contact_count += 1

	if hull_contact_count > 0:
		_resolve_hull_contact(
			delta,
			approach_velocity,
			hull_normal,
			hull_point / hull_contact_count,
			was_already_touching
		)

	for contact in debris_contacts:
		_shove_debris(contact, approach_velocity, was_already_touching)


func _resolve_hull_contact(
	delta: float,
	approach_velocity: Vector3,
	summed_normal: Vector3,
	contact_point: Vector3,
	was_already_touching: bool
) -> void:
	if was_already_touching:
		velocity = velocity.lerp(Vector3.ZERO, minf(PrototypeKnobs.SCRAPE_FRICTION * delta, 1.0))
		return

	# Normals that cancel out mean opposing surfaces - wedged, with nowhere to
	# bounce to. Dump the speed instead of picking a meaningless direction.
	if summed_normal.length_squared() < 0.0001:
		velocity = Vector3.ZERO
		return
	var contact_normal := summed_normal.normalized()

	var closing_speed := approach_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		# Touched a surface without driving into it; nothing to rebound.
		return

	var into_surface := contact_normal * closing_speed
	var along_surface := approach_velocity - into_surface

	velocity = (
		along_surface * (1.0 - PrototypeKnobs.COLLISION_FRICTION)
		- into_surface * PrototypeKnobs.COLLISION_RESTITUTION
	)

	_apply_impact_spin(along_surface, contact_point)


## Resolves a hit against loose debris as a two-body momentum exchange, so the
## same collision both redirects the player and sends the object tumbling. The
## mass ratio does all the work: something far lighter than PLAYER_MASS gets
## swatted aside barely slowing you, something far heavier shoves you off
## course while still giving way.
##
## move_and_slide treats a RigidBody3D as an obstacle and has already stripped
## the closing speed out of velocity, so the pre-move approach velocity is what
## the exchange has to be computed from.
func _shove_debris(
	contact: KinematicCollision3D, approach_velocity: Vector3, was_already_touching: bool
) -> void:
	var debris := contact.get_collider() as RigidBody3D
	if debris == null or debris.mass <= 0.0:
		return

	var contact_normal := contact.get_normal()
	var contact_point := contact.get_position()
	var relative_velocity := approach_velocity - debris.linear_velocity
	var closing_speed := relative_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		return

	# Bounce only on the frame contact begins; sustained contact becomes a
	# steady push, which is what lets you shoulder something out of the way
	# instead of pinballing off it.
	var restitution := 0.0 if was_already_touching else PrototypeKnobs.COLLISION_RESTITUTION
	var reduced_mass := 1.0 / (1.0 / PrototypeKnobs.PLAYER_MASS + 1.0 / debris.mass)
	var impulse_magnitude := -(1.0 + restitution) * closing_speed * reduced_mass

	velocity += contact_normal * (impulse_magnitude / PrototypeKnobs.PLAYER_MASS)
	debris.apply_impulse(
		-contact_normal * impulse_magnitude, contact_point - debris.global_position
	)

	var mass_ratio := debris.mass / (debris.mass + PrototypeKnobs.PLAYER_MASS)
	var along_surface := relative_velocity - contact_normal * closing_speed
	_apply_impact_spin(along_surface * mass_ratio, contact_point)


## Friction acts where the body actually touched, not at its centre, so it
## applies a torque proportional to that offset. A square-on hit has no lever
## and produces no spin; a graze has a long one and tumbles you.
func _apply_impact_spin(along_surface: Vector3, contact_point: Vector3) -> void:
	if is_zero_approx(PrototypeKnobs.COLLISION_SPIN_TRANSFER):
		return

	var friction_impulse := -along_surface * PrototypeKnobs.COLLISION_FRICTION
	var lever_arm := contact_point - global_position
	var world_torque := lever_arm.cross(friction_impulse)

	# angular_velocity is held in body-local axes, so the torque has to come
	# back out of world space before it can be added.
	angular_velocity += (
		global_transform.basis.inverse() * world_torque * PrototypeKnobs.COLLISION_SPIN_TRANSFER
	)
	angular_velocity = angular_velocity.limit_length(PrototypeKnobs.MAX_ANGULAR_SPEED)
