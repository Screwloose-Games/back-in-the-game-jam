@tool
class_name MineralDeposit
extends Node3D

## A small cluster of mineral chunks placed in the level. Mining out every chunk
## it spawned is what "mining out" this deposit means -- each chunk hands its
## pieces to the player as it is mined, and frees itself once spent.

const CHUNK_SCENE := preload("res://prefabs/environment/minerals/prefab_mineral_chunk.tscn")
const DEFAULT_TUNING := preload("res://systems/minerals/mining_tuning_default.tres")
const CLUSTER_RADIUS := 1.2

## The marker every chunk is grown upwards from and the snap drives into the wall.
const FORMATION_BOTTOM := ^"%MineralFormationBottom"

## How far the "Snap to Nearest Wall" editor button will reach to find rock.
const SNAP_MAX_DISTANCE := 5.0

## Directions sampled around the formation bottom when hunting for the nearest wall.
const SNAP_RAY_DIRECTIONS := 32

## How far past the rock surface the formation bottom, and each chunk's base, is
## buried, so none of them shows its flat underside.
const SNAP_EMBED_DEPTH := 0.25

const SNAP_COLLISION_MASK := 1

@export var mineral_type: MineralType
@export var chunk_count: int = 5
@export var tuning: MiningTuning = DEFAULT_TUNING

@export_tool_button("Snap to Nearest Wall") var snap_to_wall_action := snap_to_nearest_wall


func _ready() -> void:
	if _chunks().is_empty():
		_scatter_chunks()
	if Engine.is_editor_hint():
		return
	for chunk in _chunks():
		chunk.configure(mineral_type, tuning)


## Editor-only dressing pass: this deposit moves until its formation bottom is
## inside the nearest surface and every chunk then slides along the deposit's own
## Y axis until its base is buried too, keeping both its scatter and the prefab's
## orientation.
func snap_to_nearest_wall() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_snap_self_to_nearest_wall()
	dress_in_place()


## The same dressing pass without the move, for a caller that has already chosen
## where this deposit goes and which way it faces. MineralScatter is that caller.
func dress_in_place() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_bury_chunk_bases()
	_bake_chunks()


## Moves this deposit so its formation bottom ends up SNAP_EMBED_DEPTH inside the
## nearest surface a sphere of rays cast from that same marker can reach.
func _snap_self_to_nearest_wall() -> void:
	var anchor := _formation_bottom_position()
	var target := _nearest_surface_target(
		get_world_3d().direct_space_state, _own_body_rids(), anchor
	)

	if target.is_empty():
		push_warning(
			(
				"MineralDeposit '%s' found no cave wall within %.1fm of its bottom; not moved."
				% [name, SNAP_MAX_DISTANCE]
			)
		)
		return

	global_position += (target["position"] as Vector3) - anchor


## Where the formation bottom belongs -- SNAP_EMBED_DEPTH inside the nearest
## surface around `anchor` -- or an empty dictionary when nothing is in reach.
func _nearest_surface_target(
	space: PhysicsDirectSpaceState3D, exclude: Array[RID], anchor: Vector3
) -> Dictionary:
	var target := {}
	var closest := SNAP_MAX_DISTANCE

	for direction in _sample_sphere_directions(SNAP_RAY_DIRECTIONS):
		var far_point := anchor + direction * SNAP_MAX_DISTANCE
		# Probed from both ends, as in _surface_offset_along(): the trimesh is
		# backface-blind, so a bottom that is already inside rock -- where both a
		# fresh scatter and the previous snap leave it -- can only see the face it
		# is behind from the far side.
		var probes: Array[PackedVector3Array] = [
			PackedVector3Array([anchor, far_point]), PackedVector3Array([far_point, anchor])
		]
		for probe in probes:
			var query := PhysicsRayQueryParameters3D.create(
				probe[0], probe[1], SNAP_COLLISION_MASK, exclude
			)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var hit_position: Vector3 = hit.position
			var distance := anchor.distance_to(hit_position)
			if distance >= closest:
				continue
			closest = distance
			var heading := (probe[1] - probe[0]).normalized()
			target = {"position": hit_position - _surface_normal(hit, heading) * SNAP_EMBED_DEPTH}

	return target


## Slides each chunk along this deposit's Y axis -- never sideways, never
## rotated -- so its base ends up SNAP_EMBED_DEPTH inside the rock.
func _bury_chunk_bases() -> void:
	var space := get_world_3d().direct_space_state
	var exclude := _own_body_rids()
	var up := global_basis.y.normalized()
	var stranded := 0

	for chunk in _chunks():
		var base_point := chunk.global_transform * Vector3(0.0, _chunk_base_offset(chunk), 0.0)
		var offset := _surface_offset_along(space, exclude, base_point, up)
		if is_inf(offset):
			stranded += 1
			continue
		chunk.global_position += up * (offset - SNAP_EMBED_DEPTH)

	if stranded > 0:
		push_warning(
			(
				"MineralDeposit '%s': %d chunk(s) found no rock within %.1fm; left in place."
				% [name, stranded, SNAP_MAX_DISTANCE]
			)
		)


## Signed distance along `up` from `base_point` to the nearest surface in that
## column, probed from both ends of each half so a chunk that already starts
## inside rock finds the face it is behind, or INF when the column is empty.
func _surface_offset_along(
	space: PhysicsDirectSpaceState3D, exclude: Array[RID], base_point: Vector3, up: Vector3
) -> float:
	var closest := INF
	var headings: Array[Vector3] = [up, -up]
	for direction in headings:
		var far_point := base_point + direction * SNAP_MAX_DISTANCE
		var probes: Array[PackedVector3Array] = [
			PackedVector3Array([base_point, far_point]), PackedVector3Array([far_point, base_point])
		]
		for probe in probes:
			var query := PhysicsRayQueryParameters3D.create(
				probe[0], probe[1], SNAP_COLLISION_MASK, exclude
			)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var hit_position: Vector3 = hit.position
			var offset := up.dot(hit_position - base_point)
			if absf(offset) < absf(closest):
				closest = offset
	return closest


## Lowest point of a chunk's meshes in its own space, so the snap buries the
## visible base rather than the origin.
func _chunk_base_offset(chunk: Node3D) -> float:
	var to_chunk := chunk.global_transform.affine_inverse()
	var lowest := 0.0
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := (to_chunk * mesh_instance.global_transform) * mesh_instance.get_aabb()
		lowest = minf(lowest, bounds.position.y)
	return lowest


## Where the bottom of the formation sits in world space, falling back to this
## deposit's own origin for a hand-built one that carries no marker.
func _formation_bottom_position() -> Vector3:
	var marker := get_node_or_null(FORMATION_BOTTOM) as Node3D
	return global_position if marker == null else marker.global_position


## Spawns the cluster, only ever when the deposit has none, so a layout already
## baked into a level is never re-rolled.
func _scatter_chunks() -> void:
	var bottom := to_local(_formation_bottom_position())
	for i in chunk_count:
		var chunk := CHUNK_SCENE.instantiate() as MineralChunk
		chunk.name = "Chunk%d" % (i + 1)
		chunk.mineral_type = mineral_type
		chunk.tuning = tuning
		add_child(chunk)
		# Lifted by the chunk's own overhang, so its base rather than its origin
		# is what starts at the formation bottom.
		chunk.position = (
			bottom
			+ Vector3(
				randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS),
				randf_range(0.0, CLUSTER_RADIUS) - _chunk_base_offset(chunk),
				randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS)
			)
		)


## Hands the chunks to the scene being edited, so the dressed layout is what
## saves and what ships rather than a fresh scatter on the next load.
func _bake_chunks() -> void:
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return
	for chunk in _chunks():
		chunk.owner = scene_root
	# Looked up by name rather than named directly: the bare `EditorInterface`
	# identifier is compiled out of export templates, and this script ships.
	if Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").mark_scene_as_unsaved()


## The chunks of this deposit, whether scattered on load or baked into a level.
func _chunks() -> Array[MineralChunk]:
	var chunks: Array[MineralChunk] = []
	for child in get_children():
		if child is MineralChunk:
			chunks.append(child)
	return chunks


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


## The outward normal at a hit, falling back to the ray that found it when the
## trimesh reports a degenerate one.
static func _surface_normal(hit: Dictionary, heading: Vector3) -> Vector3:
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	return -heading if normal.length_squared() < 0.5 else normal.normalized()
