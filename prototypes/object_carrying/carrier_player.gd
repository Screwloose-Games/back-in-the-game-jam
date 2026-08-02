class_name CarrierPlayer
extends CharacterBody3D

## Six-degrees-of-freedom suit-thruster controller that can take hold of a
## heavy module and haul it around.
##
## The suit itself behaves exactly as it does in the navigation prototype:
## thrust along the body's own axes, momentum that persists, no world "up".
## What is new is the two ways of being attached to the module, which are
## independent - either, both, or neither can be live at once.
##
## The GRIP is two hands. Each takes its own point on the module and gets its
## own spring, and because the two pull toward two points fixed to the suit,
## every way the module could turn out of your hands shows up as the springs
## disagreeing and unwinds itself. That is what one anchor could not do: it can
## only haul the module's centre about while it pivots freely on the grab
## point. The one turn a pair of hands cannot hold is a roll about the line
## running through them, and _apply_grip_twist holds that.
##
## The TETHER is a rope clipped to a harness point behind you. It does nothing
## until it pulls taut, and then only pulls along its own line. It is simulated
## as a chain of points that collide with the hull (see tether_rope.gd), and
## each end is hauled along its own first length of it, so a tether taken
## around a pillar hauls you toward the pillar.
##
## Thrusting with the module held does not go through either of them. The suit
## and the module are given their shares of the burst directly, so they set off
## together and the hands are left holding only the module's own wandering; see
## _apply_thrust for why.
##
## Both end at _push_link_force, which is where the two bodies actually get
## moved: the module gets an impulse, the suit gets the equal and opposite one.
## Which of them noticeably moves is decided entirely by the mass ratio, and
## the module has two masses. Held, it is heavy enough that hauling it costs
## most of your thrust. Let go of, it is heavier still, which is what makes a
## taut tether reel you in toward the module rather than towing it after you.
##
## Every tunable value lives in carry_knobs.gd.

## Tumble rate about the body's own axes: x pitch, y yaw, z roll. Only ever
## non-zero in INERTIAL rotation mode; impacts do not impart spin.
var angular_velocity := Vector3.ZERO
## True while the stabilizers are held. Read by the debug HUD.
var stabilizers_engaged := false

var _spawn_transform: Transform3D
var _accumulated_mouse_motion := Vector2.ZERO
var _was_touching_surface := false
var _is_mouse_captured := false

## The module currently in your hands, or null.
var _held_object: RigidBody3D
## The module currently on the end of the tether, or null. Nothing ties this to
## _held_object: you can be holding what you are clipped to, clipped to
## something you have set down, or neither.
var _tethered_object: RigidBody3D
## A carryable the grab ray is on right now, attached or not. Read by the HUD
## so the crosshair can say "this is grabbable" before you commit.
var _targeted_object: RigidBody3D

## Where each hand has hold of the module, in the module's local space. Fixed
## at the moment of grabbing and empty whenever nothing is held.
var _hand_object_anchors: Array[Vector3] = []
## The module's pose in suit-local space at the moment it was caught, and the
## pose it is being eased toward. The hands pull toward a blend of the two, so
## taking hold opens at zero tension whatever angle you came in at.
var _grip_start_pose := Transform3D.IDENTITY
var _grip_carry_pose := Transform3D.IDENTITY
## How far along the ease from one to the other, 0 to 1.
var _grip_settle := 0.0
## What the module weighed before it was picked up, restored when it is let go.
var _held_object_free_mass := 0.0
## The furthest either hand has been pulled off its hold, in metres. Reaches
## GRIP_BREAK_DISTANCE at the instant the grip slips. Read by the HUD.
var _grip_strain := 0.0

## Where the tether is clipped to the module, in the module's local space, and
## to the suit, in the suit's.
var _tether_object_anchor := Vector3.ZERO
var _tether_suit_anchor := Vector3.ZERO
## The simulated rope. The grip is a pair of straight springs and has no shape
## to keep, so this belongs to the tether alone.
var _tether_rope := TetherRope.new()
## Length of the rope along its whole shape, in metres. Read by the HUD.
var _tether_distance := 0.0
## How much longer the rope is than the straight line between its anchors, in
## metres. It is the readable sign that the rope has gone the long way round
## something. Read by the HUD.
var _tether_drape := 0.0
## How far the rope is stretched past TETHER_LENGTH, in metres. Zero while it
## is slack, and reaches TETHER_BREAK_STRETCH as the line parts. Read by the
## HUD.
var _tether_strain := 0.0

@onready var _head_camera: Camera3D = $HeadCamera
@onready var _helmet_lamp: SpotLight3D = $HeadCamera/HelmetLamp
@onready var _grab_ray: RayCast3D = $HeadCamera/GrabRay
@onready var _tether_line: MeshInstance3D = $TetherLine

## The drawn rope: a ring of vertices around every point the rope is simulated
## at, rebuilt every frame from wherever those points ended up.
var _tether_mesh := ArrayMesh.new()
var _tether_tube_vertices := PackedVector3Array()
var _tether_tube_normals := PackedVector3Array()
## Which vertices make which faces. The rope's point count is fixed from the
## moment it is laid out, so this is worked out once rather than every frame.
var _tether_tube_indices := PackedInt32Array()


func _ready() -> void:
	# Whoever built this scene is responsible for putting the player at
	# CarryKnobs.PLAYER_SPAWN before it enters the tree; the pose it arrives
	# with is the one R returns to.
	_spawn_transform = global_transform
	_head_camera.far = CarryKnobs.CAMERA_FAR
	_helmet_lamp.spot_range = CarryKnobs.HELMET_LAMP_RANGE
	_grab_ray.target_position = Vector3(0.0, 0.0, -CarryKnobs.GRAB_RANGE)

	# The line node is top_level, so parking its transform at the origin lets
	# the tether be redrawn straight in world space every frame.
	_tether_line.mesh = _tether_mesh
	_tether_line.global_transform = Transform3D.IDENTITY

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
	# Aim has already moved this frame, so the ray reports what the crosshair
	# is actually on. Grabbing is polled here rather than handled in _input for
	# the same reason - the ray has to be current before a link is decided.
	_update_grab_target()
	if Input.is_action_just_pressed("grab"):
		_toggle_grip()
	if Input.is_action_just_pressed("toggle_tether"):
		_toggle_tether()

	_update_velocity(delta)
	_apply_carry_force(delta)
	# move_and_slide reports what was hit but resolves contact its own way, so
	# the approach velocity has to be kept to compute the bounce afterwards.
	var approach_velocity := velocity
	move_and_slide()
	_resolve_surface_contact(delta, approach_velocity)
	# Drawn last, from where both bodies actually ended up.
	_update_tether_line()


## Returns the current drift speed in metres per second.
func get_drift_speed() -> float:
	return velocity.length()


## The module in your hands, or null if empty-handed.
func get_held_object() -> RigidBody3D:
	return _held_object


## The module on the end of the tether, or null if unclipped.
func get_tethered_object() -> RigidBody3D:
	return _tethered_object


## The carryable under the crosshair and within reach, or null.
func get_targeted_object() -> RigidBody3D:
	return _targeted_object


## The furthest either hand has been pulled off its hold, in metres. Zero when
## empty-handed, and it reaches GRIP_BREAK_DISTANCE as the grip slips.
func get_grip_strain() -> float:
	return _grip_strain


## Length of the rope along its whole shape, in metres. Zero when unclipped.
func get_tether_distance() -> float:
	return _tether_distance


## How much longer the rope is than the straight line between its anchors, in
## metres. Near zero on a taut clear run, and climbing as the rope drapes over
## things or gathers slack behind you.
func get_tether_drape() -> float:
	return _tether_drape


## How far the rope is stretched past TETHER_LENGTH, in metres. Zero while it
## is slack, and it reaches TETHER_BREAK_STRETCH as the line parts.
func get_tether_strain() -> float:
	return _tether_strain


## Returns the player to their starting pose, fully at rest, empty-handed and
## unclipped.
func respawn() -> void:
	release_grip()
	unclip_tether()
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_accumulated_mouse_motion = Vector2.ZERO
	_was_touching_surface = false
	global_transform = _spawn_transform


## Lets go with the hands. The module keeps whatever momentum it had - nothing
## is zeroed, so releasing mid-haul leaves it coasting away on its own - but it
## gets its free mass back, so what drifts off is heavier than what you were
## holding. Any tether stays clipped on.
func release_grip() -> void:
	if _held_object != null:
		_held_object.mass = _held_object_free_mass
	_held_object = null
	_hand_object_anchors = []
	_grip_settle = 0.0
	_grip_strain = 0.0


## Unclips the line. What you were moored to keeps drifting wherever it was
## going; you keep whatever the line had already done to you.
func unclip_tether() -> void:
	_tethered_object = null
	_tether_distance = 0.0
	_tether_strain = 0.0
	_tether_drape = 0.0


func capture_mouse() -> void:
	_set_mouse_captured(true)


func toggle_mouse_capture() -> void:
	_set_mouse_captured(not _is_mouse_captured)


func _set_mouse_captured(should_capture: bool) -> void:
	_is_mouse_captured = should_capture
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE
	)


# --- Carry link ------------------------------------------------------------


## The ray only collides with the carryable layer, so anything it reports is
## fair game and no filtering by type is needed.
func _update_grab_target() -> void:
	_grab_ray.force_raycast_update()
	_targeted_object = _grab_ray.get_collider() as RigidBody3D


func _toggle_grip() -> void:
	if _held_object != null:
		release_grip()
	elif _targeted_object != null:
		_take_hold_of(_targeted_object, _grab_ray.get_collision_point())


func _toggle_tether() -> void:
	if _tethered_object != null:
		unclip_tether()
	elif _targeted_object != null:
		_clip_tether_to(_targeted_object, _grab_ray.get_collision_point())


## Puts both hands on the module, straddling the point the ray hit along your
## own right axis, and records where the module was so it can be brought square
## from there.
##
## The hands hold fixed points on the module, so where they land is what the
## grip is working with from then on. What moves is the pose they pull those
## points toward: it starts as the pose the module is already in, which is what
## makes taking hold jolt-free, and eases to the carry pose over
## GRIP_SETTLE_TIME.
##
## The carry pose is squared up to the nearest axis rather than to a nominal
## upright, because on a roughly cubic module every face is as good as any
## other and rotating one most of a turn to reach a particular one would read
## as the module being wrestled rather than caught.
func _take_hold_of(object: RigidBody3D, grab_point: Vector3) -> void:
	_held_object = object
	_held_object_free_mass = object.mass
	object.mass = CarryKnobs.CARRY_OBJECT_HELD_MASS

	var object_inverse := object.global_transform.affine_inverse()
	var half_span := global_transform.basis.x * CarryKnobs.GRIP_HAND_SEPARATION * 0.5
	_hand_object_anchors = [
		object_inverse * (grab_point - half_span),
		object_inverse * (grab_point + half_span),
	]

	_grip_start_pose = global_transform.affine_inverse() * object.global_transform
	_grip_carry_pose = Transform3D(
		_snap_basis_to_axes(_grip_start_pose.basis), CarryKnobs.GRIP_CARRY_OFFSET
	)
	_grip_settle = 0.0
	_grip_strain = 0.0


## Clips the line to the point the ray hit, in the module's own frame, and to
## the harness at the other end, where it hangs slack until you pull away.
func _clip_tether_to(object: RigidBody3D, clip_point: Vector3) -> void:
	_tethered_object = object
	_tether_object_anchor = object.global_transform.affine_inverse() * clip_point
	_tether_suit_anchor = CarryKnobs.TETHER_ANCHOR_OFFSET
	_tether_rope.reset(clip_point, global_transform * _tether_suit_anchor)
	_tether_distance = 0.0
	_tether_strain = 0.0
	_tether_drape = 0.0


## Runs whichever links are live. They are independent and both push the same
## two bodies, so hauling the module on a leash is simply both of them at once.
func _apply_carry_force(delta: float) -> void:
	_apply_grip_force(delta)
	_apply_tether_force(delta)


## Two springs with no slack, one per hand, each pulling its hold back onto the
## point of the suit it belongs to. Together they fight sideways drift as hard
## as they fight the module trailing behind, and any twist between the two
## holds comes out as a couple that squares the module back up.
func _apply_grip_force(delta: float) -> void:
	if _held_object == null:
		return

	_grip_settle = minf(
		_grip_settle + delta / maxf(CarryKnobs.GRIP_SETTLE_TIME, 0.0001), 1.0
	)
	var target_pose := global_transform * _blend_toward_carry_pose()

	# Two springs in parallel between the same pair of bodies are twice the
	# spring one of them is, so each hand gets its share of the pair's reduced
	# mass. That keeps GRIP_SPRING_FREQUENCY the frequency of the grip as a
	# whole rather than of one hand, and holds it there if the hand count ever
	# changes.
	var hand_count := _hand_object_anchors.size()
	var reduced_mass := _measure_reduced_mass(_held_object) / float(hand_count)
	var angular_frequency := TAU * CarryKnobs.GRIP_SPRING_FREQUENCY
	var stiffness := reduced_mass * angular_frequency * angular_frequency
	var damping := 2.0 * CarryKnobs.GRIP_SPRING_DAMPING_RATIO * angular_frequency * reduced_mass
	var force_ceiling := CarryKnobs.GRIP_MAX_FORCE / float(hand_count)

	# Both hands are measured before either is pushed, because the grip slips as
	# a unit: one hand torn off its hold means the module is gone, and letting
	# the other spend a frame hauling on its own would fling it as it went.
	var hand_points := PackedVector3Array()
	var suit_points := PackedVector3Array()
	_grip_strain = 0.0
	for anchor: Vector3 in _hand_object_anchors:
		var hand_point := _held_object.global_transform * anchor
		var suit_point := target_pose * anchor
		hand_points.append(hand_point)
		suit_points.append(suit_point)
		_grip_strain = maxf(_grip_strain, hand_point.distance_to(suit_point))

	if _grip_strain > CarryKnobs.GRIP_BREAK_DISTANCE:
		# Pulled further than the grip can hold. Giving out is what keeps it from
		# reading as a rubber band on a hard yank.
		release_grip()
		return

	for index: int in range(hand_points.size()):
		var hand_point := hand_points[index]
		var suit_point := suit_points[index]
		var object_lever_arm := hand_point - _held_object.global_position
		# Both ends of a hand are points on a spinning body rather than centres
		# of mass, so both spins feed how fast the gap is opening. Damping
		# against the suit's own tumble as well as its drift is most of what
		# stops the module wallowing when you turn.
		var hand_velocity := (
			_held_object.linear_velocity + _held_object.angular_velocity.cross(object_lever_arm)
		)
		var suit_point_velocity := (
			velocity + _read_world_spin().cross(suit_point - global_position)
		)
		var relative_velocity := hand_velocity - suit_point_velocity
		var grip_force := (
			(suit_point - hand_point) * stiffness - relative_velocity * damping
		).limit_length(force_ceiling)
		_push_link_force(
			delta,
			_held_object,
			grip_force,
			object_lever_arm,
			-grip_force,
			suit_point,
			CarryKnobs.GRIP_SPIN_TRANSFER
		)

	_apply_grip_twist(delta, target_pose.basis)


## Holds the one turn a pair of hands cannot: a roll about the line running
## through them. The hands are two points, and a rigid body is free to spin
## about the axis joining any two of its points no matter how hard they are
## held, so without this the module rolls between your palms while staying
## perfectly held on every other axis.
##
## Read it as wrist stiffness. It is deliberately the weakest part of the grip.
func _apply_grip_twist(delta: float, target_basis: Basis) -> void:
	if is_zero_approx(CarryKnobs.GRIP_TWIST_FREQUENCY) or _hand_object_anchors.size() < 2:
		return

	var object_pose := _held_object.global_transform
	var hand_span := (
		object_pose * _hand_object_anchors[1] - object_pose * _hand_object_anchors[0]
	)
	if hand_span.is_zero_approx():
		return
	var twist_axis := hand_span.normalized()

	# Only the part of the orientation error that runs along the hand axis is
	# this spring's business. Everything else is already the two hands' job, and
	# answering it here as well would double the stiffness they were tuned at.
	var orientation_error := _measure_rotation(
		target_basis * object_pose.basis.orthonormalized().inverse()
	)
	var twist_error := orientation_error.dot(twist_axis)
	var twist_rate := (_held_object.angular_velocity - _read_world_spin()).dot(twist_axis)

	var moment_of_inertia := _measure_inertia_about(twist_axis)
	var angular_frequency := TAU * CarryKnobs.GRIP_TWIST_FREQUENCY
	var stiffness := moment_of_inertia * angular_frequency * angular_frequency
	var damping := (
		2.0 * CarryKnobs.GRIP_TWIST_DAMPING_RATIO * angular_frequency * moment_of_inertia
	)
	var torque := clampf(
		twist_error * stiffness - twist_rate * damping,
		-CarryKnobs.GRIP_TWIST_MAX_TORQUE,
		CarryKnobs.GRIP_TWIST_MAX_TORQUE
	)

	var angular_impulse := twist_axis * torque * delta
	_held_object.apply_torque_impulse(angular_impulse)
	_add_spin_from_angular_impulse(-angular_impulse, CarryKnobs.GRIP_TWIST_SPIN_TRANSFER)


## The suit-local pose the hands are pulling the module toward this frame,
## eased from where it was caught to where it is carried.
func _blend_toward_carry_pose() -> Transform3D:
	var eased := smoothstep(0.0, 1.0, _grip_settle)
	var blended_rotation := _grip_start_pose.basis.get_rotation_quaternion().slerp(
		_grip_carry_pose.basis.get_rotation_quaternion(), eased
	)
	return Transform3D(
		Basis(blended_rotation), _grip_start_pose.origin.lerp(_grip_carry_pose.origin, eased)
	)


## A rope: nothing at all below its length, and past that a pull along its own
## line and no other. The module is free to drift sideways, swing, and fall
## behind, and only ever gets hauled back along the line - which is the whole
## reason it stays out of your view.
##
## Which end the haul actually moves is not decided here. It falls out of the
## mass ratio at _push_link_force, and a module nobody is holding weighs several
## times what the suit does, so going taut reels you back toward the module. To
## get past the end of the line you have to unclip.
##
## The line is measured along the rope's whole shape, not end to end, so a rope
## that has gone the long way round something has already spent that length.
func _apply_tether_force(delta: float) -> void:
	if _tethered_object == null:
		return

	var suit_point := global_transform * _tether_suit_anchor
	var object_point := _tethered_object.global_transform * _tether_object_anchor
	var object_lever_arm := object_point - _tethered_object.global_position
	# The line is clipped to a point on the module's surface, so the module's
	# spin contributes to how fast that point is moving.
	var object_point_velocity := (
		_tethered_object.linear_velocity
		+ _tethered_object.angular_velocity.cross(object_lever_arm)
	)

	# Both ends have to sit outside the hull before the rope is asked to hang
	# off them. The harness point rides behind you, further out than the suit's
	# own collider reaches, so hugging a pillar to get the rope round it puts
	# the anchor inside the pillar - and the rope, which has no choice but to
	# start where it is tied, goes in after it. The module's clip point does the
	# same when it is dragged up against something.
	var space_state := get_world_3d().direct_space_state
	suit_point = _hold_anchor_clear(space_state, global_position, suit_point)
	object_point = _hold_anchor_clear(
		space_state, _tethered_object.global_position, object_point
	)

	_tether_rope.step(delta, space_state, object_point, suit_point)
	_tether_distance = _tether_rope.measure_length()
	_tether_drape = _tether_distance - _tether_rope.measure_span()
	_tether_strain = maxf(_tether_distance - CarryKnobs.TETHER_LENGTH, 0.0)
	if _tether_strain > CarryKnobs.TETHER_BREAK_STRETCH:
		unclip_tether()
		return
	if is_zero_approx(_tether_strain):
		return

	# Each end is hauled along its own first length of rope rather than toward
	# the far end. With the rope draped over something those are different
	# directions, and it is the drape the pull is really against: take a tether
	# round a pillar and it drags you toward the pillar, not toward the load.
	var suit_run := suit_point - _tether_rope.read_point_beside_suit()
	var object_run := object_point - _tether_rope.read_point_beside_object()
	if suit_run.is_zero_approx() or object_run.is_zero_approx():
		return
	var suit_direction := suit_run.normalized()
	var object_direction := object_run.normalized()

	# How fast the rope is being pulled out. Each end contributes only the part
	# of its motion that runs along the rope it is paying out; the rest is
	# slack the tether has no opinion about.
	var stretch_rate := velocity.dot(suit_direction) + object_point_velocity.dot(object_direction)

	var angular_frequency := TAU * CarryKnobs.TETHER_SPRING_FREQUENCY
	var reduced_mass := _measure_reduced_mass(_tethered_object)
	var stiffness := reduced_mass * angular_frequency * angular_frequency
	var damping := 2.0 * CarryKnobs.TETHER_SPRING_DAMPING_RATIO * angular_frequency * reduced_mass

	# A rope pulls and never pushes, so damping can soften the haul but must
	# not be allowed to invert it into a shove.
	var tension := maxf(_tether_strain * stiffness + stretch_rate * damping, 0.0)
	tension = minf(tension, CarryKnobs.TETHER_MAX_FORCE)

	_push_link_force(
		delta,
		_tethered_object,
		-object_direction * tension,
		object_lever_arm,
		-suit_direction * tension,
		suit_point,
		CarryKnobs.TETHER_SPIN_TRANSFER
	)


## Brings an anchor back to the near side of any hull between it and the centre
## of the body it belongs to. Both centres are kept out of the hull by their own
## colliders, so a cast from one is always a cast from somewhere real.
##
## This is what lets the rope trust its two ends. Everything the rope does to
## keep itself out of geometry works outward from the anchors, so an anchor
## buried in a wall is the one case it cannot reason its way out of.
func _hold_anchor_clear(
	space_state: PhysicsDirectSpaceState3D, body_center: Vector3, anchor: Vector3
) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		body_center, anchor, CarryKnobs.TETHER_ROPE_LAYERS
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return anchor

	var contact_point: Vector3 = hit["position"]
	var contact_normal: Vector3 = hit["normal"]
	return contact_point + contact_normal * CarryKnobs.TETHER_ROPE_RADIUS


## Hands one frame of link force to both ends. A straight link gets the same
## force with opposite signs; a rope bent around the hull does not, because
## whatever it is bent around absorbs the difference.
##
## Both ends are pushed off centre, which is why a module swinging out to one
## side slews your heading as the hands haul it back, and why the same pull that
## tows the module also tumbles it.
func _push_link_force(
	delta: float,
	object: RigidBody3D,
	object_force: Vector3,
	object_lever_arm: Vector3,
	suit_force: Vector3,
	suit_point: Vector3,
	spin_transfer: float
) -> void:
	object.apply_impulse(object_force * delta, object_lever_arm)

	var suit_velocity_change := suit_force * delta / CarryKnobs.PLAYER_MASS
	velocity = (velocity + suit_velocity_change).limit_length(CarryKnobs.MAX_SPEED)
	if not is_zero_approx(spin_transfer):
		_add_spin_from_impulse(suit_velocity_change, suit_point, spin_transfer)


## The effective mass of the two-body pair. Deriving stiffness from this keeps a
## spring's frequency meaningful on its own whatever the module weighs. What
## does change with mass is who moves: the same force divided by 600 kg barely
## shifts the module, divided by 90 kg it throws the player around.
func _measure_reduced_mass(object: RigidBody3D) -> float:
	return 1.0 / (1.0 / CarryKnobs.PLAYER_MASS + 1.0 / object.mass)


## The held module's moment of inertia about a world-space axis, in kg m^2.
##
## Taken from the physics server rather than assumed, so the wrist spring's
## frequency stays honest for a module of any shape and does not have to be
## retuned every time its mass is changed.
func _measure_inertia_about(world_axis: Vector3) -> float:
	var body_state := PhysicsServer3D.body_get_direct_state(_held_object.get_rid())
	# Falls back on treating the module as its mass a metre out. Only reachable
	# if the body has left the physics world mid-frame.
	if body_state == null:
		return _held_object.mass
	var inverse_inertia := world_axis.dot(body_state.inverse_inertia_tensor * world_axis)
	if inverse_inertia <= 0.0:
		return _held_object.mass
	return 1.0 / inverse_inertia


## The suit's tumble in world space. angular_velocity is kept in body-local
## axes, which is the wrong frame for anything comparing it against a rigid
## body's own spin.
func _read_world_spin() -> Vector3:
	return global_transform.basis * angular_velocity


## A rotation expressed as the axis it turns about scaled by how far it turns,
## in radians. This is what makes an orientation error something a spring can
## work on: it is a vector, so it can be projected onto one axis and the rest
## left to whatever else is holding the module.
static func _measure_rotation(rotation_basis: Basis) -> Vector3:
	var rotation := Quaternion(rotation_basis.orthonormalized())
	# Every rotation has a second representation turning the long way round the
	# other direction, and it is the one that reads as most of a turn of error
	# where there is almost none. Negating picks the short way.
	if rotation.w < 0.0:
		rotation = -rotation
	var angle := rotation.get_angle()
	if is_zero_approx(angle):
		return Vector3.ZERO
	return rotation.get_axis() * angle


## The axis-aligned orientation nearest the one given.
##
## Squaring a roughly cubic module up to a nominal upright would mean rotating
## it up to half a turn to reach a face indistinguishable from the one already
## facing you. This takes the short way instead: pick the cardinal each of the
## module's own axes is closest to already.
static func _snap_basis_to_axes(source: Basis) -> Basis:
	var snapped_z := _find_nearest_cardinal(source.z, Vector3.ZERO)
	var snapped_y := _find_nearest_cardinal(source.y, snapped_z)
	return Basis(snapped_y.cross(snapped_z), snapped_y, snapped_z)


## The signed cardinal axis a direction points most nearly along, skipping the
## one line already spoken for so the result can be part of a valid basis.
static func _find_nearest_cardinal(direction: Vector3, claimed_axis: Vector3) -> Vector3:
	var cardinals := [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	var nearest := Vector3.RIGHT
	var best_alignment := -INF
	for candidate: Vector3 in cardinals:
		if not is_zero_approx(candidate.dot(claimed_axis)):
			continue
		var alignment := candidate.dot(direction)
		if alignment > best_alignment:
			best_alignment = alignment
			nearest = candidate
	return nearest


## Draws the rope through the points it is actually simulated at. Worth having
## even though nothing about it is physical: the module you are moored to spends
## most of its time behind you and out of the lamp, and this is the only thing
## telling you where it is, what it is caught on, and whether it has gone taut.
##
## Slack needs no drawing trick now. The rope trails where its own momentum
## left it, which in vacuum is the honest answer to what a slack line does.
func _update_tether_line() -> void:
	var rope_points := _tether_rope.read_points()
	_tether_line.visible = _tethered_object != null and rope_points.size() >= 2
	if not _tether_line.visible:
		return

	_build_rope_tube(rope_points)

	var surface_arrays := []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = _tether_tube_vertices
	surface_arrays[Mesh.ARRAY_NORMAL] = _tether_tube_normals
	surface_arrays[Mesh.ARRAY_INDEX] = _tether_tube_indices
	_tether_mesh.clear_surfaces()
	_tether_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)


## Lays a ring of vertices across the rope at each of its points, which is what
## gives the drawn rope a thickness the simulated chain of points does not have.
##
## Each ring needs a pair of axes across the rope, and nothing picks which way
## round they go - a tube is the same shape whichever you choose. What matters
## is that neighbouring rings agree, or the tube creases along its length, so
## each ring leans the previous ring's axes onto its own cross-section rather
## than choosing afresh.
##
## Both end rings are drawn in to nothing. That closes the tube off where it
## meets its anchors without any geometry beyond what is already here, and the
## taper is hidden in the module and the harness it runs into.
func _build_rope_tube(rope_points: PackedVector3Array) -> void:
	var point_count := rope_points.size()
	var sides := maxi(3, CarryKnobs.TETHER_ROPE_DRAW_SIDES)
	_resize_rope_tube(point_count, sides)

	var across := Vector3.ZERO
	for point_index: int in range(point_count):
		var along := _measure_rope_direction(rope_points, point_index)
		across -= along * across.dot(along)
		# Only reachable on the first ring, which has nothing to lean, and on a
		# rope that has doubled back hard enough to leave nothing to lean on.
		if across.length_squared() < 0.0001:
			across = _find_any_perpendicular(along)
		across = across.normalized()
		var other_across := along.cross(across)

		var radius := CarryKnobs.TETHER_ROPE_DRAW_RADIUS
		if point_index == 0 or point_index == point_count - 1:
			radius = 0.0

		var ring_center := rope_points[point_index]
		var ring_start := point_index * sides
		for side_index: int in range(sides):
			var angle := TAU * float(side_index) / float(sides)
			var outward := across * cos(angle) + other_across * sin(angle)
			_tether_tube_vertices[ring_start + side_index] = ring_center + outward * radius
			_tether_tube_normals[ring_start + side_index] = outward


## Sizes the tube's arrays to the rope and works out its faces. Both only ever
## change when the rope's point count does, which is when a line is clipped on.
func _resize_rope_tube(point_count: int, sides: int) -> void:
	var vertex_count := point_count * sides
	if _tether_tube_vertices.size() == vertex_count:
		return
	_tether_tube_vertices.resize(vertex_count)
	_tether_tube_normals.resize(vertex_count)
	_tether_tube_indices.resize((point_count - 1) * sides * 6)

	# Each pair of neighbouring rings is joined by a quad per side, wound the way
	# round that leaves it facing out of the rope.
	var index := 0
	for ring_index: int in range(point_count - 1):
		for side_index: int in range(sides):
			var next_side := (side_index + 1) % sides
			var near_first := ring_index * sides + side_index
			var near_second := ring_index * sides + next_side
			var far_first := near_first + sides
			var far_second := near_second + sides
			_tether_tube_indices[index] = near_first
			_tether_tube_indices[index + 1] = far_first
			_tether_tube_indices[index + 2] = far_second
			_tether_tube_indices[index + 3] = near_first
			_tether_tube_indices[index + 4] = far_second
			_tether_tube_indices[index + 5] = near_second
			index += 6


## Which way the rope runs at one of its points, averaged from the runs either
## side of it so the tube bends through a link rather than kinking at it.
##
## Averaged rather than simply taken across the point, because the two
## neighbours of a point where the rope has folded back on itself are in nearly
## the same place, and the line between them is noise. A ring built on a tangent
## that has come out pointing back down the rope is wound the opposite way to
## its neighbours, and the tube turns inside out between them.
##
## Where the average cancels the rope really has doubled right back, and the run
## out of the point is the honest answer. A tube through a fold that sharp
## pinches through itself whatever tangent it is given.
static func _measure_rope_direction(rope_points: PackedVector3Array, point_index: int) -> Vector3:
	var ahead := Vector3.ZERO
	if point_index < rope_points.size() - 1:
		ahead = (rope_points[point_index + 1] - rope_points[point_index]).normalized()
	var behind := Vector3.ZERO
	if point_index > 0:
		behind = (rope_points[point_index] - rope_points[point_index - 1]).normalized()

	var along := ahead + behind
	if along.length_squared() < 0.0001:
		along = behind if ahead.is_zero_approx() else ahead
	if along.is_zero_approx():
		return Vector3.BACK
	return along.normalized()


## Any unit vector across the direction given. Which one is immaterial: it only
## ever seeds the first ring, and a tube has no preferred way round.
static func _find_any_perpendicular(direction: Vector3) -> Vector3:
	var off_axis := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	return direction.cross(off_axis).normalized()


# --- Movement --------------------------------------------------------------


func _update_orientation(delta: float) -> void:
	var mouse_motion := _accumulated_mouse_motion
	_accumulated_mouse_motion = Vector2.ZERO
	var roll_input := Input.get_axis("roll_left", "roll_right")

	var is_inertial := CarryKnobs.ROTATION_MODE == CarryKnobs.RotationMode.INERTIAL
	if is_inertial:
		var aim_gain := CarryKnobs.MOUSE_SENSITIVITY * CarryKnobs.ANGULAR_ACCELERATION
		angular_velocity.x += -mouse_motion.y * aim_gain
		angular_velocity.y += -mouse_motion.x * aim_gain
		angular_velocity.z += -roll_input * CarryKnobs.ROLL_RATE * delta
		angular_velocity = angular_velocity.limit_length(CarryKnobs.MAX_ANGULAR_SPEED)

	_damp_angular_velocity(delta)

	# Both modes carry angular_velocity, because impacts and the grip write to
	# it. DIRECT additionally steers straight from the mouse on top of whatever
	# spin those have left you with; INERTIAL has already folded aim into it.
	var aim_pitch := 0.0
	var aim_yaw := 0.0
	var aim_roll := 0.0
	if not is_inertial:
		aim_pitch = -mouse_motion.y * CarryKnobs.MOUSE_SENSITIVITY
		aim_yaw = -mouse_motion.x * CarryKnobs.MOUSE_SENSITIVITY
		aim_roll = -roll_input * CarryKnobs.ROLL_RATE * delta

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
		Vector3.ZERO, minf(CarryKnobs.ANGULAR_DRAG * delta, 1.0)
	)
	if stabilizers_engaged:
		angular_velocity = angular_velocity.lerp(
			Vector3.ZERO, minf(CarryKnobs.ANGULAR_STABILIZER_RATE * delta, 1.0)
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
	_apply_thrust(delta, thrust_input)

	if stabilizers_engaged:
		velocity = velocity.lerp(
			Vector3.ZERO, minf(CarryKnobs.LINEAR_STABILIZER_RATE * delta, 1.0)
		)

	velocity = velocity.limit_length(CarryKnobs.MAX_SPEED)


## Spends one frame of thruster force, braced against the module when it is in
## your hands.
##
## Thrusting with a load is one force and two bodies. Put all of it into the
## suit and the module hears about it only through your hands, which are out in
## front of your centre of mass: the pull that gets the module moving arrives on
## a lever arm and turns you, worst on the axes furthest from the line through
## your hands. That is realistic and it is miserable to fly - a burst straight
## up or down pitches you over every time.
##
## Bracing hands the module its own share of the force directly, at its centre,
## so both bodies set off together and the hands are left holding only what the
## module does on its own. That still turns you, and it is the part worth
## feeling.
##
## Thrust costs the same either way. The force has both masses to shift whether
## it reaches the module through your hands or on its own, so a braced burst
## accelerates you at exactly what an unbraced one settles at.
func _apply_thrust(delta: float, thrust_input: Vector3) -> void:
	var thrust_force := (
		global_transform.basis
		* thrust_input
		* CarryKnobs.THRUST_ACCELERATION
		* CarryKnobs.PLAYER_MASS
	)

	# At full brace this is the share that leaves both bodies at the same
	# acceleration, so the grip is left holding nothing. The rest is yours.
	var object_share := 0.0
	if _held_object != null:
		object_share = (
			CarryKnobs.GRIP_BRACED_THRUST
			* _held_object.mass
			/ (CarryKnobs.PLAYER_MASS + _held_object.mass)
		)
	if not is_zero_approx(object_share):
		_held_object.apply_central_impulse(thrust_force * object_share * delta)

	velocity += thrust_force * (1.0 - object_share) * delta / CarryKnobs.PLAYER_MASS


# --- Collision -------------------------------------------------------------


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

	# Immovable hull and loose bodies need completely different answers, so
	# split the frame's contacts before resolving either.
	var hull_normal := Vector3.ZERO
	var hull_point := Vector3.ZERO
	var hull_contact_count := 0
	var loose_contacts: Array[KinematicCollision3D] = []

	for index in contact_count:
		var contact := get_slide_collision(index)
		var collider := contact.get_collider()
		if collider is RigidBody3D:
			# The held object is already governed by the grip spring. Running
			# the momentum exchange on it as well would double-count the same
			# contact and fight the spring, so it is left to move_and_slide,
			# which still stops the suit from passing through it.
			if collider != _held_object:
				loose_contacts.append(contact)
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

	for contact in loose_contacts:
		_shove_loose_body(contact, approach_velocity, was_already_touching)


func _resolve_hull_contact(
	delta: float,
	approach_velocity: Vector3,
	summed_normal: Vector3,
	contact_point: Vector3,
	was_already_touching: bool
) -> void:
	if was_already_touching:
		velocity = velocity.lerp(Vector3.ZERO, minf(CarryKnobs.SCRAPE_FRICTION * delta, 1.0))
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
		along_surface * (1.0 - CarryKnobs.COLLISION_FRICTION)
		- into_surface * CarryKnobs.COLLISION_RESTITUTION
	)

	_apply_impact_spin(along_surface, contact_point)


## Resolves a hit against a loose body as a two-body momentum exchange, so the
## same collision both redirects the player and sends the object tumbling. The
## mass ratio does all the work: something far lighter than PLAYER_MASS gets
## swatted aside barely slowing you, something far heavier shoves you off
## course while still giving way.
##
## move_and_slide treats a RigidBody3D as an obstacle and has already stripped
## the closing speed out of velocity, so the pre-move approach velocity is what
## the exchange has to be computed from.
func _shove_loose_body(
	contact: KinematicCollision3D, approach_velocity: Vector3, was_already_touching: bool
) -> void:
	var body := contact.get_collider() as RigidBody3D
	if body == null or body.mass <= 0.0:
		return

	var contact_normal := contact.get_normal()
	var contact_point := contact.get_position()
	var relative_velocity := approach_velocity - body.linear_velocity
	var closing_speed := relative_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		return

	# Bounce only on the frame contact begins; sustained contact becomes a
	# steady push, which is what lets you shoulder something out of the way
	# instead of pinballing off it.
	var restitution := 0.0 if was_already_touching else CarryKnobs.COLLISION_RESTITUTION
	var reduced_mass := 1.0 / (1.0 / CarryKnobs.PLAYER_MASS + 1.0 / body.mass)
	var impulse_magnitude := -(1.0 + restitution) * closing_speed * reduced_mass

	velocity += contact_normal * (impulse_magnitude / CarryKnobs.PLAYER_MASS)
	body.apply_impulse(-contact_normal * impulse_magnitude, contact_point - body.global_position)

	var mass_ratio := body.mass / (body.mass + CarryKnobs.PLAYER_MASS)
	var along_surface := relative_velocity - contact_normal * closing_speed
	_apply_impact_spin(along_surface * mass_ratio, contact_point)


## Friction acts where the body actually touched, not at its centre, so it
## applies a torque proportional to that offset. A square-on hit has no lever
## and produces no spin; a graze has a long one and tumbles you.
func _apply_impact_spin(along_surface: Vector3, contact_point: Vector3) -> void:
	if is_zero_approx(CarryKnobs.COLLISION_SPIN_TRANSFER):
		return
	_add_spin_from_impulse(
		-along_surface * CarryKnobs.COLLISION_FRICTION,
		contact_point,
		CarryKnobs.COLLISION_SPIN_TRANSFER
	)


## Turns a velocity change applied somewhere other than the centre of mass into
## body spin.
func _add_spin_from_impulse(
	velocity_change: Vector3, application_point: Vector3, transfer: float
) -> void:
	var lever_arm := application_point - global_position
	_add_spin_from_angular_impulse(
		lever_arm.cross(velocity_change * CarryKnobs.PLAYER_MASS), transfer
	)


## Adds a world-space angular impulse to the suit's own tumble. The transfer
## factor, divided through by a mass standing in for a moment of inertia the
## suit does not model, is a feel dial rather than a physical quantity.
func _add_spin_from_angular_impulse(world_angular_impulse: Vector3, transfer: float) -> void:
	# angular_velocity is held in body-local axes, so the impulse has to come
	# back out of world space before it can be added.
	angular_velocity += (
		global_transform.basis.inverse()
		* world_angular_impulse
		* transfer
		/ CarryKnobs.PLAYER_MASS
	)
	angular_velocity = angular_velocity.limit_length(CarryKnobs.MAX_ANGULAR_SPEED)
