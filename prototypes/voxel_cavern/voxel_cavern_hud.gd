class_name VoxelCavernHud
extends CanvasLayer

## Debug readout for the voxel cavern prototype: controls, beam state and the two
## carve toggles, so a playtester can see at a glance what the laser will and will
## not eat.

var _laser: MiningLaser
var _settings: VoxelCavernSettings

@onready var _readout: Label = $Readout


func bind(laser: MiningLaser, settings: VoxelCavernSettings) -> void:
	_laser = laser
	_settings = settings


func _process(_delta: float) -> void:
	if _laser == null or _settings == null:
		return

	var minerals_state := "on" if _settings.mining_deform_minerals else "off"
	var terrain_state := "on" if _settings.mining_deform_terrain else "off"

	var lines := PackedStringArray()
	lines.append("VOXEL CAVERN MINING")
	lines.append("WASD / Space / Ctrl thrust   mouse look   Q/E roll   Shift sprint")
	lines.append("Hold LEFT MOUSE to fire the laser   Esc frees the cursor for the panel")
	lines.append("")
	lines.append(
		(
			"firing: %s   beam on: %s"
			% ["yes" if _laser.is_firing() else "no", _laser.hit_material_label()]
		)
	)
	lines.append("deform minerals: %s   deform terrain: %s" % [minerals_state, terrain_state])
	lines.append(
		(
			"carve diameter: %.2f m   rate: %.1f/s"
			% [_settings.mining_beam_deformation_diameter, _settings.deformations_per_second]
		)
	)
	lines.append(
		(
			"voxel size: %.2f m   fps: %d"
			% [VoxelCavernKnobs.VOXEL_SIZE, Engine.get_frames_per_second()]
		)
	)
	_readout.text = "\n".join(lines)
