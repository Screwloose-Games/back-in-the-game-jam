class_name ChaseTargetFollower
extends Marker3D

## The creature's INTENT, flown by a navmesh instead of by a keyboard.
##
## A PEER OF MarkerPilot, not a wrapper around it. MarkerPilot's entire contract
## with the creature is one line - CrawlerBody reads `target_marker.global_position`
## and leashes to it - and `target_marker` is typed Node3D. Everything else over
## there (mouse look, roll, adopting the camera's facing, owning the pointer)
## exists for the human holding it. So the autonomous version is another node that
## fills the same slot: swap one for the other in the scene tree and the creature
## cannot tell, which is also why none of this needed a single edit to the tentacle
## crawler prototype.
##
## The movement below is MarkerPilot's, deliberately unchanged - the same
## accelerate-toward-wanted lerp, the same lower brake than accel so releasing
## coasts rather than stopping dead. One substitution:
##
##     MarkerPilot                             ChaseTargetFollower
##     wish from Input.get_action_strength     wish from the agent's next corner
##     wanted = global_basis * wish * speed    wanted = wish * speed
##
## The second line is the whole difference between an intent expressed in the
## pilot's own frame and one expressed in the world's.
##
## THERE IS NO SEPARATE SURFACE OFFSET KNOB, and there was going to be.
## `clearance_radius` is the whole answer: containment pushes the marker that far
## off any wall, and `_lifted` aims it at that same distance off the navmesh, so
## the two agree rather than fight. The creature then keeps its own, larger
## distance behind through probe_comfort and its depenetration radius. Three
## systems, one number between them, all of it already tuned.

## The six directions containment probes along. World axes rather than local, for
## MarkerPilot's reason: a wall does not care which way you are facing.
const AXES: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3.BACK,
	Vector3.FORWARD,
]

@export_group("Wiring")
@export var chase_target: ChaseTarget
## Off until the prototype root has baked the navmesh. A follower that starts
## pathing against an empty map walks to the world origin, dragging the creature
## through the divider on its way, and looks for all the world like a broken
## navmesh rather than one that merely is not built yet.
@export var enabled: bool = false

@export_group("Flight")
@export var move_speed: float = ChaseKnobs.FOLLOWER_SPEED
@export var accel: float = ChaseKnobs.FOLLOWER_ACCEL
@export var brake: float = ChaseKnobs.FOLLOWER_BRAKE

@export_group("Navigation")
@export var repath_interval: float = ChaseKnobs.FOLLOWER_REPATH_INTERVAL
@export var path_desired_distance: float = ChaseKnobs.FOLLOWER_PATH_DESIRED_DISTANCE
@export var target_desired_distance: float = ChaseKnobs.FOLLOWER_TARGET_DESIRED_DISTANCE

@export_group("Containment")
@export var clearance_radius: float = ChaseKnobs.FOLLOWER_CLEARANCE
@export_flags_3d_physics var containment_mask: int = ChaseKnobs.FOLLOWER_CONTAINMENT_MASK

var _velocity: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0

@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	_agent.path_desired_distance = path_desired_distance
	_agent.target_desired_distance = target_desired_distance
	# RVO resolves in a plane about the map's up axis, which is meaningless for
	# an agent whose whole job is to be on the ceiling half the time. There is
	# also exactly one agent, so there is nothing here to avoid.
	_agent.avoidance_enabled = false


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_update_destination(delta)
	_apply_movement(delta)
	_apply_containment()


## Drop the marker somewhere and kill its momentum. For the reset key: writing
## global_position alone would leave the old velocity running, and the marker
## would set off across the chamber the instant it landed.
func teleport(to: Vector3) -> void:
	global_position = to
	_velocity = Vector3.ZERO
	_elapsed = repath_interval


func current_speed() -> float:
	return _velocity.length()


## The corners of the path currently being walked, for the debug overlay.
func path_points() -> PackedVector3Array:
	return _agent.get_current_navigation_path()


## Metres still to walk, following the path rather than the straight line - the
## difference between the two is how far out of its way the divider is sending it.
func path_length() -> float:
	var corners := path_points()
	if corners.size() < 2:
		return 0.0
	var total := 0.0
	for i: int in range(1, corners.size()):
		total += corners[i - 1].distance_to(corners[i])
	return total


func debug_state() -> Dictionary:
	return {
		"enabled": enabled,
		"speed": current_speed(),
		"position": global_position,
		"path_length": path_length(),
		"corners": path_points().size(),
		"arrived": _agent.is_navigation_finished(),
	}


func _update_destination(delta: float) -> void:
	_elapsed += delta
	if _elapsed < repath_interval:
		return
	_elapsed = 0.0
	if chase_target == null or not chase_target.is_valid():
		return
	_agent.target_position = chase_target.surface_position()


func _apply_movement(delta: float) -> void:
	var wish := Vector3.ZERO
	if not _agent.is_navigation_finished():
		# Normalised rather than clamped, which is the one place this departs
		# from MarkerPilot's feel on purpose. A stick can be pushed halfway; a
		# path corner is either where you are going or it is not, and scaling
		# with distance-to-corner would make the marker crawl the last metre of
		# every leg and stall the creature at every turn.
		wish = (_lifted(_agent.get_next_path_position()) - global_position).normalized()

	var wanted := wish * move_speed
	var rate := brake if wish.is_zero_approx() else accel
	_velocity = _velocity.lerp(wanted, 1.0 - exp(-rate * delta))
	global_position += _velocity * delta


## A path corner, lifted off the surface it sits on by the marker's own clearance.
##
## The navmesh is painted ON the walls, so every corner the agent hands back is a
## point inside one. Steering straight at it means most of the wish vector points
## into the wall, containment cancels exactly that part, and what is left is the
## sideways remainder - the marker crabs along at a fraction of move_speed and the
## creature never gets a taut leash. Measured at 0.95 m/s against a move_speed of
## 6.0 before this line existed.
##
## Lifting by `clearance_radius` aims at the place containment was going to put it
## anyway, so the two agree instead of cancelling. That is also the honest answer
## to where the standoff lives: one number, used twice, rather than a separate
## offset knob that could disagree with it.
func _lifted(point: Vector3) -> Vector3:
	var normal := NavigationServer3D.map_get_closest_point_normal(
		_agent.get_navigation_map(), point
	)
	if normal.is_zero_approx():
		return point
	return point + normal * clearance_radius


## MarkerPilot's containment, unchanged, and load-bearing for a reason that only
## applies here: the navmesh is painted ON the surfaces, so every destination this
## marker is given is a point inside a wall. This is what holds it a metre out in
## the room instead, and it is why there is no offset knob anywhere above.
##
## Only the inward component of velocity is killed, never reflected - a marker
## that bounces off the corridor makes the creature jitter along the wall.
func _apply_containment() -> void:
	var space := get_world_3d().direct_space_state
	for axis: Vector3 in AXES:
		var from := global_position
		var query := PhysicsRayQueryParameters3D.create(
			from, from + axis * clearance_radius, containment_mask
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		var depth: float = clearance_radius - from.distance_to(hit["position"] as Vector3)
		if depth > 0.0:
			global_position += normal * depth
		var inward := _velocity.dot(-normal)
		if inward > 0.0:
			_velocity += normal * inward
