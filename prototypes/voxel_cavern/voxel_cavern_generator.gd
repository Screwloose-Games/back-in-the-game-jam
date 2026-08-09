@tool
class_name VoxelCavernGenerator
extends VoxelGeneratorScript

## Generates a solid rock body with a hollow spawn chamber at its centre and
## mineral veins threaded through the surrounding rock.
##
## Modelled on asteroid/generation/asteroid_voxel_generator.gd. All distances are
## in VOXELS, not metres: the VoxelTerrain node is scaled by VOXEL_SIZE, so the
## generator works in the unscaled voxel grid and the prototype root converts the
## metre knobs before calling configure().
##
## VoxelMesherBlocky meshes only axis-aligned cube faces, so every carve - even a
## sphere - leaves a fully perpendicular, stair-stepped surface. That is what makes
## the result read as "voxel-like".

const AIR := 0
const ROCK := 1
const MINERAL_A := 2
const MINERAL_B := 3
const CHANNEL := VoxelBuffer.CHANNEL_TYPE

var rock_body_radius_voxels := 83.0
var chamber_radius_voxels := 30.0
var vein_frequency := 0.09
var vein_threshold_a := 0.32
var vein_threshold_b := 0.55
var world_seed := 0

var _noise: FastNoiseLite


func _init() -> void:
	_rebuild_noise()


## Sets the generation parameters and rebuilds the vein noise. Called by the root
## before the generator is assigned to the terrain, on the main thread, so the
## noise is always ready before any (possibly threaded) block generation runs.
func configure(
	rock_body_radius: float,
	chamber_radius: float,
	frequency: float,
	threshold_a: float,
	threshold_b: float,
	seed_value: int
) -> void:
	rock_body_radius_voxels = rock_body_radius
	chamber_radius_voxels = chamber_radius
	vein_frequency = frequency
	vein_threshold_a = threshold_a
	vein_threshold_b = threshold_b
	world_seed = seed_value
	_rebuild_noise()


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var size := out_buffer.get_size()

	# Whole-block early-outs: a block entirely outside the rock body, or entirely
	# inside the hollow, is uniform air. The buffer defaults to AIR, so returning
	# without writing leaves it correct and skips the per-voxel loop - which is most
	# of the cost at this voxel size.
	var block_min := Vector3(origin_in_voxels)
	var block_max := Vector3(origin_in_voxels + size)
	var nearest := Vector3(
		clampf(0.0, block_min.x, block_max.x),
		clampf(0.0, block_min.y, block_max.y),
		clampf(0.0, block_min.z, block_max.z)
	)
	var farthest := Vector3(
		maxf(absf(block_min.x), absf(block_max.x)),
		maxf(absf(block_min.y), absf(block_max.y)),
		maxf(absf(block_min.z), absf(block_max.z))
	)
	if nearest.length() > rock_body_radius_voxels:
		return
	if farthest.length() < chamber_radius_voxels:
		return

	for z in range(size.z):
		for y in range(size.y):
			for x in range(size.x):
				var voxel_position := origin_in_voxels + Vector3i(x, y, z)
				var distance := Vector3(voxel_position).length()
				var voxel_type := AIR
				if distance <= rock_body_radius_voxels and distance >= chamber_radius_voxels:
					voxel_type = _mineral_at(voxel_position)
				out_buffer.set_voxel(voxel_type, x, y, z, CHANNEL)


func _mineral_at(voxel_position: Vector3i) -> int:
	var value := _noise.get_noise_3dv(Vector3(voxel_position))
	if value >= vein_threshold_b:
		return MINERAL_B
	if value >= vein_threshold_a:
		return MINERAL_A
	return ROCK


func _rebuild_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = world_seed
	_noise.frequency = vein_frequency
