extends Node3D

## Voxel cavern mining + chase prototype.
##
## Float through a blocky, three-room voxel cavern, carve mineral veins out of the
## walls with a mining laser, and get hunted by the tentacle crawler. The two wide
## tunnels are big enough for the alien to chase you down; the narrow tunnel is your
## escape - you fit, it does not.
##
## The alien, its chase AI and its wall navmesh are reused wholesale from
## prototypes/tentacle_crawler_chaser (the creature senses the world only by
## raycasts on the hull layer, so it drops onto the voxel terrain unchanged). This
## script builds the world, spawns both, bakes the navmesh over the voxel collider
## once it exists, and then lets the existing chase stack run itself.
##
## Pushes voxel_cavern_knobs.gd onto the scene at startup; the few values with
## sliders come from voxel_cavern_settings.tres instead. See prototypes/AGENTS.md.

## Frames to wait for the streamed voxel collider before baking the navmesh anyway.
const TERRAIN_WAIT_FRAMES := 600

const PLAYER_SCENE := preload("res://prototypes/navigation/zero_g_player.tscn")
const CRAWLER_SCENE := preload("res://prototypes/tentacle_crawler/actors/crawler/crawler.tscn")

## The live-tunable mining values and carve toggles. Assigned in the .tscn; see
## _ready for the fallback when it is missing.
@export var settings: VoxelCavernSettings

var _generator: VoxelCavernGenerator
var _player: ZeroGPlayer
var _crawler: CrawlerBody
var _target: ChaseTarget
var _follower: ChaseTargetFollower
var _navigation: WallNavmeshBaker
var _contact: CreatureContact

@onready var _terrain: VoxelTerrain = $VoxelTerrain
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _mining_laser: MiningLaser = $MiningLaser
@onready var _hud: VoxelCavernHud = $HUD
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


func _ready() -> void:
	# A fresh clone has no voxel_cavern_settings.tres yet, and anyone may delete it.
	# A bare instance holds exactly the knobs consts, so the fallback runs the same
	# rather than crashing.
	if settings == null:
		settings = VoxelCavernSettings.new()
		push_warning(
			"No voxel_cavern_settings.tres wired; running on voxel_cavern_knobs.gd defaults."
		)
	settings.changed.connect(_apply_settings)

	_configure_terrain()
	_player = _spawn_player()
	_mining_laser.bind(
		_player.get_node("HeadCamera"), _terrain, settings, VoxelCavernKnobs.VOXEL_SIZE
	)
	_spawn_alien()
	_hud.bind(_mining_laser, settings)
	_hud.bind_chase(_player, _crawler, _follower, _contact)
	_tuning.bind(settings)
	_apply_settings()
	await _bake_navigation()


## Runs at startup and on every panel change. The mining laser reads its tunables
## at the point of use each frame, so nothing is pushed at it; this only owns the
## fog and the invariant warnings. Must not write back to settings.
func _apply_settings() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = VoxelCavernKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = VoxelCavernKnobs.FOG_DEPTH_END
	for failure: String in settings.invariant_failures():
		push_warning("voxel_cavern_settings: %s" % failure)


func _configure_terrain() -> void:
	var voxel_size := VoxelCavernKnobs.VOXEL_SIZE
	_terrain.scale = Vector3.ONE * voxel_size
	_terrain.collision_layer = 1
	_terrain.collision_mask = 0
	_terrain.generate_collisions = true

	var rooms := PackedVector3Array(
		[
			VoxelCavernKnobs.ROOM_A / voxel_size,
			VoxelCavernKnobs.ROOM_B / voxel_size,
			VoxelCavernKnobs.ROOM_C / voxel_size,
		]
	)
	# Two wide tunnels the long way (A->B->C), one narrow shortcut (A->C).
	var starts := PackedVector3Array(
		[
			VoxelCavernKnobs.ROOM_A / voxel_size,
			VoxelCavernKnobs.ROOM_B / voxel_size,
			VoxelCavernKnobs.ROOM_A / voxel_size,
		]
	)
	var ends := PackedVector3Array(
		[
			VoxelCavernKnobs.ROOM_B / voxel_size,
			VoxelCavernKnobs.ROOM_C / voxel_size,
			VoxelCavernKnobs.ROOM_C / voxel_size,
		]
	)
	var radii := PackedFloat32Array(
		[
			VoxelCavernKnobs.WIDE_TUNNEL_RADIUS / voxel_size,
			VoxelCavernKnobs.WIDE_TUNNEL_RADIUS / voxel_size,
			VoxelCavernKnobs.NARROW_TUNNEL_RADIUS / voxel_size,
		]
	)
	var vein_params := Vector3(
		VoxelCavernKnobs.VEIN_NOISE_FREQUENCY,
		VoxelCavernKnobs.VEIN_THRESHOLD_A,
		VoxelCavernKnobs.VEIN_THRESHOLD_B
	)

	_generator = VoxelCavernGenerator.new()
	_generator.configure(
		_map_center() / voxel_size,
		VoxelCavernKnobs.MAP_RADIUS / voxel_size,
		rooms,
		VoxelCavernKnobs.ROOM_RADIUS / voxel_size,
		starts,
		ends,
		radii,
		vein_params,
		VoxelCavernKnobs.WORLD_SEED
	)
	_terrain.generator = _generator

	# One fixed viewer at the map centre, ranged to cover the whole cavern, so the
	# collider exists everywhere at once - which the navmesh bake needs, and the map
	# is small enough to hold loaded.
	var viewer := VoxelViewer.new()
	viewer.view_distance = int(ceil(VoxelCavernKnobs.VIEW_DISTANCE / voxel_size))
	add_child(viewer)
	viewer.global_position = _map_center()


func _spawn_player() -> ZeroGPlayer:
	var player: ZeroGPlayer = PLAYER_SCENE.instantiate()
	# Positioned before add_child: the player's _ready snapshots its respawn pose,
	# so it must be at the spawn room before that runs.
	player.position = VoxelCavernKnobs.PLAYER_SPAWN
	add_child(player)
	return player


## Instances the crawler, drops it in the far room, and wires up the reused chase
## stack: ChaseTarget projects the player onto the wall navmesh, ChaseTargetFollower
## walks it, and the crawler leashes to the follower - exactly as in the chaser
## prototype, only over voxel terrain.
func _spawn_alien() -> void:
	var crawler: CrawlerBody = CRAWLER_SCENE.instantiate()
	_crawler = crawler
	crawler.position = VoxelCavernKnobs.CREATURE_SPAWN
	crawler.max_speed = VoxelCavernKnobs.CREATURE_MAX_SPEED
	crawler.leash_slack = VoxelCavernKnobs.CREATURE_LEASH_SLACK
	crawler.probe_comfort = VoxelCavernKnobs.CREATURE_PROBE_COMFORT
	# Hull only: layer 2 is the player, and left in the mask the creature would
	# read the player as a wall to avoid and its tentacles would grab at them.
	crawler.probe_mask = 1
	add_child(crawler)
	(crawler.get_node("Tentacles") as TentacleArray).query_mask = 1

	var creature_light := OmniLight3D.new()
	creature_light.light_color = VoxelCavernKnobs.CREATURE_LIGHT_COLOR
	creature_light.light_energy = VoxelCavernKnobs.CREATURE_LIGHT_ENERGY
	creature_light.omni_range = VoxelCavernKnobs.CREATURE_LIGHT_RANGE
	creature_light.shadow_enabled = false
	_crawler.add_child(creature_light)

	_contact = CreatureContact.new()
	_crawler.add_child(_contact)
	_contact.caught.connect(_on_caught)

	_target = ChaseTarget.new()
	_target.quarry = _player
	add_child(_target)

	_follower = ChaseTargetFollower.new()
	_follower.add_child(NavigationAgent3D.new())
	_follower.chase_target = _target
	_follower.move_speed = VoxelCavernKnobs.FOLLOWER_SPEED
	_follower.enabled = false
	add_child(_follower)
	_follower.teleport(VoxelCavernKnobs.CREATURE_SPAWN)

	_crawler.target_marker = _follower

	_navigation = WallNavmeshBaker.new()
	_navigation.openness_radius = VoxelCavernKnobs.NAVMESH_OPENNESS_RADIUS
	add_child(_navigation)


## Bake late, enable the follower later still - the same ordering the chaser
## prototype documents, adapted for voxel streaming: the terrain's collider only
## exists after the viewer has streamed and meshed the map, so wait for it rather
## than for a fixed two frames.
func _bake_navigation() -> void:
	await get_tree().physics_frame
	await _wait_for_terrain()
	await _navigation.bake_network(VoxelCavernKnobs.PLAYER_SPAWN, _map_bounds())
	_follower.enabled = true


## Polls a witness raycast in each room until the streamed collider answers, so the
## bake probes real geometry rather than an empty world.
func _wait_for_terrain() -> void:
	for _attempt: int in TERRAIN_WAIT_FRAMES:
		if (
			_room_ceiling_solid(VoxelCavernKnobs.ROOM_A)
			and _room_ceiling_solid(VoxelCavernKnobs.ROOM_C)
		):
			return
		await get_tree().physics_frame
	push_warning("voxel_cavern: terrain collider not ready after waiting; baking anyway.")


func _room_ceiling_solid(room_center: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var to := room_center + Vector3.UP * (VoxelCavernKnobs.ROOM_RADIUS + 3.0)
	var query := PhysicsRayQueryParameters3D.create(room_center, to, 1)
	return not space.intersect_ray(query).is_empty()


func _on_caught(_body: Node3D) -> void:
	_hud.flash_caught()
	await get_tree().create_timer(VoxelCavernKnobs.CATCH_RESPAWN_DELAY).timeout
	_player.respawn()
	_crawler.teleport(VoxelCavernKnobs.CREATURE_SPAWN)
	_follower.teleport(VoxelCavernKnobs.CREATURE_SPAWN)
	_contact.armed = true


func _map_center() -> Vector3:
	return (VoxelCavernKnobs.ROOM_A + VoxelCavernKnobs.ROOM_B + VoxelCavernKnobs.ROOM_C) / 3.0


## An AABB fencing the navmesh flood to the rooms plus a margin, so a hole in the
## rock cannot leak the fill into the void.
func _map_bounds() -> AABB:
	var lowest := VoxelCavernKnobs.ROOM_A
	var highest := VoxelCavernKnobs.ROOM_A
	for room: Vector3 in [VoxelCavernKnobs.ROOM_B, VoxelCavernKnobs.ROOM_C]:
		lowest = lowest.min(room)
		highest = highest.max(room)
	var margin := Vector3.ONE * (VoxelCavernKnobs.ROOM_RADIUS + 4.0)
	return AABB(lowest - margin, (highest - lowest) + margin * 2.0)
