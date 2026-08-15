class_name PlayerLocomotion
extends Node

## Turns published input into the body's linear and angular motion each physics
## tick. It owns `angular_velocity`, so the grip, the tether and every impact
## add their spin through `add_spin_from_impulse` rather than keeping their own.

## Runs before the links, which need a current heading to aim their springs at.
const PHYSICS_PRIORITY := -80

@export var settings: PlayerSettings

## Tumble about the body's own axes: x pitch, y yaw, z roll.
var angular_velocity := Vector3.ZERO
var stabilizers_engaged := false

## Raised while sprint is held and eased back down after, so letting go coasts
## rather than braking.
var _current_speed_cap := 0.0

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerLocomotion has no settings; running on PlayerSettings defaults.")
	_current_speed_cap = settings.max_speed


func _physics_process(delta: float) -> void:
	stabilizers_engaged = input.stabilize_held
	_update_orientation(delta)
	_update_speed_cap(delta)
	_update_velocity(delta)


## The suit's tumble in world space. `angular_velocity` is kept in body-local
## axes, which is the wrong frame for comparing against a rigid body's spin.
func world_spin() -> Vector3:
	return PlayerFlight.world_spin(body.global_transform.basis, angular_velocity)


## Adds the spin a velocity change applied away from the centre of mass causes.
func add_spin_from_impulse(
	velocity_change: Vector3, application_point: Vector3, transfer: float
) -> void:
	var lever_arm := application_point - body.global_position
	angular_velocity += PlayerContact.spin_from_impulse(
		body.global_transform.basis, velocity_change, lever_arm, settings.player_mass, transfer
	)
	angular_velocity = angular_velocity.limit_length(settings.max_angular_speed)


## Adds a world-space angular impulse to the suit's own tumble.
func add_spin_from_angular_impulse(world_angular_impulse: Vector3, transfer: float) -> void:
	angular_velocity += PlayerContact.spin_from_angular_impulse(
		body.global_transform.basis, world_angular_impulse, transfer, settings.player_mass
	)
	angular_velocity = angular_velocity.limit_length(settings.max_angular_speed)


## Spends one frame of manoeuvring, braced against a held object so both bodies
## set off together instead of the load arriving through the hands on a lever.
func apply_braced_velocity_change(
	unloaded_velocity_change: Vector3, held_object: RigidBody3D
) -> void:
	var object_share := 0.0
	if held_object != null:
		object_share = PlayerFlight.braced_object_share(
			settings.grip_bracing, settings.player_mass, held_object.mass
		)
		if not is_zero_approx(object_share):
			held_object.apply_central_impulse(
				unloaded_velocity_change * settings.player_mass * object_share
			)
	body.velocity += unloaded_velocity_change * (1.0 - object_share)


## Adds a link's pull to the body and the spin it causes, then re-caps speed.
func apply_link_velocity_change(
	velocity_change: Vector3, application_point: Vector3, spin_transfer: float
) -> void:
	body.velocity = (body.velocity + velocity_change).limit_length(_current_speed_cap)
	if not is_zero_approx(spin_transfer):
		add_spin_from_impulse(velocity_change, application_point, spin_transfer)


## Brings the body fully to rest, keeping its pose.
func halt() -> void:
	body.velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_current_speed_cap = settings.max_speed


func _update_orientation(delta: float) -> void:
	var is_inertial := settings.rotation_mode == PlayerFlight.RotationMode.INERTIAL
	if is_inertial:
		angular_velocity = PlayerFlight.accumulate_spin(
			angular_velocity,
			input.look,
			input.roll,
			settings.aim_gain(),
			settings.roll_rate,
			settings.max_angular_speed,
			delta
		)

	# Drag runs in both modes, because impacts and the grip write spin in DIRECT
	# too. Stabilisers brake on top of it.
	angular_velocity = PlayerFlight.damp_spin(angular_velocity, settings.angular_drag, delta)
	if stabilizers_engaged:
		angular_velocity = PlayerFlight.damp_spin(
			angular_velocity, settings.angular_stabilizer_rate, delta
		)

	# DIRECT steers straight from the mouse on top of whatever spin is left;
	# INERTIAL has already folded aim into the tumble.
	var aim_pitch := 0.0
	var aim_yaw := 0.0
	var aim_roll := 0.0
	if not is_inertial:
		aim_pitch = -input.look.y * settings.mouse_sensitivity
		aim_yaw = -input.look.x * settings.mouse_sensitivity
		aim_roll = -input.roll * settings.roll_rate * delta

	body.global_transform.basis = PlayerFlight.rotate_about_own_axes(
		body.global_transform.basis,
		aim_pitch + angular_velocity.x * delta,
		aim_yaw + angular_velocity.y * delta,
		aim_roll + angular_velocity.z * delta
	)


## Sprint raises the cap at once and it eases back down, so releasing sprint
## coasts to the walking cap instead of braking to it.
func _update_speed_cap(delta: float) -> void:
	var sprint_cap := settings.max_speed * settings.sprint_speed_multiplier
	if input.sprint_held:
		_current_speed_cap = maxf(_current_speed_cap, sprint_cap)
		return
	_current_speed_cap = maxf(
		lerpf(
			_current_speed_cap, settings.max_speed, minf(settings.sprint_falloff_rate * delta, 1.0)
		),
		settings.max_speed
	)


func _update_velocity(delta: float) -> void:
	var held_object := _held_object()
	var acceleration := settings.thrust_acceleration_for(input.sprint_held)
	apply_braced_velocity_change(
		PlayerFlight.thrust_velocity_change(
			body.global_transform.basis, input.thrust, acceleration, delta
		),
		held_object
	)

	# Braking is thrust pointed backwards as far as a held load is concerned, so
	# it goes through the same brace.
	if stabilizers_engaged:
		apply_braced_velocity_change(
			PlayerFlight.stabilizer_velocity_change(
				body.velocity, settings.linear_stabilizer_rate, delta
			),
			held_object
		)

	body.velocity = body.velocity.limit_length(_current_speed_cap)


## The grip component is optional, so a prefab without one still flies.
func _held_object() -> RigidBody3D:
	var grab := get_parent().get_node_or_null("Grab") as PlayerGrab
	if grab == null:
		return null
	return grab.held_object()
