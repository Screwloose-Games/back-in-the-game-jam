class_name VoxelCavernKnobs
extends RefCounted

## Every tunable value for the voxel cavern mining prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the terrain at startup, so they win
## over whatever is saved in the .tscn. The handful the tuning panel puts a slider
## on are overridden by voxel_cavern_settings.tres, which declares its defaults AS
## these consts - so no number is written down twice.

#region World scale

## Metres per voxel, applied as the VoxelTerrain node's scale.
##
## THIS IS THE SCALE LEVER, and it is a compromise. The mining wants a fine grid;
## the chasing alien (~4.3 m across, needs passages wider than ~6.4 m) forces a map
## tens of metres across, and generation cost scales with roughly 1 / VOXEL_SIZE^3.
## 0.4 m keeps the whole map generatable at once (needed so the navmesh can bake
## over the collided terrain) while still reading as blocky. Raise it (0.5-0.6) if
## the GL Compatibility / web build is slow to generate the map; lower it for finer
## mining at the cost of a heavier startup.
const VOXEL_SIZE := 0.4

## Radius of the solid rock body, in metres. Everything is carved out of this; past
## it is open space. Kept just big enough to enclose the three rooms plus a margin
## of rock, because every extra metre of radius is voxels generated at startup.
const MAP_RADIUS := 27.0

## Fixed so the same veins come back every run. Change it to roll a new field.
const WORLD_SEED := 20260809

#endregion

#region Rooms and tunnels
#
# A three-room loop carved out of the rock. Two wide tunnels (which the alien can
# fit through) join the rooms the long way A -> B -> C; one narrow tunnel is a
# direct A -> C shortcut the alien is too big to enter. All in metres, world space.

## Radius of each of the three rooms, in metres.
const ROOM_RADIUS := 6.0

## Player spawn room.
const ROOM_A := Vector3(0.0, 0.0, 0.0)
## Mid room, the corner of the long path.
const ROOM_B := Vector3(22.0, 0.0, 0.0)
## Alien spawn room, on the far side of the map.
const ROOM_C := Vector3(22.0, 0.0, -22.0)

## Radius of the two wide tunnels, in metres. Their 9 m bore is above the alien's
## ~6.4 m minimum passage width, so it can hunt down them.
const WIDE_TUNNEL_RADIUS := 4.5

## Radius of the shortcut tunnel, in metres. Its 2 m bore is far under the alien's
## body (2.15 m radius) - it physically cannot enter, but the 0.4 m player slips
## through. This is the escape.
const NARROW_TUNNEL_RADIUS := 1.0

## Where the player starts (centre of room A).
const PLAYER_SPAWN := ROOM_A
## Where the alien starts (centre of room C, the far side).
const CREATURE_SPAWN := ROOM_C

#endregion

#region Mineral veins

## Spatial frequency of the vein noise, in 1 / voxels. Higher packs the veins
## tighter; lower spreads them into fewer, fatter seams.
const VEIN_NOISE_FREQUENCY := 0.12

## Noise value above which rock becomes the first (outer) mineral. Lower is more
## ore.
const VEIN_THRESHOLD_A := 0.32

## Noise value above which mineral becomes the second (richer, core) mineral.
const VEIN_THRESHOLD_B := 0.55

#endregion

#region Optics

## Metres at which fog starts to thicken. Below this you see clearly.
const FOG_DEPTH_BEGIN := 4.0

## Metres at which geometry is fully swallowed by fog. Far enough to see the alien
## emerge from a tunnel mouth, close enough to keep the rooms tense.
const FOG_DEPTH_END := 20.0

## How far, in metres, the fixed viewer streams terrain. Covers the whole map from
## its centre so the collider exists everywhere for the navmesh bake.
const VIEW_DISTANCE := 34.0

#endregion

#region Mining laser

## Diameter, in metres, of the sphere the beam removes on each deformation. The
## carve radius is half this. Sized for the coarser 0.4 m grid: a 1.6 m bite is
## about two voxels of radius. (Named for the diameter on purpose; the sphere it
## drives uses DIAMETER / 2 as its radius.)
const MINING_BEAM_DEFORMATION_DIAMETER := 1.6
const MINING_BEAM_DEFORMATION_DIAMETER_MIN := 0.4
const MINING_BEAM_DEFORMATION_DIAMETER_MAX := 6.0

## How many times per second the beam deforms terrain while held on a surface.
const MINING_DEFORMATIONS_PER_SECOND := 2.0
const MINING_DEFORMATIONS_PER_SECOND_MIN := 0.5
const MINING_DEFORMATIONS_PER_SECOND_MAX := 10.0

## How far the beam reaches, in metres. Long enough to cross a room.
const MINING_BEAM_RANGE := 14.0
const MINING_BEAM_RANGE_MIN := 2.0
const MINING_BEAM_RANGE_MAX := 40.0

## Whether the beam removes mineral voxels. Toggled live from the panel.
const MINING_DEFORM_MINERALS := true

## Whether the beam removes plain rock voxels. Toggled live from the panel.
const MINING_DEFORM_TERRAIN := true

## Visual thickness of the beam cylinder, in metres.
const MINING_BEAM_THICKNESS := 0.05

## Where the beam emerges relative to the head camera: right, down and slightly
## forward, so it reads as fired from the right hip rather than from the eyes. The
## beam still converges on the crosshair, only its origin is offset.
const MINING_BEAM_MUZZLE_OFFSET := Vector3(0.3, -0.28, -0.2)

#endregion

#region Alien
#
# The chaser reuses prototypes/tentacle_crawler_chaser wholesale. These are the few
# values pushed onto it here; everything else keeps that prototype's own defaults
# (see ChaseKnobs). The creature is generator-agnostic - it senses the world only
# by raycasts on the hull layer - so it drops into the voxel cavern unchanged.

## Top speed of the creature, m/s.
const CREATURE_MAX_SPEED := 8.0

## How far the creature may trail its follower before the leash hauls, m. Small so
## it actually reaches you rather than hovering a standoff away.
const CREATURE_LEASH_SLACK := 1.2

## How far off the nearest wall the creature holds, m. Half of this times two is the
## narrowest tunnel it can use, which is why the wide tunnels are 9 m and the
## shortcut (2 m) shuts it out.
const CREATURE_PROBE_COMFORT := 3.2

## Speed the navmesh follower flies the path at, m/s (the ceiling on the chase).
const FOLLOWER_SPEED := 7.0

## Violet so the creature is never confused with the helmet lamp or the veins.
const CREATURE_LIGHT_COLOR := Color(0.72, 0.42, 0.95)
const CREATURE_LIGHT_ENERGY := 2.0
const CREATURE_LIGHT_RANGE := 16.0

## Radius of the openness sphere the navmesh flood uses, in metres. Set ABOVE the
## narrow tunnel radius (1.0) and below the wide tunnels (4.5), so the shortcut is
## excluded from the alien's navmesh entirely - it can neither fit nor path it.
const NAVMESH_OPENNESS_RADIUS := 1.15

## Seconds held on the "CAUGHT" flash before the player and alien are reset.
const CATCH_RESPAWN_DELAY := 1.2

#endregion
