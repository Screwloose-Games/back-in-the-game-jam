class_name ChaseTarget
extends Node3D

## Where the creature wants to be, which is not where the player is.
##
## One hop of indirection, and the reason it exists is that the two things are
## never the same point. The player is a suit floating in the middle of a room;
## the creature crawls the shell of it. So "chase the player" has to become "get
## to the piece of wall nearest the player" before anything can act on it, and
## this is the node that does that conversion and nothing else.
##
## Splitting it out buys two things. The follower below stays purely about
## navigation and never learns what a quarry is, and with `quarry` left unwired
## this is simply a marker you drag around in the editor - which is how you test
## whether the navmesh connects with no player in the scene at all.

@export var quarry: Node3D
@export var refresh_interval: float = ChaseKnobs.TARGET_REFRESH_INTERVAL

var _normal: Vector3 = Vector3.ZERO
var _valid: bool = false
var _elapsed: float = 0.0


func _physics_process(delta: float) -> void:
	if quarry == null:
		return
	_elapsed += delta
	if _elapsed < refresh_interval:
		return
	_elapsed = 0.0
	_project()


## The point on the navmesh the creature should head for. This node moves itself
## there, so it is also visible in the remote scene tree while the game runs.
func surface_position() -> Vector3:
	return global_position


## Which way that piece of surface faces. Not used by the follower - the marker's
## own containment handles standoff - but it is what tells you at a glance
## whether the target has landed on the floor, a wall or the ceiling.
func surface_normal() -> Vector3:
	return _normal


## False until the navigation map has a mesh on it. The map is empty for the
## first frames while the chamber's CSG settles and the bake runs, and
## map_get_closest_point answers the origin rather than failing during that
## window - so anything reading this node has to be told to wait rather than
## being allowed to path to (0, 0, 0).
func is_valid() -> bool:
	return _valid


## How far the creature's destination is from the quarry itself: the thickness of
## room between the player and the nearest crawlable surface.
func standoff() -> float:
	if quarry == null:
		return 0.0
	return global_position.distance_to(quarry.global_position)


func _project() -> void:
	var map := get_world_3d().navigation_map
	if not NavigationServer3D.map_is_active(map):
		_valid = false
		return

	var quarry_point := quarry.global_position
	var normal := NavigationServer3D.map_get_closest_point_normal(map, quarry_point)
	# An empty map answers a zero normal rather than reporting that it has
	# nothing to answer with, and a zero normal is not a direction any polygon
	# can face - so this doubles as the "is there a mesh yet" test.
	if normal.is_zero_approx():
		_valid = false
		return

	_normal = normal
	_valid = true
	global_position = NavigationServer3D.map_get_closest_point(map, quarry_point)
