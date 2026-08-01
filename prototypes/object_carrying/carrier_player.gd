class_name CarrierPlayer
extends CharacterBody3D

## Six-degrees-of-freedom suit-thruster controller that can take hold of a
## heavy object and haul it around.
##
## The suit itself behaves exactly as it does in the navigation prototype:
## thrust along the body's own axes, momentum that persists, no world "up".
## What is new is the carry link. Aim at a carryable, press grab, and a spring
## is strung between a point on your suit and the point you grabbed. That
## spring pulls on both ends every frame, so hauling something is a genuine
## two-body problem - you tow it, it tows you, and the mass ratio decides who
## wins.
##
## There are two ways to be attached, switchable live so they can be compared
## back to back. GRIP anchors at the hands with no slack, so the load answers
## instantly and rides in the middle of your view. TETHER anchors behind you
## on a rope that does nothing until it pulls taut, so the load trails out of
## sight and only ever pulls along the line. That rope also catches on the hull
## and bends around it, and each end is hauled along its own last span, so a
## tether taken around a pillar hauls you toward the pillar. Both modes end at
## _push_link_force, which is where the two bodies actually get moved.
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

## The object currently on the end of the link, or null.
var _held_object: RigidBody3D
## A carryable the grab ray is on right now, held or not. Read by the HUD so
## the crosshair can say "this is grabbable" before you commit.
var _targeted_object: RigidBody3D
## Where the link meets the object, in the object's local space. Fixed at the
## moment of grabbing, so the object keeps being held by the corner you
## actually reached for.
var _object_local_anchor := Vector3.ZERO
## Where the link meets the suit, in the suit's local space. In GRIP this is
## the point the ray hit, recorded as it stood, which is what makes attaching
## jolt-free - the spring opens with no tension and only builds it once you
## move. In TETHER it is the fixed harness point behind you instead.
var _suit_local_anchor := Vector3.ZERO
## Which of the two ways of being attached is active. Switchable at runtime.
var _carry_mode := CarryKnobs.CarryMode.GRIP
## Where the rope is bent around hull geometry, in world space, ordered from
## the object end to the suit end. Empty whenever the line runs straight, which
## is the only case GRIP ever has.
var _tether_wraps: Array[Vector3] = []
## Length of the link right now, in metres: straight between the anchors in
## GRIP, measured along the whole bent path in TETHER. Read by the HUD.
var _link_distance := 0.0
## How far the link is stretched past what it holds for free, in metres: the
## whole distance in GRIP, only the part past TETHER_LENGTH in TETHER. It is
## what is measured against get_link_break_distance().
var _link_strain := 0.0

@onready var _head_camera: Camera3D = $HeadCamera
@onready var _helmet_lamp: SpotLight3D = $HeadCamera/HelmetLamp
@onready var _grab_ray: RayCast3D = $HeadCamera/GrabRay
@onready var _tether_line: MeshInstance3D = $TetherLine

var _tether_mesh := ImmediateMesh.new()


func _ready() -> void:
	# Whoever built this scene is responsible for putting the player at
	# CarryKnobs.PLAYER_SPAWN before it enters the tree; the pose it arrives
	# with is the one R returns to.
	_spawn_transform = global_transform
	_carry_mode = CarryKnobs.CARRY_MODE
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
	# the same reason - the ray has to be current before the link is decided.
	_update_grab_target()
	if Input.is_action_just_pressed("toggle_carry_mode"):
		_toggle_carry_mode()
	if Input.is_action_just_pressed("grab"):
		_toggle_hold()

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


## The object on the end of the link, or null if empty-handed.
func get_held_object() -> RigidBody3D:
	return _held_object


## The carryable under the crosshair and within reach, or null.
func get_targeted_object() -> RigidBody3D:
	return _targeted_object


## Which of the two ways of being attached is active right now.
func get_carry_mode() -> CarryKnobs.CarryMode:
	return _carry_mode


## Length of the link, in metres, measured the way the active mode measures it.
## Zero when nothing is held.
func get_link_distance() -> float:
	return _link_distance


## How many places the rope is currently bent around the hull. Always zero in
## GRIP, and zero on a tether with a clear run to the load.
func get_tether_wrap_count() -> int:
	return _tether_wraps.size()


## How far the link is stretched past what it holds for free, in metres. Zero
## when nothing is held, and zero on a slack tether. It reaches
## get_link_break_distance() at the instant the link parts.
func get_link_strain() -> float:
	return _link_strain


## The strain the active mode gives out at, in metres.
func get_link_break_distance() -> float:
	if _carry_mode == CarryKnobs.CarryMode.TETHER:
		return CarryKnobs.TETHER_BREAK_STRETCH
	return CarryKnobs.CARRY_BREAK_DISTANCE


## Returns the player to their starting pose, fully at rest and empty-handed.
func respawn() -> void:
	release_object()
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_accumulated_mouse_motion = Vector2.ZERO
	_was_touching_surface = false
	global_transform = _spawn_transform


## Lets go. The object keeps whatever momentum it had - nothing is zeroed, so
## releasing mid-haul leaves it coasting away on its own.
func release_object() -> void:
	_held_object = null
	_tether_wraps.clear()
	_link_distance = 0.0
	_link_strain = 0.0


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


func _toggle_hold() -> void:
	if _held_object != null:
		release_object()
	elif _targeted_object != null:
		_attach_to(_targeted_object, _grab_ray.get_collision_point())


## Switching drops whatever is held. The two modes anchor to different points
## on the suit, so carrying across a switch would jump the load from your
## hands to your back or the reverse, under whatever tension it was already
## under.
func _toggle_carry_mode() -> void:
	release_object()
	if _carry_mode == CarryKnobs.CarryMode.GRIP:
		_carry_mode = CarryKnobs.CarryMode.TETHER
	else:
		_carry_mode = CarryKnobs.CarryMode.GRIP


## Anchors the object end at the point the ray hit, in the object's own frame,
## so it keeps being held by the corner you actually reached for.
##
## The suit end depends on the mode. GRIP records the same world point in the
## suit's frame, so both ends start coincident and the spring opens with no
## tension - taking hold reads as latching on rather than the object snapping
## to a carry pose. TETHER ignores the hit point and clips the line to the
## harness, where it will hang slack until you pull away.
func _attach_to(object: RigidBody3D, grab_point: Vector3) -> void:
	_held_object = object
	_tether_wraps.clear()
	_object_local_anchor = object.global_transform.affine_inverse() * grab_point
	if _carry_mode == CarryKnobs.CarryMode.TETHER:
		_suit_local_anchor = CarryKnobs.TETHER_ANCHOR_OFFSET
	else:
		_suit_local_anchor = global_transform.affine_inverse() * grab_point
	_link_distance = 0.0
	_link_strain = 0.0


## Measures the link and hands the active mode the two points it runs between.
func _apply_carry_force(delta: float) -> void:
	if _held_object == null:
		return

	var suit_point := global_transform * _suit_local_anchor
	var object_point := _held_object.global_transform * _object_local_anchor
	var object_lever_arm := object_point - _held_object.global_position
	# The link is anchored to a point on the object's surface, so the object's
	# spin contributes to how fast that point is moving.
	var object_point_velocity := (
		_held_object.linear_velocity + _held_object.angular_velocity.cross(object_lever_arm)
	)

	if _carry_mode == CarryKnobs.CarryMode.TETHER:
		_apply_tether_force(
			delta, suit_point, object_point, object_lever_arm, object_point_velocity
		)
	else:
		_apply_grip_force(delta, suit_point, object_point, object_lever_arm, object_point_velocity)


## A spring with no slack, pulling the two anchors back together in every
## direction at once. That is what makes GRIP feel like a hand: it fights
## sideways drift as hard as it fights the object trailing behind.
func _apply_grip_force(
	delta: float,
	suit_point: Vector3,
	object_point: Vector3,
	object_lever_arm: Vector3,
	object_point_velocity: Vector3
) -> void:
	var separation := suit_point - object_point
	_link_distance = separation.length()
	_link_strain = _link_distance
	if _link_strain > CarryKnobs.CARRY_BREAK_DISTANCE:
		# Stretched past what the grip can hold. Giving out is what keeps it
		# from reading as a rubber band on a hard yank.
		release_object()
		return

	var relative_velocity := object_point_velocity - velocity
	var angular_frequency := TAU * CarryKnobs.CARRY_SPRING_FREQUENCY
	var reduced_mass := _measure_reduced_mass()
	var stiffness := reduced_mass * angular_frequency * angular_frequency
	var damping := 2.0 * CarryKnobs.CARRY_SPRING_DAMPING_RATIO * angular_frequency * reduced_mass
	var grip_force := (separation * stiffness - relative_velocity * damping).limit_length(
		CarryKnobs.CARRY_MAX_FORCE
	)
	_push_link_force(
		delta, grip_force, object_lever_arm, -grip_force, suit_point, CarryKnobs.CARRY_SPIN_TRANSFER
	)


## A rope: nothing at all below its length, and past that a pull along its own
## line and no other. The object is free to drift sideways, swing, and fall
## behind, and only ever gets hauled back along the line - which is the whole
## reason it stays out of your view.
##
## The line is measured along its whole bent path, not end to end, so anything
## it has wrapped around has already spent some of its length.
func _apply_tether_force(
	delta: float,
	suit_point: Vector3,
	object_point: Vector3,
	object_lever_arm: Vector3,
	object_point_velocity: Vector3
) -> void:
	_update_tether_path(object_point, suit_point)
	_link_distance = _measure_tether_path_length(object_point, suit_point)
	_link_strain = maxf(_link_distance - CarryKnobs.TETHER_LENGTH, 0.0)
	if _link_strain > CarryKnobs.TETHER_BREAK_STRETCH:
		release_object()
		return
	if is_zero_approx(_link_strain):
		return

	# Each end is hauled along its own last span rather than toward the far
	# end. With the line bent around something those are different directions,
	# and it is the bend the pull is really against: wrap a tether around a
	# pillar and it drags you toward the pillar, not toward the load.
	var suit_run := suit_point - _read_wrap_toward_suit(object_point)
	var object_run := object_point - _read_wrap_toward_object(suit_point)
	if suit_run.is_zero_approx() or object_run.is_zero_approx():
		return
	var suit_direction := suit_run.normalized()
	var object_direction := object_run.normalized()

	# How fast the whole path is lengthening. Each end contributes only the
	# part of its motion that runs along the line it is paying out; the rest is
	# slack the tether has no opinion about.
	var stretch_rate := velocity.dot(suit_direction) + object_point_velocity.dot(object_direction)

	var angular_frequency := TAU * CarryKnobs.TETHER_SPRING_FREQUENCY
	var reduced_mass := _measure_reduced_mass()
	var stiffness := reduced_mass * angular_frequency * angular_frequency
	var damping := 2.0 * CarryKnobs.TETHER_SPRING_DAMPING_RATIO * angular_frequency * reduced_mass

	# A rope pulls and never pushes, so damping can soften the haul but must
	# not be allowed to invert it into a shove.
	var tension := maxf(_link_strain * stiffness + stretch_rate * damping, 0.0)
	tension = minf(tension, CarryKnobs.TETHER_MAX_FORCE)

	_push_link_force(
		delta,
		-object_direction * tension,
		object_lever_arm,
		-suit_direction * tension,
		suit_point,
		CarryKnobs.TETHER_SPIN_TRANSFER
	)


## Hands one frame of link force to both ends. A straight link gets the same
## force with opposite signs; a rope bent around the hull does not, because
## whatever it is bent around absorbs the difference.
##
## Both ends are pushed off centre, which is why thrusting with the load out to
## one side slews your heading instead of just slowing you down, and why the
## same pull that tows the object also tumbles it.
func _push_link_force(
	delta: float,
	object_force: Vector3,
	object_lever_arm: Vector3,
	suit_force: Vector3,
	suit_point: Vector3,
	spin_transfer: float
) -> void:
	_held_object.apply_impulse(object_force * delta, object_lever_arm)

	var suit_velocity_change := suit_force * delta / CarryKnobs.PLAYER_MASS
	velocity = (velocity + suit_velocity_change).limit_length(CarryKnobs.MAX_SPEED)
	if not is_zero_approx(spin_transfer):
		_add_spin_from_impulse(suit_velocity_change, suit_point, spin_transfer)


# --- Rope path -------------------------------------------------------------


## The bend the suit end of the line pulls against, or the object itself when
## the rope runs straight.
func _read_wrap_toward_suit(object_point: Vector3) -> Vector3:
	if _tether_wraps.is_empty():
		return object_point
	return _tether_wraps[-1]


## The bend the object end of the line pulls against, or the suit itself when
## the rope runs straight.
func _read_wrap_toward_object(suit_point: Vector3) -> Vector3:
	if _tether_wraps.is_empty():
		return suit_point
	return _tether_wraps[0]


func _measure_tether_path_length(object_point: Vector3, suit_point: Vector3) -> float:
	var path_length := 0.0
	var span_start := object_point
	for wrap_point: Vector3 in _tether_wraps:
		path_length += span_start.distance_to(wrap_point)
		span_start = wrap_point
	return path_length + span_start.distance_to(suit_point)


## Keeps the list of bends current: bends are dropped as soon as the span they
## stood in for comes clear, then new ones are found wherever the line still
## runs through something. Dropping first matters - a bend that has just been
## rounded would otherwise be used as the anchor for finding the next one.
func _update_tether_path(object_point: Vector3, suit_point: Vector3) -> void:
	_drop_cleared_wraps(object_point, suit_point)
	_grow_wraps_from_end(suit_point, object_point, true)
	_grow_wraps_from_end(object_point, suit_point, false)


## Walks in from both ends removing bends whose span has come clear. A rope
## unwraps in the reverse order it wrapped, so only the outermost bend at each
## end is ever a candidate.
func _drop_cleared_wraps(object_point: Vector3, suit_point: Vector3) -> void:
	while not _tether_wraps.is_empty():
		var inboard_of_suit := object_point
		if _tether_wraps.size() > 1:
			inboard_of_suit = _tether_wraps[-2]
		if _is_span_blocked(inboard_of_suit, suit_point):
			break
		_tether_wraps.remove_at(_tether_wraps.size() - 1)

	while not _tether_wraps.is_empty():
		var inboard_of_object := suit_point
		if _tether_wraps.size() > 1:
			inboard_of_object = _tether_wraps[1]
		if _is_span_blocked(inboard_of_object, object_point):
			break
		_tether_wraps.remove_at(0)


## Runs one end of the line out against the hull until the end span is clear.
## Only the two end spans can newly catch on anything: everything between two
## bends is pinned at both ends and has not moved. `at_suit_end` picks which
## end, since the two are mirror images and differ only in which end of the
## list they grow from.
##
## A span can be blocked in two ways that need different answers. Blocked out
## in open space is the rope running into something new, and a bend goes where
## it touched. Blocked immediately, right where the rope already bends, means
## that bend is sitting on the face beside an edge rather than clear of the
## edge itself - the rope has caught on the corner, and no number of extra
## bends in the same spot will ever get it round. That one is answered by
## sliding the bend along the face, away from the run it came in on, until it
## comes past the edge.
func _grow_wraps_from_end(moving_end: Vector3, far_end: Vector3, at_suit_end: bool) -> void:
	for attempt: int in range(CarryKnobs.TETHER_WRAP_ITERATIONS):
		var edge_index := _tether_wraps.size() - 1 if at_suit_end else 0
		var span_start := far_end
		var inboard_point := far_end
		if not _tether_wraps.is_empty():
			span_start = _tether_wraps[edge_index]
			var inboard_index := edge_index - 1 if at_suit_end else 1
			if inboard_index >= 0 and inboard_index < _tether_wraps.size():
				inboard_point = _tether_wraps[inboard_index]

		var snag := _cast_along_span(span_start, moving_end)
		if snag.is_empty():
			return

		var contact_point: Vector3 = snag["position"]
		var contact_normal: Vector3 = snag["normal"]
		var bend := contact_point + contact_normal * CarryKnobs.TETHER_WRAP_OFFSET
		if bend.distance_to(span_start) >= CarryKnobs.TETHER_MIN_WRAP_SPACING:
			if _tether_wraps.size() >= CarryKnobs.TETHER_MAX_WRAPS:
				return
			if at_suit_end:
				_tether_wraps.append(bend)
			else:
				_tether_wraps.insert(0, bend)
			continue

		if _tether_wraps.is_empty():
			# The anchor itself is up against the hull, which happens when you
			# back into a wall. There is no bend to slide, and moving an anchor
			# is not this function's business.
			return

		var slide_direction := (span_start - inboard_point).slide(contact_normal)
		if slide_direction.is_zero_approx():
			return
		_tether_wraps[edge_index] = (
			span_start + slide_direction.normalized() * CarryKnobs.TETHER_CORNER_SLIDE
		)


func _is_span_blocked(from_point: Vector3, to_point: Vector3) -> bool:
	return not _cast_along_span(from_point, to_point).is_empty()


## Casts one span of the line at the hull, returning the raw intersection or an
## empty dictionary when the span is clear.
func _cast_along_span(from_point: Vector3, to_point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		from_point, to_point, CarryKnobs.TETHER_WRAP_LAYERS
	)
	return get_world_3d().direct_space_state.intersect_ray(query)


## The effective mass of the two-body pair. Deriving stiffness from this keeps
## a spring's frequency meaningful on its own whatever the object weighs. What
## does change with mass is who moves: the same force divided by 350 kg barely
## shifts the object, divided by 90 kg it throws the player around.
func _measure_reduced_mass() -> float:
	return 1.0 / (1.0 / CarryKnobs.PLAYER_MASS + 1.0 / _held_object.mass)


## Redraws the rope along its whole bent path. Worth having even though nothing
## about it is physical: on a tether the load spends most of its time behind
## you and out of the lamp, and this is the only thing telling you where it is,
## what it has caught on, and whether it has gone taut.
##
## The bow in a slack line is a drawing cue rather than a simulation. There is
## no down to hang toward in zero g, so slack is shown by letting the line
## trail the way you came, which is roughly where its own inertia would leave
## it. Standing still it draws straight, having nothing to trail.
func _update_tether_line() -> void:
	var shows_tether := _held_object != null and _carry_mode == CarryKnobs.CarryMode.TETHER
	_tether_line.visible = shows_tether
	if not shows_tether:
		return

	var path := PackedVector3Array()
	path.append(_held_object.global_transform * _object_local_anchor)
	path.append_array(_tether_wraps)
	path.append(global_transform * _suit_local_anchor)

	var slack := maxf(CarryKnobs.TETHER_LENGTH - _link_distance, 0.0)
	var bow := -velocity.normalized() * slack * CarryKnobs.TETHER_SAG_SCALE

	_tether_mesh.clear_surfaces()
	_tether_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for span_index: int in range(path.size() - 1):
		_add_tether_span(path[span_index], path[span_index + 1], bow)
	_tether_mesh.surface_add_vertex(path[path.size() - 1])
	_tether_mesh.surface_end()


## Adds one span of the rope, up to but not including its far end, so that
## consecutive spans join without doubling a vertex. The bow is shared out by
## length, each span taking the share of the slack it accounts for.
func _add_tether_span(span_start: Vector3, span_end: Vector3, bow: Vector3) -> void:
	if bow.is_zero_approx() or _link_distance <= 0.0:
		_tether_mesh.surface_add_vertex(span_start)
		return

	var span_bow := bow * (span_start.distance_to(span_end) / _link_distance)
	for step: int in range(CarryKnobs.TETHER_LINE_SEGMENTS):
		var along := float(step) / float(CarryKnobs.TETHER_LINE_SEGMENTS)
		# Peaks at 1.0 halfway along and vanishes at both ends, so the rope
		# stays pinned where it is actually anchored or bent.
		var bow_profile := 4.0 * along * (1.0 - along)
		_tether_mesh.surface_add_vertex(span_start.lerp(span_end, along) + span_bow * bow_profile)


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

	velocity += (
		global_transform.basis * thrust_input * CarryKnobs.THRUST_ACCELERATION * delta
	)

	if stabilizers_engaged:
		velocity = velocity.lerp(
			Vector3.ZERO, minf(CarryKnobs.LINEAR_STABILIZER_RATE * delta, 1.0)
		)

	velocity = velocity.limit_length(CarryKnobs.MAX_SPEED)


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
## body spin. The transfer factor stands in for a moment of inertia the suit
## does not model, so it is a feel dial rather than a physical quantity.
func _add_spin_from_impulse(
	velocity_change: Vector3, application_point: Vector3, transfer: float
) -> void:
	var lever_arm := application_point - global_position
	var world_torque := lever_arm.cross(velocity_change)

	# angular_velocity is held in body-local axes, so the torque has to come
	# back out of world space before it can be added.
	angular_velocity += global_transform.basis.inverse() * world_torque * transfer
	angular_velocity = angular_velocity.limit_length(CarryKnobs.MAX_ANGULAR_SPEED)
