class_name PlayerTether
extends Node

## Clips the harness line to a carryable and applies the taut-only spring that
## caps how far you can get from it. Which end the haul moves falls out of the
## mass ratio: an unheld shared box weighs several times what the suit does, so
## going taut reels you back rather than towing the box after you.

signal clipped(object: RigidBody3D)
signal unclipped(object: RigidBody3D)

## Runs after the grip; both push the same two bodies and are independent.
const PHYSICS_PRIORITY := -30

@export var settings: PlayerSettings

## Set by PlayerNetworkDriver: peer 1 decides when this player clips on, so this
## copy must not answer the tether key on its own.
var externally_driven := false

var _object: RigidBody3D
var _object_anchor := Vector3.ZERO
var _rope := PlayerTetherRope.new()
## Length along the rope's whole shape, in metres.
var _distance := 0.0
## How much longer the rope is than the straight line between its anchors — the
## readable sign that it has gone the long way round something.
var _drape := 0.0
## How far the rope is stretched past its length. Reaches tether_break_stretch
## as the line parts.
var _strain := 0.0
var _rope_mesh := PlayerTetherRopeMesh.new()

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input
@onready var locomotion: PlayerLocomotion = %Locomotion
@onready var rope_view: MeshInstance3D = %TetherRopeView
@onready var anchor: Marker3D = %TetherAnchor


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerTether has no settings; running on PlayerSettings defaults.")
	_configure_rope()
	# The marker is driven by the setting rather than set in the scene, so the
	# two can never disagree about where the harness point is.
	anchor.position = settings.tether_anchor_offset
	if not externally_driven:
		input.tether_toggled.connect(toggle_clip)

	# The view is top_level, so parking its transform at the origin lets the rope
	# be redrawn straight in world space every frame.
	_rope_mesh.sides = settings.tether_rope_draw_sides
	_rope_mesh.radius = settings.tether_rope_draw_radius
	rope_view.mesh = _rope_mesh.read_mesh()
	rope_view.global_transform = Transform3D.IDENTITY
	rope_view.visible = false


func _physics_process(delta: float) -> void:
	_apply_tension(delta)
	_redraw()


func is_attached() -> bool:
	return _object != null


func tethered_object() -> RigidBody3D:
	return _object


## Length along the rope's whole shape, in metres. Zero when unclipped.
func distance() -> float:
	return _distance


## How much of the rope is going the long way round something.
func drape() -> float:
	return _drape


## How far the line is stretched past its length. Zero while slack.
func strain() -> float:
	return _strain


## Clips the line to a point on an object, in that object's own frame. The rope
## is laid out straight and hangs slack until you pull away.
func clip_to(object: RigidBody3D, clip_point: Vector3) -> void:
	if object == null:
		return
	_object = object
	_object_anchor = object.global_transform.affine_inverse() * clip_point
	_configure_rope()
	_rope.reset(clip_point, anchor.global_position, settings.tether_length)
	_distance = 0.0
	_strain = 0.0
	_drape = 0.0
	clipped.emit(object)


## Unclips. What you were moored to keeps drifting; you keep whatever the line
## had already done to you.
func unclip() -> void:
	if _object == null:
		return
	var released := _object
	_object = null
	_distance = 0.0
	_strain = 0.0
	_drape = 0.0
	rope_view.visible = false
	unclipped.emit(released)


func _configure_rope() -> void:
	_rope.segment_spacing = settings.tether_rope_segment
	_rope.iterations = settings.tether_rope_iterations
	_rope.point_damping = settings.tether_rope_damping
	_rope.spread = settings.tether_rope_spread
	_rope.contact_radius = settings.tether_rope_radius
	_rope.friction = settings.tether_rope_friction
	_rope.collision_layers = settings.tether_rope_layers


## Clips the line to what is targeted, or unclips what it is already on.
func toggle_clip() -> void:
	if _object != null:
		unclip()
		return
	var grab := get_parent().get_node_or_null("Grab") as PlayerGrab
	if grab == null or grab.targeted_object() == null:
		return
	clip_to(grab.targeted_object(), grab.target_point())


## A rope: nothing at all below its length, and past that a pull along its own
## line and no other.
func _apply_tension(delta: float) -> void:
	if _object == null:
		return

	var suit_point := anchor.global_position
	var object_point := _object.global_transform * _object_anchor
	var object_lever_arm := object_point - _object.global_position
	var object_point_velocity := PlayerSpring.point_velocity(
		_object.linear_velocity, _object.angular_velocity, object_lever_arm
	)

	# Both ends have to sit outside the hull before the rope hangs off them: an
	# anchor buried in a wall is the one case the rope cannot reason its way out.
	var space_state := body.get_world_3d().direct_space_state
	suit_point = _hold_anchor_clear(space_state, body.global_position, suit_point)
	object_point = _hold_anchor_clear(space_state, _object.global_position, object_point)

	_rope.step(delta, space_state, object_point, suit_point)
	_distance = _rope.measure_length()
	_drape = _distance - _rope.measure_span()
	_strain = maxf(_distance - settings.tether_length, 0.0)
	if _strain > settings.tether_break_stretch:
		unclip()
		return
	if is_zero_approx(_strain):
		return

	# Each end is hauled along its own first length of rope rather than toward
	# the far end. Draped over something those are different directions, and it
	# is the drape the pull is really against.
	var suit_run := suit_point - _rope.read_point_beside_suit()
	var object_run := object_point - _rope.read_point_beside_object()
	if suit_run.is_zero_approx() or object_run.is_zero_approx():
		return
	var suit_direction := suit_run.normalized()
	var object_direction := object_run.normalized()

	# How fast the rope is being paid out. Each end contributes only the part of
	# its motion along the rope; the rest is slack the tether has no view on.
	var stretch_rate := (
		body.velocity.dot(suit_direction) + object_point_velocity.dot(object_direction)
	)

	var pair_mass := PlayerSpring.reduced_mass(settings.player_mass, _object.mass)
	var tension := PlayerSpring.rope_tension(
		_strain,
		stretch_rate,
		PlayerSpring.stiffness(pair_mass, settings.tether_spring_frequency),
		PlayerSpring.damping(
			pair_mass, settings.tether_spring_frequency, settings.tether_spring_damping_ratio
		),
		settings.tether_max_force
	)

	_object.apply_impulse(-object_direction * tension * delta, object_lever_arm)
	locomotion.apply_link_velocity_change(
		-suit_direction * tension * delta / settings.player_mass,
		suit_point,
		settings.tether_spin_transfer
	)


## Brings an anchor back to the near side of any hull between it and the centre
## of the body it belongs to. Both centres are kept clear by their own colliders,
## so a cast from one always starts somewhere real.
func _hold_anchor_clear(
	space_state: PhysicsDirectSpaceState3D, body_center: Vector3, anchor_point: Vector3
) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		body_center, anchor_point, settings.tether_rope_layers
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return anchor_point
	var contact_point: Vector3 = hit["position"]
	var contact_normal: Vector3 = hit["normal"]
	return contact_point + contact_normal * settings.tether_rope_radius


## Draws the rope through the points it is actually simulated at. Nothing about
## it is physical, but it is the only thing telling you where the box you are
## moored to is and whether the line has gone taut.
func _redraw() -> void:
	var points := _rope.read_points()
	rope_view.visible = _object != null and points.size() >= 2
	if rope_view.visible:
		_rope_mesh.rebuild(points)
