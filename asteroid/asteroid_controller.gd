extends Node3D


const AsteroidGenerator = preload(
	"res://asteroid/generation/asteroid_voxel_generator.gd"
)

@onready var terrain: VoxelTerrain = $VoxelTerrain


func _ready() -> void:
	var generator = AsteroidGenerator.new()

	generator.asteroid_radius = 16.0
	generator.surface_distortion = 2.5

	terrain.generator = generator
