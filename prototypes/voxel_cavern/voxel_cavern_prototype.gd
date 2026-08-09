extends Node3D

## Voxel cavern mining prototype: float inside a blocky rock body and carve mineral
## veins out of the walls with a mining laser.
##
## Pushes voxel_cavern_knobs.gd onto the terrain and player at startup; the few
## values with sliders come from voxel_cavern_settings.tres instead. See
## PrototypeSettings and prototypes/AGENTS.md.

const PLAYER_SCENE := preload("res://prototypes/navigation/zero_g_player.tscn")

## The live-tunable mining values and carve toggles. Assigned in the .tscn; see
## _ready for the fallback when it is missing.
@export var settings: VoxelCavernSettings

var _generator: VoxelCavernGenerator

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
	var player := _spawn_player()
	_mining_laser.bind(
		player.get_node("HeadCamera"), _terrain, settings, VoxelCavernKnobs.VOXEL_SIZE
	)
	_hud.bind(_mining_laser, settings)
	_tuning.bind(settings)
	_apply_settings()


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

	_generator = VoxelCavernGenerator.new()
	_generator.configure(
		VoxelCavernKnobs.ROCK_BODY_RADIUS / voxel_size,
		VoxelCavernKnobs.SPAWN_CHAMBER_RADIUS / voxel_size,
		VoxelCavernKnobs.VEIN_NOISE_FREQUENCY,
		VoxelCavernKnobs.VEIN_THRESHOLD_A,
		VoxelCavernKnobs.VEIN_THRESHOLD_B,
		VoxelCavernKnobs.WORLD_SEED
	)
	_terrain.generator = _generator


func _spawn_player() -> ZeroGPlayer:
	var player: ZeroGPlayer = PLAYER_SCENE.instantiate()
	# Positioned before add_child: the player's _ready snapshots its respawn pose,
	# so it must be at the chamber centre before that runs (the same ordering trap
	# tunnel_system documents).
	player.position = Vector3.ZERO
	add_child(player)

	var viewer := VoxelViewer.new()
	viewer.view_distance = int(round(VoxelCavernKnobs.VIEW_DISTANCE / VoxelCavernKnobs.VOXEL_SIZE))
	(player.get_node("HeadCamera") as Camera3D).add_child(viewer)
	return player
