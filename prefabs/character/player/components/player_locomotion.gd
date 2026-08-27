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

## A network driver calls step() itself so prediction and replay do not also
## receive a second movement step from this node's normal physics callback.
var externally_driven := false

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
	if externally_driven:
		return
	step(
		delta,
		input.thrust,
		input.look,
		input.roll,
		input.stabilize_held,
		input.sprint_held,
		true,
	)


## Advances one complete locomotion tick from explicit controls.
##
## Prediction and replay pass allow_shared_body_effects=false: rewinding a
## player must never apply a second impulse to a held world object.
func step(
	delta: float,
	thrust: Vector3,
	look_delta: Vector2,
	roll_input: float,
	stabilizing: bool,
	sprinting: bool,
	allow_shared_body_effects: bool,
) -> void:
	stabilizers_engaged = stabilizing
	_update_orientation(delta, look_delta, roll_input)
	_update_speed_cap(delta, sprinting)
	_update_velocity(delta, thrust, sprinting, allow_shared_body_effects)


func capture_prediction_state() -> Dictionary:
	return {
		"angular_velocity": angular_velocity,
		"speed_cap": _current_speed_cap,
	}


func restore_prediction_state(state: Dictionary) -> void:
	var raw_angular_velocity: Variant = state.get("angular_velocity", Vector3.ZERO)
	if typeof(raw_angular_velocity) == TYPE_VECTOR3:
		var restored_angular_velocity: Vector3 = raw_angular_velocity
		angular_velocity = (
			restored_angular_velocity.limit_length(settings.max_angular_speed)
			if restored_angular_velocity.is_finite()
			else Vector3.ZERO
		)

	var restored_speed_cap := float(state.get("speed_cap", settings.max_speed))
	if is_finite(restored_speed_cap):
		_current_speed_cap = clampf(
			restored_speed_cap,
			settings.max_speed,
			settings.max_speed * settings.sprint_speed_multiplier,
		)
	else:
		_current_speed_cap = settings.max_speed


func prediction_states_match(predicted: Dictionary, authoritative: Dictionary) -> bool:
	var raw_predicted_angular: Variant = predicted.get("angular_velocity", Vector3.ZERO)
	var raw_authoritative_angular: Variant = authoritative.get("angular_velocity", Vector3.ZERO)
	if (
		typeof(raw_predicted_angular) != TYPE_VECTOR3
		or typeof(raw_authoritative_angular) != TYPE_VECTOR3
	):
		return false
	var predicted_angular_velocity: Vector3 = raw_predicted_angular
	var authoritative_angular_velocity: Vector3 = raw_authoritative_angular
	var predicted_speed_cap := float(predicted.get("speed_cap", settings.max_speed))
	var authoritative_speed_cap := float(authoritative.get("speed_cap", settings.max_speed))
	return (
		predicted_angular_velocity.distance_to(authoritative_angular_velocity) <= 0.02
		and absf(predicted_speed_cap - authoritative_speed_cap) <= 0.05
	)


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


## A kick from something outside the suit: a blast, a shove, a lunge.
##
## Both halves in one call, so a hazard never touches `body.velocity` itself and the
## tumble stays a consequence of WHERE the push landed rather than a random spin.
func apply_external_impulse(impulse: Vector3, at: Vector3) -> void:
	var velocity_change := impulse / maxf(settings.player_mass, 0.001)
	body.velocity += velocity_change
	add_spin_from_impulse(velocity_change, at, 1.0)


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


func _update_orientation(delta: float, look_delta: Vector2, roll_input: float) -> void:
	var is_inertial := settings.rotation_mode == PlayerFlight.RotationMode.INERTIAL
	if is_inertial:
		angular_velocity = PlayerFlight.accumulate_spin(
			angular_velocity,
			look_delta,
			roll_input,
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
		aim_pitch = -look_delta.y * settings.mouse_sensitivity
		aim_yaw = -look_delta.x * settings.mouse_sensitivity
		aim_roll = -roll_input * settings.roll_rate * delta

	body.global_transform.basis = PlayerFlight.rotate_about_own_axes(
		body.global_transform.basis,
		aim_pitch + angular_velocity.x * delta,
		aim_yaw + angular_velocity.y * delta,
		aim_roll + angular_velocity.z * delta
	)


## Sprint raises the cap at once and it eases back down, so releasing sprint
## coasts to the walking cap instead of braking to it.
func _update_speed_cap(delta: float, sprinting: bool) -> void:
	var sprint_cap := settings.max_speed * settings.sprint_speed_multiplier
	if sprinting:
		_current_speed_cap = maxf(_current_speed_cap, sprint_cap)
		return
	_current_speed_cap = maxf(
		lerpf(
			_current_speed_cap, settings.max_speed, minf(settings.sprint_falloff_rate * delta, 1.0)
		),
		settings.max_speed
	)


func _update_velocity(
	delta: float, thrust: Vector3, sprinting: bool, allow_shared_body_effects: bool
) -> void:
	var held_object := _held_object() if allow_shared_body_effects else null
	var acceleration := settings.thrust_acceleration_for(sprinting)
	apply_braced_velocity_change(
		PlayerFlight.thrust_velocity_change(
			body.global_transform.basis, thrust, acceleration, delta
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
