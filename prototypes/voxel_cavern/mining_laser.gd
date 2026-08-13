class_name MiningLaser
extends Node3D

## Camera-forward mining beam that carves spheres out of the voxel terrain.
##
## Hold the `mine` action to fire while the cursor is captured. While the beam is
## held on a surface it deforms the terrain at a fixed cadence
## (deformations_per_second): each deformation removes a sphere of voxels of radius
## mining_beam_deformation_diameter / 2, honouring the two toggles - a voxel is
## only cleared when its material class (mineral or plain rock) is enabled.
##
## The sphere is walked cell by cell rather than handed to VoxelTool.do_sphere on
## purpose: do_sphere cannot look at the existing voxel, and looking at it is the
## whole point of letting the beam eat one class and leave the other.

const AIR := 0
const ROCK := 1
const MINERAL_A := 2
const TERRAIN_COLLISION_MASK := 1

var _settings: VoxelCavernSettings
var _camera: Camera3D
var _terrain: VoxelTerrain
var _voxel_size := 0.06
var _deform_accumulator := 0.0
var _is_firing := false
var _was_hitting := false
var _hit_type := AIR

var _beam: MeshInstance3D
var _impact_light: OmniLight3D


## Points the laser at the player's camera and the terrain, and builds its beam
## visuals. Called by the prototype root once the player exists.
func bind(
	camera: Camera3D, terrain: VoxelTerrain, settings: VoxelCavernSettings, voxel_size: float
) -> void:
	_camera = camera
	_terrain = terrain
	_settings = settings
	_voxel_size = voxel_size
	_build_visuals()


## True while the fire button is held (and the cursor is captured). Read by the HUD.
func is_firing() -> bool:
	return _is_firing


## What the beam is currently resting on, for the HUD: "mineral", "rock" or "-".
func hit_material_label() -> String:
	if not _is_firing or _hit_type == AIR:
		return "-"
	if _hit_type >= MINERAL_A:
		return "mineral"
	return "rock"


func _process(delta: float) -> void:
	if _camera == null or _terrain == null:
		return

	# Only fire while the cursor is captured, so clicking a tuning slider does not
	# also punch a hole in the wall behind the panel.
	_is_firing = (Input.is_action_pressed("mine") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	if not _is_firing:
		_stop_beam()
		return

	var hit := _raycast()
	_update_beam(hit)
	if hit.is_empty():
		_was_hitting = false
		_deform_accumulator = 0.0
		_impact_light.visible = false
		_hit_type = AIR
		return

	var world_hit: Vector3 = hit["position"]
	var world_normal: Vector3 = hit["normal"]
	_impact_light.visible = true
	_impact_light.global_position = world_hit
	_hit_type = _material_at_surface(world_hit, world_normal)

	if not _was_hitting:
		# Rising edge: carve at once so first contact feels responsive, then settle
		# into the steady cadence below.
		_was_hitting = true
		_deform_accumulator = 0.0
		_carve(world_hit)
		return

	_deform_accumulator += delta
	var interval := 1.0 / maxf(_settings.deformations_per_second, 0.01)
	if _deform_accumulator >= interval:
		_carve(world_hit)
		_deform_accumulator -= interval


func _stop_beam() -> void:
	_was_hitting = false
	_deform_accumulator = 0.0
	_hit_type = AIR
	if _beam != null:
		_beam.visible = false
	if _impact_light != null:
		_impact_light.visible = false


func _raycast() -> Dictionary:
	var space_state := _camera.get_world_3d().direct_space_state
	var from := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	var to := from + forward * _settings.mining_beam_range
	var query := PhysicsRayQueryParameters3D.create(from, to, TERRAIN_COLLISION_MASK)
	return space_state.intersect_ray(query)


func _carve(world_hit: Vector3) -> void:
	var voxel_tool := _terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE

	# to_local folds in the terrain's VOXEL_SIZE scale, so the result is already in
	# voxel-grid coordinates.
	var center := Vector3i(_terrain.to_local(world_hit).round())
	var radius_voxels := (_settings.mining_beam_deformation_diameter * 0.5) / _voxel_size
	var radius_ceil := int(ceil(radius_voxels))
	var radius_squared := radius_voxels * radius_voxels

	for z in range(-radius_ceil, radius_ceil + 1):
		for y in range(-radius_ceil, radius_ceil + 1):
			for x in range(-radius_ceil, radius_ceil + 1):
				if float(x * x + y * y + z * z) > radius_squared:
					continue
				var position := center + Vector3i(x, y, z)
				var voxel_type := voxel_tool.get_voxel(position)
				if voxel_type == AIR:
					continue
				var is_mineral := voxel_type >= MINERAL_A
				if is_mineral and _settings.mining_deform_minerals:
					voxel_tool.set_voxel(position, AIR)
				elif not is_mineral and _settings.mining_deform_terrain:
					voxel_tool.set_voxel(position, AIR)


## Peeks a few voxels below the impact point to name what the beam rests on. The
## physics hit sits on the surface, which is usually air, so step inward along the
## surface normal until a solid voxel is found.
func _material_at_surface(world_hit: Vector3, world_normal: Vector3) -> int:
	var voxel_tool := _terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var normal_local := (_terrain.global_transform.basis.inverse() * world_normal).normalized()
	var base := _terrain.to_local(world_hit)
	for step in range(1, 4):
		var probe := Vector3i((base - normal_local * float(step)).round())
		var voxel_type := voxel_tool.get_voxel(probe)
		if voxel_type != AIR:
			return voxel_type
	return AIR


func _update_beam(hit: Dictionary) -> void:
	# Fired from the right hip: the beam emerges at the muzzle offset (down and to
	# the right of the eyes) but still converges on the crosshair, so aiming stays
	# centre-screen while the beam reads as coming from a held tool.
	var from := _camera.global_transform * VoxelCavernKnobs.MINING_BEAM_MUZZLE_OFFSET
	var forward := -_camera.global_transform.basis.z
	var to: Vector3 = _camera.global_position + forward * _settings.mining_beam_range
	if not hit.is_empty():
		to = hit["position"]
	var length := from.distance_to(to)
	if length < 0.01:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_position = (from + to) * 0.5
	_beam.look_at(to, _camera.global_transform.basis.y)
	var thickness := VoxelCavernKnobs.MINING_BEAM_THICKNESS
	_beam.scale = Vector3(thickness, thickness, length)


func _build_visuals() -> void:
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.albedo_color = Color(1.0, 0.35, 0.2, 0.85)
	beam_material.emission_enabled = true
	beam_material.emission = Color(1.0, 0.4, 0.2)
	beam_material.emission_energy_multiplier = 6.0

	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3.ONE

	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.material_override = beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)

	_impact_light = OmniLight3D.new()
	_impact_light.light_color = Color(1.0, 0.55, 0.3)
	_impact_light.light_energy = 3.0
	_impact_light.omni_range = 2.0
	_impact_light.visible = false
	add_child(_impact_light)
