class_name CreatureAwarenessCreature
extends CharacterBody3D

## The body the navigation module drives, and the label that says what it is doing.
##
## LIFTED ALMOST VERBATIM FROM `creature_nav_demo_creature.gd`, with one addition: the label
## carries a behaviour line as well as a locomotion line, because this prototype has a
## behaviour layer and that one is the whole point.
##
## A CharacterBody3D RATHER THAN A KINEMATIC Node3D. The controllers emit a desired
## DIRECTION and SPEED, not a resolved position (see NavMotionCommand), so something has to
## resolve contact -- `move_and_slide` is that for free. A raw Node3D teleports into a wall
## whenever a steer is slightly off, and every such frame reads as a navigation bug rather
## than as the steering error it is.
##
## LAYER 0, MASK 1, AND THIS IS THE EASIEST WAY TO LOSE A DAY. The creature collides with
## the hull and nothing collides with the creature. If it sat on the navigation world mask
## instead, `shape_fits` at the body's own position would find the body, every candidate
## under it would fail, and the alien would freeze solid with nothing in the log.
##
## PERCEPTION HANGS OFF THIS NODE, and that is not tidiness. `CreaturePerception._own_position`
## returns its own `global_position`, so a perception node parented anywhere else measures
## every noise from the wrong place -- and a node not in the tree at all measures from the
## origin, which in this cave is the middle of the Dock.

## How fast the mesh and collider follow the squeeze, per second. Fast enough to read as
## the body compressing, slow enough that it is not a pop.
const SQUEEZE_LERP: float = 8.0
const LABEL_HEIGHT: float = 3.2

@export var navigation: CreatureNavigation = null
@export var enabled: bool = false

## Set by the behaviour layer each frame. Shown above the locomotion mode.
var status_line: String = ""

var _mesh: MeshInstance3D = null
var _sphere: SphereMesh = null
var _shape: SphereShape3D = null
var _label: Label3D = null
var _radius: float = 1.25


func _ready() -> void:
	# Zero gravity: the cave has none, and section 11.1's leap is a straight line.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = CreatureAwarenessMap.TERRAIN_LAYER
	_build_body()
	_build_label()


func _physics_process(delta: float) -> void:
	if navigation == null:
		return
	navigation.set_body_state(global_position, velocity, _facing(), transform.basis.y)
	if not enabled:
		return
	_apply(navigation.command, delta)
	_refresh_label()


func _build_body() -> void:
	var profile: ClearanceProfile = _profile()
	_radius = profile.normal_clearance()

	_sphere = SphereMesh.new()
	_sphere.radial_segments = 16
	_sphere.rings = 10
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.35, 0.45, 1.0)
	material.roughness = 0.6
	# Faintly lit from within, so the body still reads against dark rock in the ant-farm
	# view where there is no helmet lamp pointing at it.
	material.emission_enabled = true
	material.emission = Color(0.5, 0.1, 0.16, 1.0)
	material.emission_energy_multiplier = 0.6
	_mesh.material_override = material
	add_child(_mesh)

	_shape = SphereShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	add_child(collider)
	_resize(_radius)


func _build_label() -> void:
	_label = Label3D.new()
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Readable from inside a tunnel, which is where half the interesting states happen, and
	# through rock from the ant-farm camera, which is where the rest of them happen.
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.outline_size = 12
	_label.font_size = 48
	_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	add_child(_label)


## Turns one NavMotionCommand into movement. Everything navigation decides arrives here and
## nowhere else.
func _apply(command: NavMotionCommand, delta: float) -> void:
	if command == null:
		return
	var profile: LocomotionProfile = navigation.config.locomotion_profile
	_squeeze_toward(command.squeeze, delta)

	if navigation.local_planner.is_airborne():
		# Invariant 4: the velocity was fixed at launch and is re-emitted unchanged. The body
		# must not blend toward it, or the leap becomes steerable by accident.
		velocity = command.leap_velocity
	elif command.desired_speed <= 0.0:
		velocity = velocity.move_toward(Vector3.ZERO, profile.crawl_acceleration * delta)
	else:
		var wanted: Vector3 = command.desired_direction * command.desired_speed
		velocity = velocity.move_toward(wanted, profile.crawl_acceleration * delta)
	move_and_slide()

	if not command.preferred_forward.is_zero_approx():
		look_at(global_position + command.preferred_forward, command.preferred_up)


func _squeeze_toward(squeezing: bool, delta: float) -> void:
	var profile: ClearanceProfile = _profile()
	var target: float = (
		profile.min_traversal_clearance() if squeezing else profile.normal_clearance()
	)
	_resize(move_toward(_radius, target, SQUEEZE_LERP * delta))


## THE CLEARANCES, NOT THE BARE RADII, AND THE DIFFERENCE WEDGES THE CREATURE PERMANENTLY.
##
## `ClearanceProfile.normal_body()` -- the shape every swept cast in the module is made with
## -- is a sphere of `normal_clearance()`, which is the body radius PLUS the safety margin.
## Give the collider only `normal_radius_equivalent` and the physics engine will happily
## park the body 1.10 m from a ceiling that navigation plans against at 1.25 m. From that
## pose `shape_sweep_clear`'s origin-overlap test reports penetration, EVERY candidate in
## every mode is rejected, and the creature never moves again.
func _resize(radius: float) -> void:
	_radius = radius
	_sphere.radius = radius
	_sphere.height = radius * 2.0
	_shape.radius = radius


func _refresh_label() -> void:
	var planner: NavLocalPlanner = navigation.local_planner
	var lines: Array[String] = []
	if not status_line.is_empty():
		lines.append(status_line)
	lines.append(NavLocomotion.mode_name(planner.mode()).to_upper())

	if navigation.command != null and navigation.command.recovering:
		# Above the inspection state on purpose: a body working itself off a wall or back to
		# one is the most misreadable thing in the scene, because it moves slowly in a
		# direction the route did not ask for and looks exactly like broken steering.
		lines.append("reacquiring")
	elif navigation.inspector.is_busy():
		lines.append(NavInspector.state_name(navigation.inspector.state()))
	elif navigation.command != null and navigation.command.is_stalled():
		lines.append("! " + NavMotionCommand.abort_name(navigation.command.abort))
	elif navigation.command != null and navigation.command.preparing_leap:
		lines.append("winding up")
	elif planner.wiggler.squeeze_fraction() > 0.01:
		lines.append("squeeze %d%%" % int(planner.wiggler.squeeze_fraction() * 100.0))

	var route: NavRoute = navigation.route
	if route != null:
		lines.append(
			(
				"%s  %d/%d"
				% [
					route.status_name().to_lower(),
					navigation.follower.index,
					maxi(route.anchors.size() - 1, 0)
				]
			)
		)
	_label.text = "\n".join(lines)
	_label.modulate = _mode_colour(planner.mode())


static func _mode_colour(mode: NavLocomotion.Mode) -> Color:
	match mode:
		NavLocomotion.Mode.SURFACE_CRAWL:
			return Color(0.55, 1.0, 0.65, 1.0)
		NavLocomotion.Mode.TUNNEL_SWIM:
			return Color(0.55, 0.80, 1.0, 1.0)
		NavLocomotion.Mode.WIGGLE:
			return Color(1.0, 0.75, 0.35, 1.0)
		NavLocomotion.Mode.LEAP:
			return Color(1.0, 0.60, 1.0, 1.0)
	return Color(1.0, 1.0, 1.0, 1.0)


func _facing() -> Vector3:
	if velocity.is_zero_approx():
		return -transform.basis.z
	return velocity.normalized()


func _profile() -> ClearanceProfile:
	if navigation != null and navigation.config != null:
		return navigation.config.clearance_profile
	return ClearanceProfile.new()
