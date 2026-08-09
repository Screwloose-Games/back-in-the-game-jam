class_name VoxelCavernKnobs
extends RefCounted

## Every tunable value for the voxel cavern mining prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the terrain at startup, so they win
## over whatever is saved in the .tscn. The handful the tuning panel puts a slider
## on are overridden by voxel_cavern_settings.tres, which declares its defaults AS
## these consts - so no number is written down twice.

#region World shape

## Metres per voxel, applied as the VoxelTerrain node's scale.
##
## THIS IS THE PERFORMANCE LEVER. Generation and meshing cost scale with roughly
## 1 / VOXEL_SIZE^3, and the generator visits every voxel in GDScript, so the fine
## 0.06 m grid is deliberately paired with the small ROCK_BODY_RADIUS and short
## VIEW_DISTANCE below. If the GL Compatibility / web build cannot hold framerate,
## raise this first (0.12 - 0.25 m): it is a one-line change and the world, the
## chamber and the view distance are all derived from it.
const VOXEL_SIZE := 0.06

## Radius of the solid rock body, in metres. Beyond it is open space (air), so the
## player can eventually mine all the way through a wall and break out.
const ROCK_BODY_RADIUS := 5.0

## Radius of the hollow the player spawns inside, carved out of the rock centre.
const SPAWN_CHAMBER_RADIUS := 1.8

## Fixed so the same veins come back every run. Change it to roll a new field.
const WORLD_SEED := 20260809

#endregion

#region Mineral veins

## Spatial frequency of the vein noise, in 1 / voxels. Higher packs the veins
## tighter; lower spreads them into fewer, fatter seams.
const VEIN_NOISE_FREQUENCY := 0.09

## Noise value above which rock becomes the first (outer) mineral. Lower is more
## ore.
const VEIN_THRESHOLD_A := 0.32

## Noise value above which mineral becomes the second (richer, core) mineral.
const VEIN_THRESHOLD_B := 0.55

#endregion

#region Optics

## Metres at which fog starts to thicken. Below this you see clearly.
const FOG_DEPTH_BEGIN := 1.0

## Metres at which geometry is fully swallowed by fog. Kept near VIEW_DISTANCE so
## the streaming edge is hidden by murk rather than popping into view.
const FOG_DEPTH_END := 3.5

## How far, in metres, terrain streams around the player. Converted to voxels for
## the VoxelViewer. The other half of the performance budget - see VOXEL_SIZE.
const VIEW_DISTANCE := 4.0

#endregion

#region Mining laser

## Diameter, in metres, of the sphere the beam removes on each deformation. The
## carve radius is half this. Named for the diameter on purpose - the sphere it
## drives uses DIAMETER / 2 as its radius.
const MINING_BEAM_DEFORMATION_DIAMETER := 0.6
const MINING_BEAM_DEFORMATION_DIAMETER_MIN := 0.12
const MINING_BEAM_DEFORMATION_DIAMETER_MAX := 2.4

## How many times per second the beam deforms terrain while held on a surface.
const MINING_DEFORMATIONS_PER_SECOND := 2.0
const MINING_DEFORMATIONS_PER_SECOND_MIN := 0.5
const MINING_DEFORMATIONS_PER_SECOND_MAX := 10.0

## How far the beam reaches, in metres.
const MINING_BEAM_RANGE := 8.0
const MINING_BEAM_RANGE_MIN := 1.0
const MINING_BEAM_RANGE_MAX := 30.0

## Whether the beam removes mineral voxels. Toggled live from the panel.
const MINING_DEFORM_MINERALS := true

## Whether the beam removes plain rock voxels. Toggled live from the panel.
const MINING_DEFORM_TERRAIN := true

## Visual thickness of the beam cylinder, in metres.
const MINING_BEAM_THICKNESS := 0.04

#endregion
