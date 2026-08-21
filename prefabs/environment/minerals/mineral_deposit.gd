@tool
class_name MineralDeposit
extends Node3D

## A small cluster of mineral chunks placed in the level. Mining out every chunk
## it spawned is what "mining out" this deposit means -- each chunk hands its
## pieces to the player as it is mined, and frees itself once spent.

const CHUNK_SCENE := preload("res://prefabs/environment/minerals/prefab_mineral_chunk.tscn")
const DEFAULT_TUNING := preload("res://systems/minerals/mining_tuning_default.tres")
const CLUSTER_RADIUS := 1.2

## How far the "Snap to Nearest Wall" editor button will reach to find rock.
const SNAP_MAX_DISTANCE := 5.0

## Directions sampled around the deposit when hunting for the nearest wall.
const SNAP_RAY_DIRECTIONS := 32

const SNAP_COLLISION_MASK := 1

@export var mineral_type: MineralType
@export var chunk_count: int = 5
@export var tuning: MiningTuning = DEFAULT_TUNING

@export_tool_button("Snap to Nearest Wall") var snap_to_wall_action := snap_to_nearest_wall


func _ready() -> void:
	for _i in chunk_count:
		var chunk := CHUNK_SCENE.instantiate() as MineralChunk
		chunk.mineral_type = mineral_type
		chunk.tuning = tuning
		chunk.position = Vector3(
			randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS),
			randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS),
			randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS)
		)
		add_child(chunk)


## Editor-only. Casts a sphere of rays from this deposit and moves it to the
## nearest surface hit, so it can be dressed onto a cave wall, floor or
## ceiling like a stalactite or stalagmite. No-ops if nothing is within
## SNAP_MAX_DISTANCE.
func snap_to_nearest_wall() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return

	var space := get_world_3d().direct_space_state
	var exclude := _own_body_rids()
	var closest_position := Vector3.ZERO
	var closest_distance := SNAP_MAX_DISTANCE
	var found_hit := false

	for direction in _sample_sphere_directions(SNAP_RAY_DIRECTIONS):
		var query := PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + direction * SNAP_MAX_DISTANCE,
			SNAP_COLLISION_MASK,
			exclude
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var distance := global_position.distance_to(hit.position)
		if distance < closest_distance:
			closest_distance = distance
			closest_position = hit.position
			found_hit = true

	if not found_hit:
		push_warning(
			(
				"MineralDeposit '%s' found no cave wall within %.1fm; not moved."
				% [name, SNAP_MAX_DISTANCE]
			)
		)
		return

	global_position = closest_position


## Physics bodies spawned by this deposit, so the wall search does not hit its
## own chunks instead of the cave.
func _own_body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for body in find_children("*", "PhysicsBody3D", true, false):
		rids.append((body as PhysicsBody3D).get_rid())
	return rids


## Evenly spaced directions on the unit sphere, via a Fibonacci sphere.
func _sample_sphere_directions(count: int) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (float(i) / float(count - 1)) * 2.0
		var radius := sqrt(1.0 - y * y)
		var theta := golden_angle * i
		directions.append(Vector3(cos(theta) * radius, y, sin(theta) * radius))
	return directions
