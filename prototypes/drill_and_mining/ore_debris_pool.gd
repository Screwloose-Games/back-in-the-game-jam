class_name OreDebrisPool
extends Node3D

## The rock the drill throws: a fixed set of bodies, reused.
##
## Fragments are spawned at a RATE by the beam rather than one per piece of rock
## removed - there is no piece, the field just recedes - which is what makes how
## violently the room fills up a separate number from how fast the hole deepens.
##
## The beam decides WHEN, and the gap it waited decides WHAT: this file is handed
## a heft and turns it into size, mass, lifetime and tumble. Nothing else about a
## fragment varies, so there is one dial for "big" rather than four that can
## disagree about which fragments are the big ones.
##
## A pool rather than spawn-and-free for two reasons and only one of them is
## performance. At the tuned rate the room would otherwise hold hundreds of
## fragments, which is unreadable long before it is slow. Recycling the oldest
## means the cap never stops you drilling; it only decides what is still there.
##
## Every body is built once at startup and parked. Parked means frozen, hidden,
## and on no collision layer at all, so nothing can hit a fragment that is not
## supposed to be there.

const ROCK_MATERIAL := preload("res://prototypes/drill_and_mining/materials/rock_material.tres")

var _bodies: Array[RigidBody3D] = []
var _shapes: Array[BoxShape3D] = []
var _meshes: Array[MeshInstance3D] = []
var _remaining_life := PackedFloat32Array()

## What each live fragment was launched with. Per-fragment rather than one number
## for the pool, because heft stretches a heavy one's life - so the fade has to
## ask the fragment how long it had, not the knob.
var _full_life := PackedFloat32Array()
var _full_scale: Array[Vector3] = []

## The impulse each live fragment was actually thrown with. Recorded rather than
## assumed so describe_newest can report the speed that follows from it.
var _launch_impulse := PackedFloat32Array()
var _launch_order: Array[int] = []

## Pushed in from the settings resource; see apply_tuning.
var _knock := DrillKnobs.DEBRIS_KNOCK
var _lifetime := DrillKnobs.DEBRIS_LIFETIME


func _ready() -> void:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	for index in DrillKnobs.DEBRIS_POOL_SIZE:
		_build_body(index, unit_box)


func _physics_process(delta: float) -> void:
	for index in _bodies.size():
		if _remaining_life[index] <= 0.0:
			continue
		_remaining_life[index] -= delta
		if _remaining_life[index] <= 0.0:
			_park(index)
			continue
		_apply_fade(index)


## Throws one fragment out of the hole at `world_point`, along `aim`.
##
## `aim` is the spray direction the beam worked out, not the beam - see
## DrillBeam._spray_direction. This end of it only scatters what it is handed.
##
## `heft` is how long the drill waited before throwing this one, 0 to 1 - see
## DrillBeam._heft_of. IT IS THE ONLY THING THAT VARIES A FRAGMENT. Size, mass
## and lifetime all come off it, so a piece that took a while to come loose is
## big, heavy, slow and still in the room after the grit has gone.
func launch(world_point: Vector3, aim: Vector3, heft: float) -> void:
	var index := _claim()
	if index < 0:
		return

	var edge := lerpf(DrillKnobs.DEBRIS_SIZE_MIN, DrillKnobs.DEBRIS_SIZE_MAX, heft)
	var size := Vector3(_draw_aspect(), _draw_aspect(), _draw_aspect()) * edge
	var body := _bodies[index]
	_shapes[index].size = size
	_meshes[index].scale = size
	_full_scale[index] = size
	# The impulse below is the same for every fragment, so this is also what makes
	# a big one slow: the same kick of rock coming apart moves more of it less.
	body.mass = DrillKnobs.DEBRIS_MASS * lerpf(1.0, DrillKnobs.DEBRIS_HEAVY_MASS_SCALE, heft)

	body.freeze = true
	body.global_transform = Transform3D(_random_basis(), world_point)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.collision_layer = DrillKnobs.DEBRIS_LAYER
	# NOT the ore layer. Fragments that collided with rock would pack into the
	# hole being cut and shield it, which reads as the beam having stopped
	# working - and the beam walks the field rather than the shapes, so they
	# would be blocking nothing but the eye.
	body.collision_mask = DrillKnobs.HULL_LAYER | DrillKnobs.PLAYER_LAYER | DrillKnobs.DEBRIS_LAYER
	body.visible = true
	body.freeze = false

	body.apply_impulse(_scatter(aim) * _knock)
	_launch_impulse[index] = _knock
	# Divided by the mass scaling, so a slab tumbles lazily where grit whirls.
	# Angular velocity is set rather than applied, so it does not get this free.
	body.angular_velocity = (
		_random_direction()
		* randf()
		* DrillKnobs.DEBRIS_SPIN
		/ lerpf(1.0, DrillKnobs.DEBRIS_HEAVY_MASS_SCALE, heft)
	)

	_full_life[index] = _lifetime * lerpf(1.0, DrillKnobs.DEBRIS_HEAVY_LIFETIME_SCALE, heft)
	_remaining_life[index] = _full_life[index]
	_launch_order.append(index)


## Pushes the two tuned numbers on. `lifetime` is the LIGHTEST fragment's; heft
## stretches it from there.
##
## Only new fragments get the new lifetime -
## rewriting the clocks of everything already in the air would make the slider
## retroactive, and a room that emptied itself the moment you touched a slider
## would be hiding the thing you were trying to look at.
func apply_tuning(knock: float, lifetime: float) -> void:
	_knock = knock
	_lifetime = lifetime


## How many fragments are loose right now. The HUD reads it; it is also the
## number to watch if the room starts feeling like soup.
func get_active_count() -> int:
	return _launch_order.size()


## What the last fragment launched came out as. For verify_drill; nothing in the
## prototype reads it.
##
## The speed is derived from the impulse rather than read off the body, because
## an impulse does not reach linear_velocity until the physics step and the
## verifier asks before one has run.
func describe_newest() -> Dictionary:
	if _launch_order.is_empty():
		return {}
	var index: int = _launch_order[-1]
	var size: Vector3 = _full_scale[index]
	var mass := _bodies[index].mass
	return {
		"volume": size.x * size.y * size.z,
		"mass": mass,
		"speed": _launch_impulse[index] / mass,
		"life": _full_life[index],
	}


## Parks everything, for the reset key.
func clear() -> void:
	for index in _bodies.size():
		if _remaining_life[index] > 0.0:
			_park(index)


func _build_body(index: int, unit_box: BoxMesh) -> void:
	var body := RigidBody3D.new()
	body.name = "Debris%02d" % index
	# Zero-g: a fragment goes where the beam sent it and nowhere else.
	body.gravity_scale = 0.0
	body.mass = DrillKnobs.DEBRIS_MASS
	body.linear_damp = DrillKnobs.DEBRIS_LINEAR_DAMP
	body.angular_damp = DrillKnobs.DEBRIS_ANGULAR_DAMP
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.can_sleep = false
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze = true
	body.visible = false

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = unit_box
	mesh_instance.material_override = ROCK_MATERIAL
	# Dozens of tumbling fragments each casting a shadow, in a room lit by one
	# spotlight, buys nothing you can pick out and costs a shadow pass apiece.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	add_child(body)

	_bodies.append(body)
	_shapes.append(shape)
	_meshes.append(mesh_instance)
	_full_scale.append(Vector3.ONE)
	_remaining_life.append(0.0)
	_full_life.append(0.0)
	_launch_impulse.append(0.0)


## A parked slot, or the oldest live one when every slot is taken.
func _claim() -> int:
	for index in _bodies.size():
		if _remaining_life[index] <= 0.0:
			return index
	if _launch_order.is_empty():
		return -1
	var oldest: int = _launch_order[0]
	_park(oldest)
	return oldest


func _park(index: int) -> void:
	var body := _bodies[index]
	body.freeze = true
	body.visible = false
	body.collision_layer = 0
	body.collision_mask = 0
	_remaining_life[index] = 0.0
	_launch_order.erase(index)


## A fragment shrinks away over the last of its life rather than blinking out.
## The mesh shrinks and the body does not, which is invisible - by the time it is
## small enough to matter it is about to be parked anyway.
func _apply_fade(index: int) -> void:
	var fade_window := _full_life[index] * DrillKnobs.DEBRIS_FADE_FRACTION
	if fade_window <= 0.0 or _remaining_life[index] > fade_window:
		return
	var fade := clampf(_remaining_life[index] / fade_window, 0.0, 1.0)
	_meshes[index].scale = _full_scale[index] * fade


## The spray direction, tipped by a random amount inside DEBRIS_SPREAD_DEGREES.
## Without the spread every fragment leaves along exactly the same line and the
## hole reads as a conveyor belt rather than as rock breaking.
func _scatter(aim: Vector3) -> Vector3:
	if aim.is_zero_approx():
		return _random_direction()
	var spread := deg_to_rad(DrillKnobs.DEBRIS_SPREAD_DEGREES)
	var tilt_axis := aim.cross(_random_direction())
	if tilt_axis.is_zero_approx():
		return aim.normalized()
	return aim.normalized().rotated(tilt_axis.normalized(), randf_range(-spread, spread))


## One axis of a fragment, as a fraction of the edge heft asked for. Without it
## heft would produce a graded set of cubes.
func _draw_aspect() -> float:
	return randf_range(1.0 - DrillKnobs.DEBRIS_ASPECT_JITTER, 1.0 + DrillKnobs.DEBRIS_ASPECT_JITTER)


func _random_direction() -> Vector3:
	var direction := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
	if direction.is_zero_approx():
		return Vector3.UP
	return direction.normalized()


func _random_basis() -> Basis:
	return Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
