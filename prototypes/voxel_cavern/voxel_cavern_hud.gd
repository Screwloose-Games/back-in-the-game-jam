class_name VoxelCavernHud
extends CanvasLayer

## Debug readout for the voxel cavern prototype: controls, beam state, the two carve
## toggles, and the chase - how far the alien is, whether it is hunting yet, and a
## flash when it catches you.

var _laser: MiningLaser
var _settings: VoxelCavernSettings
var _player: Node3D
var _crawler: Node3D
var _follower: ChaseTargetFollower
var _contact: CreatureContact
var _caught_flash := 0.0

@onready var _readout: Label = $Readout


func bind(laser: MiningLaser, settings: VoxelCavernSettings) -> void:
	_laser = laser
	_settings = settings


func bind_chase(
	player: Node3D, crawler: Node3D, follower: ChaseTargetFollower, contact: CreatureContact
) -> void:
	_player = player
	_crawler = crawler
	_follower = follower
	_contact = contact


## Called by the root when the alien catches the player, so the HUD flashes long
## enough to read before the reset.
func flash_caught() -> void:
	_caught_flash = VoxelCavernKnobs.CATCH_RESPAWN_DELAY


func _process(delta: float) -> void:
	if _laser == null or _settings == null:
		return
	_caught_flash = maxf(0.0, _caught_flash - delta)

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
	lines.append("")
	lines.append(_chase_line())
	lines.append(
		(
			"voxel size: %.2f m   fps: %d"
			% [VoxelCavernKnobs.VOXEL_SIZE, Engine.get_frames_per_second()]
		)
	)
	if _caught_flash > 0.0:
		lines.append("")
		lines.append("*** CAUGHT - the alien reached you ***")
	_readout.text = "\n".join(lines)


## One line describing the hunt: baking, or hunting with the live distance.
func _chase_line() -> String:
	if _follower == null or _crawler == null or _player == null:
		return "alien: -"
	if not _follower.enabled:
		return "alien: navmesh baking..."
	var distance := _crawler.global_position.distance_to(_player.global_position)
	var catches := _contact.catch_count() if _contact != null else 0
	return "alien: HUNTING   %.1f m away   caught you %d time(s)" % [distance, catches]
