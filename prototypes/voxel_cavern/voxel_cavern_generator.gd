@tool
class_name VoxelCavernGenerator
extends VoxelGeneratorScript

## Carves a three-room-and-tunnels cavern out of a solid rock body and threads
## mineral veins through the rock that is left.
##
## Modelled on asteroid/generation/asteroid_voxel_generator.gd. All distances are
## in VOXELS, not metres: the VoxelTerrain node is scaled by VOXEL_SIZE, so the
## generator works in the unscaled voxel grid and the prototype root converts the
## metre knobs before calling configure().
##
## VoxelMesherBlocky meshes only axis-aligned cube faces, so every carve - room,
## tunnel, or the sphere a mining shot removes - leaves a fully perpendicular,
## stair-stepped surface. That is what makes the result read as "voxel-like".

const AIR := 0
const ROCK := 1
const MINERAL_A := 2
const MINERAL_B := 3
const CHANNEL := VoxelBuffer.CHANNEL_TYPE

var map_center_voxels := Vector3.ZERO
var map_radius_voxels := 67.0
var room_centers: PackedVector3Array = PackedVector3Array()
var room_radius_voxels := 15.0
var tunnel_starts: PackedVector3Array = PackedVector3Array()
var tunnel_ends: PackedVector3Array = PackedVector3Array()
var tunnel_radii: PackedFloat32Array = PackedFloat32Array()
var vein_frequency := 0.12
var vein_threshold_a := 0.32
var vein_threshold_b := 0.55
var world_seed := 0

var _noise: FastNoiseLite


func _init() -> void:
	_rebuild_noise()


## Sets the layout (in voxels) and rebuilds the vein noise. Called by the root
## before the generator is assigned to the terrain, on the main thread, so the
## noise and layout are ready before any (possibly threaded) block generation runs.
## `vein_params` packs (frequency, threshold_a, threshold_b) into one Vector3, to
## stay under the linter's argument-count limit.
func configure(
	map_center: Vector3,
	map_radius: float,
	rooms: PackedVector3Array,
	room_radius: float,
	starts: PackedVector3Array,
	ends: PackedVector3Array,
	radii: PackedFloat32Array,
	vein_params: Vector3,
	seed_value: int
) -> void:
	map_center_voxels = map_center
	map_radius_voxels = map_radius
	room_centers = rooms
	room_radius_voxels = room_radius
	tunnel_starts = starts
	tunnel_ends = ends
	tunnel_radii = radii
	vein_frequency = vein_params.x
	vein_threshold_a = vein_params.y
	vein_threshold_b = vein_params.z
	world_seed = seed_value
	_rebuild_noise()


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var size := out_buffer.get_size()

	# Whole-block early-out: a block whose nearest corner is already past the rock
	# body is uniform air. The buffer defaults to AIR, so returning without writing
	# leaves it correct and skips the per-voxel loop for everything outside the map.
	var block_min := Vector3(origin_in_voxels)
	var block_max := Vector3(origin_in_voxels + size)
	var nearest := Vector3(
		clampf(map_center_voxels.x, block_min.x, block_max.x),
		clampf(map_center_voxels.y, block_min.y, block_max.y),
		clampf(map_center_voxels.z, block_min.z, block_max.z)
	)
	if nearest.distance_to(map_center_voxels) > map_radius_voxels:
		return

	for z in range(size.z):
		for y in range(size.y):
			for x in range(size.x):
				var voxel_position := origin_in_voxels + Vector3i(x, y, z)
				var voxel_center := Vector3(voxel_position)
				var voxel_type := AIR
				if (
					voxel_center.distance_to(map_center_voxels) <= map_radius_voxels
					and not _is_carved(voxel_center)
				):
					voxel_type = _mineral_at(voxel_center)
				out_buffer.set_voxel(voxel_type, x, y, z, CHANNEL)


## True inside any room sphere or any tunnel capsule - i.e. the open space.
func _is_carved(position: Vector3) -> bool:
	for center: Vector3 in room_centers:
		if position.distance_to(center) < room_radius_voxels:
			return true
	for index: int in tunnel_starts.size():
		var distance := _distance_to_segment(position, tunnel_starts[index], tunnel_ends[index])
		if distance < tunnel_radii[index]:
			return true
	return false


func _mineral_at(position: Vector3) -> int:
	var value := _noise.get_noise_3dv(position)
	if value >= vein_threshold_b:
		return MINERAL_B
	if value >= vein_threshold_a:
		return MINERAL_A
	return ROCK


func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return point.distance_to(start)
	var progress := clampf((point - start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * progress)


func _rebuild_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = world_seed
	_noise.frequency = vein_frequency
