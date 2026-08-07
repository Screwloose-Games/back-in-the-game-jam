@tool
class_name AsteroidVoxelGenerator
extends VoxelGeneratorScript

const AsteroidLayoutData = preload("res://asteroid/generation/asteroid_layout.gd")

const AIR: int = 0
const ROCK: int = 1
const BLUE_ORE: int = 2
const PURPLE_ORE: int = 3
const YELLOW_ORE: int = 4
const CHANNEL: int = VoxelBuffer.CHANNEL_TYPE

@export var asteroid_radius: float = 16.0
@export var surface_distortion: float = 2.5


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func is_inside_asteroid(position: Vector3) -> bool:
	var distance := position.length()

	var distortion := (
		(sin(position.x * 0.31) + sin(position.y * 0.27) + sin(position.z * 0.35))
		* surface_distortion
	)

	return distance <= asteroid_radius + distortion


func is_inside_landing_crater(position: Vector3) -> bool:
	return (
		position.distance_to(AsteroidLayoutData.LANDING_CENTER) < AsteroidLayoutData.LANDING_RADIUS
	)


func is_inside_entrance_tunnel(position: Vector3) -> bool:
	return (
		distance_to_line_segment(
			position, AsteroidLayoutData.ENTRANCE_START, AsteroidLayoutData.ENTRANCE_END
		)
		< AsteroidLayoutData.ENTRANCE_RADIUS
	)


func is_inside_blue_chamber(position: Vector3) -> bool:
	return (
		position.distance_to(AsteroidLayoutData.BLUE_ROOM_CENTER)
		< AsteroidLayoutData.BLUE_ROOM_RADIUS
	)


func is_inside_purple_tunnel(position: Vector3) -> bool:
	return (
		distance_to_line_segment(
			position, AsteroidLayoutData.PURPLE_TUNNEL_START, AsteroidLayoutData.PURPLE_TUNNEL_END
		)
		< AsteroidLayoutData.PURPLE_TUNNEL_RADIUS
	)


func is_inside_purple_chamber(position: Vector3) -> bool:
	return (
		position.distance_to(AsteroidLayoutData.PURPLE_ROOM_CENTER)
		< AsteroidLayoutData.PURPLE_ROOM_RADIUS
	)


func is_inside_core_tunnel(position: Vector3) -> bool:
	return (
		distance_to_line_segment(
			position, AsteroidLayoutData.CORE_TUNNEL_START, AsteroidLayoutData.CORE_TUNNEL_END
		)
		< AsteroidLayoutData.CORE_TUNNEL_RADIUS
	)


func is_inside_core_chamber(position: Vector3) -> bool:
	return (
		position.distance_to(AsteroidLayoutData.CORE_ROOM_CENTER)
		< AsteroidLayoutData.CORE_ROOM_RADIUS
	)


func get_ore_type(position: Vector3) -> int:
	if (
		is_near_segment(
			position,
			AsteroidLayoutData.YELLOW_FORMATION_START,
			AsteroidLayoutData.YELLOW_FORMATION_END,
			AsteroidLayoutData.YELLOW_FORMATION_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.YELLOW_DEPOSIT_CENTER,
			AsteroidLayoutData.YELLOW_BRANCH_LEFT,
			AsteroidLayoutData.YELLOW_FORMATION_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.YELLOW_DEPOSIT_CENTER,
			AsteroidLayoutData.YELLOW_BRANCH_RIGHT,
			AsteroidLayoutData.YELLOW_FORMATION_RADIUS
		)
	):
		return YELLOW_ORE

	if (
		is_near_segment(
			position,
			AsteroidLayoutData.PURPLE_VEIN_A_START,
			AsteroidLayoutData.PURPLE_VEIN_A_END,
			AsteroidLayoutData.PURPLE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.PURPLE_DEPOSIT_1_CENTER,
			AsteroidLayoutData.PURPLE_VEIN_A_BRANCH_END,
			AsteroidLayoutData.PURPLE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.PURPLE_VEIN_B_START,
			AsteroidLayoutData.PURPLE_VEIN_B_END,
			AsteroidLayoutData.PURPLE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.PURPLE_VEIN_C_START,
			AsteroidLayoutData.PURPLE_VEIN_C_END,
			AsteroidLayoutData.PURPLE_VEIN_RADIUS
		)
	):
		return PURPLE_ORE

	if (
		is_near_segment(
			position,
			AsteroidLayoutData.BLUE_VEIN_A_START,
			AsteroidLayoutData.BLUE_VEIN_A_END,
			AsteroidLayoutData.BLUE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.BLUE_DEPOSIT_1_CENTER,
			AsteroidLayoutData.BLUE_VEIN_A_BRANCH_END,
			AsteroidLayoutData.BLUE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.BLUE_VEIN_B_START,
			AsteroidLayoutData.BLUE_VEIN_B_END,
			AsteroidLayoutData.BLUE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.BLUE_DEPOSIT_2_CENTER,
			AsteroidLayoutData.BLUE_VEIN_B_BRANCH_END,
			AsteroidLayoutData.BLUE_VEIN_RADIUS
		)
		or is_near_segment(
			position,
			AsteroidLayoutData.BLUE_VEIN_C_START,
			AsteroidLayoutData.BLUE_VEIN_C_END,
			AsteroidLayoutData.BLUE_VEIN_RADIUS
		)
	):
		return BLUE_ORE

	return ROCK


func is_near_segment(position: Vector3, start: Vector3, end: Vector3, radius: float) -> bool:
	return distance_to_line_segment(position, start, end) < radius


func distance_to_line_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var segment_length_squared := segment.length_squared()

	if segment_length_squared <= 0.0001:
		return point.distance_to(start)

	var progress := clampf((point - start).dot(segment) / segment_length_squared, 0.0, 1.0)

	var closest_point := start + segment * progress

	return point.distance_to(closest_point)


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var buffer_size: Vector3i = out_buffer.get_size()

	for z in range(buffer_size.z):
		for y in range(buffer_size.y):
			for x in range(buffer_size.x):
				var voxel_position := origin_in_voxels + Vector3i(x, y, z)

				var world_position := Vector3(voxel_position)
				var voxel_type := AIR

				if is_inside_asteroid(world_position):
					var is_carved := (
						is_inside_landing_crater(world_position)
						or is_inside_entrance_tunnel(world_position)
						or is_inside_blue_chamber(world_position)
						or is_inside_purple_tunnel(world_position)
						or is_inside_purple_chamber(world_position)
						or is_inside_core_tunnel(world_position)
						or is_inside_core_chamber(world_position)
					)

					if not is_carved:
						voxel_type = get_ore_type(world_position)

				out_buffer.set_voxel(voxel_type, x, y, z, CHANNEL)
