class_name MiningLaserBeam
extends Node3D

## Draws the mining laser's beam from its muzzle to wherever the cut landed, and
## throws light of the same colour on what it lands on. It owns no raycast of its
## own: PlayerMiningTool already casts along the aim, and a second cast from the
## muzzle would stop the beam short of what you are actually pointing at.

@export var settings: PlayerSettings

@onready var muzzle: Node3D = $sm_mining_laser/muzzle_point
@onready var beam: Node3D = $Beam
@onready var beam_mesh: MeshInstance3D = $Beam/BeamMesh
@onready var impact_light: OmniLight3D = $Beam/ImpactLight


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("MiningLaserBeam has no settings; running on PlayerSettings defaults.")
	_apply_settings()
	hold_fire()


## Shows the beam running from the muzzle to a world position.
func fire_at(point: Vector3) -> void:
	var origin := muzzle.global_position
	var reach := point - origin
	var length := reach.length()
	if length < 0.001:
		hold_fire()
		return
	beam.visible = true
	beam_mesh.global_transform = _span(origin, reach / length, length)
	impact_light.global_position = point


func hold_fire() -> void:
	beam.visible = false


## The cylinder runs along its own +Y, so the basis puts that axis down the beam
## at full length and the beam's radius on the other two.
func _span(origin: Vector3, direction: Vector3, length: float) -> Transform3D:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var side := up.cross(direction).normalized()
	var radius := settings.mining_beam_radius
	var span := Basis(side * radius, direction * length, side.cross(direction) * radius)
	return Transform3D(span, origin + direction * length * 0.5)


func _apply_settings() -> void:
	var material := beam_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = settings.mining_beam_color
	impact_light.light_color = settings.mining_beam_color
	impact_light.light_energy = settings.mining_light_energy
	impact_light.omni_range = settings.mining_light_range
