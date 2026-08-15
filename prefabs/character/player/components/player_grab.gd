class_name PlayerGrab
extends Node

## Takes hold of a carryable with two hands. Each hand takes its own point and
## gets its own spring, so every way the load could turn out of your hands shows
## up as the two disagreeing and unwinds itself; the one turn a pair cannot hold
## is a roll about the line through them, and `_apply_twist` holds that.

signal took_hold(object: RigidBody3D)
signal let_go(object: RigidBody3D)

## Runs after locomotion, which has already set this frame's heading.
const PHYSICS_PRIORITY := -40

@export var settings: PlayerSettings

## The carryable in your hands, or null.
var _held: RigidBody3D
## A carryable under the crosshair, attached or not. The reticle reads this to
## say "grabbable" before you commit.
var _targeted: RigidBody3D
## Where each hand has hold, in the object's local space. Fixed at grab time.
var _hand_anchors: Array[Vector3] = []
## The pose the load was caught in and the pose it eases to, both suit-local.
var _start_pose := Transform3D.IDENTITY
var _carry_pose := Transform3D.IDENTITY
var _settle := 0.0
var _free_mass := 0.0
var _strain := 0.0

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input
@onready var locomotion: PlayerLocomotion = %Locomotion
@onready var grab_ray: RayCast3D = %GrabRay


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerGrab has no settings; running on PlayerSettings defaults.")
	grab_ray.target_position = Vector3(0.0, 0.0, -settings.grab_range)
	input.grab_toggled.connect(_on_grab_toggled)


func _physics_process(delta: float) -> void:
	_update_target()
	_apply_grip(delta)


func held_object() -> RigidBody3D:
	return _held


func targeted_object() -> RigidBody3D:
	return _targeted


## Where on the target the ray landed, in world space.
func target_point() -> Vector3:
	return grab_ray.get_collision_point()


func is_holding() -> bool:
	return _held != null


## The furthest either hand has been pulled off its hold, in metres. Reaches
## grip_break_distance as the grip slips.
func strain() -> float:
	return _strain


## Lets go. The load keeps its momentum but gets its free mass back, so what
## drifts off is heavier than what you were holding. Any tether stays clipped.
func release() -> void:
	if _held == null:
		return
	var released := _held
	released.mass = _free_mass
	_held = null
	_hand_anchors = []
	_settle = 0.0
	_strain = 0.0
	let_go.emit(released)


## Puts both hands on the object, straddling the aimed-at point along your own
## right axis. The hands hold fixed points from then on; what moves is the pose
## they pull toward, which starts where the object already was — that is what
## makes taking hold jolt-free.
func take_hold_of(object: RigidBody3D, grab_point: Vector3) -> void:
	if object == null:
		return
	_held = object
	_free_mass = object.mass
	object.mass = settings.carry_object_held_mass

	var object_inverse := object.global_transform.affine_inverse()
	var half_span := body.global_transform.basis.x * settings.grip_hand_separation * 0.5
	_hand_anchors = [
		object_inverse * (grab_point - half_span),
		object_inverse * (grab_point + half_span),
	]

	_start_pose = body.global_transform.affine_inverse() * object.global_transform
	# Squared to the nearest axis, not to a nominal upright: on a roughly cubic
	# load every face is as good as any other.
	_carry_pose = Transform3D(
		PlayerSpring.snap_basis_to_axes(_start_pose.basis), settings.grip_carry_offset
	)
	_settle = 0.0
	_strain = 0.0
	took_hold.emit(object)


func _on_grab_toggled() -> void:
	if _held != null:
		release()
		return
	if _targeted == null:
		return
	var hands := get_parent().get_node_or_null("Hands") as PlayerHands
	if hands != null and not hands.can_take_hold():
		return
	take_hold_of(_targeted, target_point())


## The ray only collides with the carryable layer, so anything it reports is
## fair game and needs no filtering.
func _update_target() -> void:
	grab_ray.force_raycast_update()
	_targeted = grab_ray.get_collider() as RigidBody3D


## Two springs in parallel between the same pair of bodies are twice the spring
## one is, so each hand gets its share of the pair's reduced mass — that keeps
## grip_spring_frequency the frequency of the grip as a whole.
func _apply_grip(delta: float) -> void:
	if _held == null:
		return

	_settle = minf(_settle + delta / maxf(settings.grip_settle_time, 0.0001), 1.0)
	var target_pose := body.global_transform * _blend_toward_carry_pose()

	var hand_count := _hand_anchors.size()
	var pair_mass := PlayerSpring.reduced_mass(settings.player_mass, _held.mass) / float(hand_count)
	var stiffness := PlayerSpring.stiffness(pair_mass, settings.grip_spring_frequency)
	var damping := PlayerSpring.damping(
		pair_mass, settings.grip_spring_frequency, settings.grip_spring_damping_ratio
	)
	var force_ceiling := settings.grip_max_force / float(hand_count)

	# Both hands are measured before either is pushed, because the grip slips as
	# a unit: one hand torn off means the load is gone, and letting the other
	# spend a frame hauling alone would fling it as it went.
	var hand_points := PackedVector3Array()
	var suit_points := PackedVector3Array()
	_strain = 0.0
	for anchor: Vector3 in _hand_anchors:
		var hand_point := _held.global_transform * anchor
		var suit_point := target_pose * anchor
		hand_points.append(hand_point)
		suit_points.append(suit_point)
		_strain = maxf(_strain, hand_point.distance_to(suit_point))

	if _strain > settings.grip_break_distance:
		release()
		return

	var world_spin := locomotion.world_spin()
	for index: int in range(hand_points.size()):
		var hand_point := hand_points[index]
		var suit_point := suit_points[index]
		var lever_arm := hand_point - _held.global_position
		# Both ends are points on spinning bodies, so both spins feed how fast
		# the gap opens. Damping against the suit's tumble is most of what stops
		# the load wallowing when you turn.
		var hand_velocity := PlayerSpring.point_velocity(
			_held.linear_velocity, _held.angular_velocity, lever_arm
		)
		var suit_point_velocity := PlayerSpring.point_velocity(
			body.velocity, world_spin, suit_point - body.global_position
		)
		var force := PlayerSpring.force(
			suit_point - hand_point,
			hand_velocity - suit_point_velocity,
			stiffness,
			damping,
			force_ceiling
		)
		_push_link_force(delta, force, lever_arm, -force, suit_point, settings.grip_spin_transfer)

	_apply_twist(delta, target_pose.basis)


## Holds the roll a pair of hands cannot: a rigid body is free to spin about the
## axis joining any two of its points however hard they are held. Read it as
## wrist stiffness, and it is deliberately the weakest part of the grip.
func _apply_twist(delta: float, target_basis: Basis) -> void:
	if is_zero_approx(settings.grip_twist_frequency) or _hand_anchors.size() < 2:
		return

	var pose := _held.global_transform
	var hand_span := pose * _hand_anchors[1] - pose * _hand_anchors[0]
	if hand_span.is_zero_approx():
		return
	var twist_axis := hand_span.normalized()

	# Only the error along the hand axis is this spring's business; the rest is
	# the two hands' job, and answering it here would double their stiffness.
	var orientation_error := PlayerSpring.measure_rotation(
		target_basis * pose.basis.orthonormalized().inverse()
	)
	var twist_error := orientation_error.dot(twist_axis)
	var twist_rate := (_held.angular_velocity - locomotion.world_spin()).dot(twist_axis)

	var inertia := _measure_inertia_about(twist_axis)
	var stiffness := PlayerSpring.stiffness(inertia, settings.grip_twist_frequency)
	var damping := PlayerSpring.damping(
		inertia, settings.grip_twist_frequency, settings.grip_twist_damping_ratio
	)
	var torque := clampf(
		twist_error * stiffness - twist_rate * damping,
		-settings.grip_twist_max_torque,
		settings.grip_twist_max_torque
	)

	var angular_impulse := twist_axis * torque * delta
	_held.apply_torque_impulse(angular_impulse)
	locomotion.add_spin_from_angular_impulse(-angular_impulse, settings.grip_twist_spin_transfer)


## The held object's moment of inertia about a world axis, taken from the
## physics server so the wrist spring stays honest for any shape.
func _measure_inertia_about(world_axis: Vector3) -> float:
	var state := PhysicsServer3D.body_get_direct_state(_held.get_rid())
	if state == null:
		return _held.mass
	var inverse_inertia := world_axis.dot(state.inverse_inertia_tensor * world_axis)
	if inverse_inertia <= 0.0:
		return _held.mass
	return 1.0 / inverse_inertia


## The suit-local pose the hands pull toward this frame, eased from where the
## load was caught to where it is carried.
func _blend_toward_carry_pose() -> Transform3D:
	var eased := smoothstep(0.0, 1.0, _settle)
	var rotation := _start_pose.basis.get_rotation_quaternion().slerp(
		_carry_pose.basis.get_rotation_quaternion(), eased
	)
	return Transform3D(Basis(rotation), _start_pose.origin.lerp(_carry_pose.origin, eased))


## Hands one frame of link force to both ends: the load gets an impulse, the
## suit gets the equal and opposite one. Which of them noticeably moves is
## decided entirely by the mass ratio.
func _push_link_force(
	delta: float,
	object_force: Vector3,
	object_lever_arm: Vector3,
	suit_force: Vector3,
	suit_point: Vector3,
	spin_transfer: float
) -> void:
	_held.apply_impulse(object_force * delta, object_lever_arm)
	locomotion.apply_link_velocity_change(
		suit_force * delta / settings.player_mass, suit_point, spin_transfer
	)
