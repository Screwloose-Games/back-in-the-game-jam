class_name VoxelCavernSettings
extends PrototypeSettings

## The voxel cavern prototype's live-tunable mining-laser feel and the two carve
## toggles, saved between runs.
##
## Defaults and slider bounds both come from voxel_cavern_knobs.gd, so this file
## adds no numbers of its own - see PrototypeSettings for why that matters. The two
## bools carry no @export_range because a bool needs none: PrototypeTuningPanel
## renders every exported bool as a CheckButton, which is exactly the two required
## toggles (mining_deform_minerals, mining_deform_terrain).

const SAVE_PATH := "res://prototypes/voxel_cavern/voxel_cavern_settings.tres"

## Diameter, in metres, of the sphere removed on each deformation. The carve radius
## is half this. Typed float explicitly so the slider steps in fractions.
@export_range(
	VoxelCavernKnobs.MINING_BEAM_DEFORMATION_DIAMETER_MIN,
	VoxelCavernKnobs.MINING_BEAM_DEFORMATION_DIAMETER_MAX,
	0.02,
	"suffix:m"
)
var mining_beam_deformation_diameter: float = VoxelCavernKnobs.MINING_BEAM_DEFORMATION_DIAMETER

## How many times per second the beam deforms while held on a surface.
@export_range(
	VoxelCavernKnobs.MINING_DEFORMATIONS_PER_SECOND_MIN,
	VoxelCavernKnobs.MINING_DEFORMATIONS_PER_SECOND_MAX,
	0.5,
	"suffix:/s"
)
var deformations_per_second: float = VoxelCavernKnobs.MINING_DEFORMATIONS_PER_SECOND

## How far the beam reaches, in metres.
@export_range(
	VoxelCavernKnobs.MINING_BEAM_RANGE_MIN, VoxelCavernKnobs.MINING_BEAM_RANGE_MAX, 0.5, "suffix:m"
)
var mining_beam_range: float = VoxelCavernKnobs.MINING_BEAM_RANGE

## Whether the beam removes mineral voxels.
@export var mining_deform_minerals: bool = VoxelCavernKnobs.MINING_DEFORM_MINERALS

## Whether the beam removes plain rock voxels.
@export var mining_deform_terrain: bool = VoxelCavernKnobs.MINING_DEFORM_TERRAIN


func settings_path() -> String:
	return SAVE_PATH
