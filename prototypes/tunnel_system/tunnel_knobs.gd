class_name TunnelKnobs
extends RefCounted

## Every tunable value for the tunnel system prototype, in one place, plus the
## hand-authored layout itself.
##
## Change a number here and re-run the build + bake tools. Same contract as
## prototypes/navigation/prototype_knobs.gd: these values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win over
## whatever is saved in the .tscn files.
##
## THIS FILE IS STILL WHERE A DEFAULT LIVES. The few values the tuning panel puts
## a slider on are overridden by tunnel_settings.tres, which the SAVE button
## writes - but that resource declares its defaults AS these consts, so there is
## still exactly one place any number is written down, and RESET means "read this
## file again". The .tscn holds no copy of anything here either way.
##
## THE LAYOUT TABLE BELOW IS A SCAFFOLD, NOT THE SOURCE OF TRUTH. It seeds
## paths/tunnel_paths.tscn once, via tools/build_tunnel_paths.gd. After that the
## Path3D curves IN THAT SCENE are what the baker reads, so dragging a curve
## point in the editor and re-baking works. Re-running the builder is a
## deliberate "reset to the authored layout" and overwrites those edits.

#region World

## The prototype occupies a 200 m cube. X and Z run -100..100; Y runs -200..0,
## with 0 being the rock surface, so -Y reads directly as depth in metres and the
## HUD can print it without arithmetic.
const WORLD_EXTENT := 200.0

## How far inside each face a centreline must stay. Big enough that the widest
## bore plus its isosurface rounding cannot breach an outer face.
const WORLD_INSET := 10.0
#endregion

#region Bore
#
# The brief is 2 m to 3 m diameter for the branches. That is a PLAYER-ONLY size:
# the tentacle crawler measures 3.9 m across and chase_knobs.gd sets
# MIN_PASSAGE_WIDTH = 6.4, so it physically cannot follow you into one.
#
# The trunk routes are 8 m for exactly that reason. The mixed bore is the point
# of the layout, not an inconsistency in it - the trunks are where the thing can
# reach you, and the tight branches are where it cannot. A network at one uniform
# size answers a much less interesting question.

## Radius of a tight branch, metres. 2.0 m diameter - the brief's floor.
const BORE_TIGHT := 1.0

## Radius of a normal branch, metres. 3.0 m diameter - the brief's ceiling.
const BORE_BRANCH := 1.5

## Radius of a mid-size connector, metres. 6 m diameter: comfortably above the
## crawler's minimum passage, so it can use these but has to squeeze.
const BORE_CONNECTOR := 3.0

## Radius of a trunk route, metres. 8 m diameter, matching the corridor width the
## chase prototype was tuned in.
const BORE_TRUNK := 4.0

## The player's collision radius. Mirrors the SphereShape3D in
## prototypes/navigation/zero_g_player.tscn; the verifier asserts they still
## match rather than trusting this copy.
const PLAYER_RADIUS := 0.4

## Spare clearance the bore check demands on top of the player radius. The sphere
## swept along every centreline is PLAYER_RADIUS + this.
const CLEARANCE_MARGIN := 0.2

## Below this width a passage is impassable to the tentacle crawler. Copied from
## chase_knobs.gd (2.0 * CREATURE_PROBE_COMFORT). The verifier asserts the trunks
## clear it and reports which routes do not, so "the creature cannot follow you
## into the squeeze" is a measured claim rather than a comment.
const CREATURE_MIN_PASSAGE := 6.4

## Maximum |dr/ds| allowed along a route, as a validation. The field uses
## `distance_to_segment - lerp(radius)`, which is only a true distance function
## while the radius changes slowly; past roughly 0.5 the gradient magnitude drifts
## far enough from 1.0 that the surface-nets edge crossing lands in the wrong
## place and the bore comes out visibly the wrong size.
const BORE_MAX_SLOPE := 0.35
#endregion

#region Field and mesh

## Edge length of one SDF cell, metres. This is the single biggest lever on both
## look and cost: triangle count scales as 1/CELL_SIZE^2.
##
## At 0.45 a 2 m bore is ~4.4 cells across, which reads as rough natural rock
## rather than as a machined pipe - the right side of the line for this art
## direction. Below ~0.3 the bake stops being interactive; above ~0.6 the tight
## branches start reading as hex prisms and, worse, the sampling begins to pinch
## them narrower than their authored radius.
const CELL_SIZE := 0.45

## Metres between resampled centreline points. Each becomes one capsule segment.
## Short enough that a curve reads as a curve, long enough that the segment count
## stays in the low thousands.
const SEGMENT_STEP := 1.5

## Beyond this distance the field stops caring about exact values and returns a
## constant. Only the sign matters out there, and truncating lets the spatial
## hash bound how far a segment has to be inserted.
const FIELD_TRUNCATE := 3.0

## Edge length of a spatial hash cell, metres. Segments are inserted into every
## cell their AABB grown by (radius + FIELD_TRUNCATE) touches, so a field query
## is ONE dictionary lookup rather than a scan over all segments.
const HASH_CELL := 8.0

## Edge length of one baked mesh chunk, metres. Kept in the same order as
## CAMERA_FAR so the far plane does most of the culling.
##
## It does NOT track CAMERA_FAR exactly, and cannot: the assertion below requires
## a whole number of cells, and 30 / 0.45 is not one while 22.5 / 0.45 is 50.
## Chunks smaller than the far plane are harmless - a few more land in frustum,
## each still culling on its own. Chunks LARGER than it would be the problem.
##
## One mesh for the whole 200 m network would never be frustum-culled and would
## build a single enormous Jolt BVH; one mesh per route would give 16 nodes with
## overlapping 150 m AABBs, which culls no better. Asserted to be a whole
## multiple of CELL_SIZE, or chunk boundaries land mid-cell and open seams.
const CHUNK_SIZE := 22.5

## How many triangles the bake samples to decide whether its winding came out
## facing the air. See tunnel_sdf_baker.gd - this is the check that catches the
## invisible-to-raycasts trap at bake time rather than in the runtime suite.
const WINDING_SAMPLE_COUNT := 2000

## Fraction of sampled triangles that must agree with the field gradient after
## any auto-flip. Below this the mesh is locally inconsistent, which is a hole
## rather than a winding error, and the baker refuses to emit.
const WINDING_MIN_AGREEMENT := 0.98
#endregion

#region Draw distance
#
# Copied from prototype_knobs.gd so this prototype's murk matches the one the
# zero-G movement was actually tuned against. Changing these changes how the
# tunnels feel to fly, not just how they look.

const FOG_DEPTH_BEGIN := 2.0

## Metres at which geometry is fully swallowed by fog. This is the number that
## actually sets how far you can see.
##
## Opened from 12 to 22. The 7 m junction chambers were black voids at 12 - their
## far walls sat past the fog end - so the hubs read as nothing at all and the
## beacons were doing all the landmark work on their own.
const FOG_DEPTH_END := 22.0

const FOG_DENSITY := 1.0

## How far past the fog the lamp throws, and how far past that the camera clips.
##
## FOG_DEPTH_END IS THE ONLY ONE OF THE THREE ANYONE SHOULD SET. The other two
## are derived from it below, because moving any one of them alone changes
## nothing you can perceive: past the lamp's throw the rock is lit by
## AMBIENT_ENERGY alone and reads as black however clear the air is, and a clip
## plane inside the fog pops geometry out before the fog has hidden it. Deriving
## them makes both invariants structural instead of something a startup warning
## has to catch.
const VIEW_LAMP_MARGIN := 4.0
const VIEW_CLIP_MARGIN := 8.0

## How far the helmet lamp throws, in metres. Derived - see above.
const HELMET_LAMP_RANGE := FOG_DEPTH_END + VIEW_LAMP_MARGIN

## Hard clip distance. Derived - see above.
const CAMERA_FAR := FOG_DEPTH_END + VIEW_CLIP_MARGIN

## Width of the helmet lamp cone in degrees, as a half-angle - so 45 is a
## 90-degree cone. Widened from the 35 the navigation prototype's player ships
## with, which lit a narrow disc directly ahead and left the walls of anything
## wider than a branch outside the beam.
const HELMET_LAMP_ANGLE := 45.0

## Whether the helmet lamp casts shadows. ON, and the cost is a known artefact.
##
## Lengthening the throw to 26 m made the two widest chambers come back ringed
## with faint concentric shadow banding. Turning shadows off cures it completely,
## so it is the shadow map, not the material and not the mesh - but bias
## (0.08/2.5 and 0.14/4.0) and a 4096 atlas both moved it not at all, so the
## actual mechanism is NOT slope-scale acne and NOT atlas resolution, and no
## cheap lever was found. Left unfixed on purpose.
##
## Shadows stay on because the alternative is worse than banding: routes in this
## network pass within about 3 m of each other, and an unshadowed 26 m lamp lights
## the neighbouring tunnel THROUGH the rock. The rings sit at roughly 2% luminance
## in a chamber you can barely see anyway; lit rock where there is no opening
## reads as a broken level.
const HELMET_LAMP_SHADOWS := true

## Near-black. There is no sky down here and no directional light - the shell is
## sealed, so a DirectionalLight3D outside it is fully occluded and renders the
## whole interior at flat ambient, which looks exactly like a broken material.
const AMBIENT_ENERGY := 0.05
#endregion

#region Landmarks

## An emissive dot at every junction, hue keyed to the junction index.
##
## Not decoration. Sixteen routes of near-identical rock behind 12 m of fog with
## no up and no down means the player is lost inside two minutes, and that one
## finding drowns every other finding the prototype exists to produce.
## ld0-asteroid.md lists "landmarks that survive having no up or down" as a hard
## requirement for exactly this reason.
const JUNCTION_BEACONS := true

## Radius of a beacon sphere, metres.
const BEACON_SIZE := 0.4
#endregion

#region Physics layers
# Matching prototypes/navigation/corridor_generator.gd and project.godot's layer
# names: 1 = hull, 2 = player, 3 = debris, 4 = carryable.

const HULL_LAYER := 1
#endregion

#region Layout - junctions
#
# Named because their coordinates must match EXACTLY between the routes that meet
# there. Sharing one of these constants between two routes is how a branch or a
# loop gets declared - the same technique prototype_knobs.gd:202-235 uses.
#
# Connectivity is therefore true by construction rather than by luck, and the
# [graph] check in the verifier proves the scene still reflects it.

## The mouth, capped flush with the surface plane at Y = 0 by its own hemisphere.
const ENTRANCE := Vector3(0, -4, 0)

## Foot of the entrance shaft. Four ways out: back up, east, west, and a spur.
const HUB_ANTECHAMBER := Vector3(0, -30, 0)

## Four ways out. The upper loop rejoins here, so you can arrive from two
## directions and not be able to tell which without having tracked your own route.
const HUB_EAST := Vector3(60, -45, -20)

## Four ways out, and the only junction where a trunk meets the squeeze.
const HUB_WEST := Vector3(-55, -40, 25)

## Three ways out, 120 m down. Reachable by trunk the long way round or by the
## squeeze the short way - which is the whole decision the layout exists to pose.
const HUB_DEEP := Vector3(70, -120, -40)

## The terminus. Deepest point, biggest chamber, worst place to be caught.
const CORE_CHAMBER := Vector3(30, -170, 20)
#endregion

#region Layout - routes
#
# One entry becomes one Path3D. `points` is an open polyline; the builder fits
# Catmull-Rom bezier handles through it so the tunnel bows between waypoints
# instead of running in straight lines, while still passing exactly through every
# point - which is what keeps the shared junction coordinates exact.
#
# `bore_start` and `bore_end` are radii, lerped along arc length. A route that
# does not taper repeats the same value; that is deliberate, so no entry is
# ambiguous about whether it tapers.

const ROUTES := [
	{
		"name": "entrance_shaft",
		"bore_start": BORE_TRUNK,
		"bore_end": BORE_TRUNK,
		"points": [ENTRANCE, Vector3(4, -11, -3), Vector3(-3, -20, 2), HUB_ANTECHAMBER],
	},
	{
		"name": "east_trunk",
		"bore_start": BORE_TRUNK,
		"bore_end": BORE_TRUNK,
		"points": [HUB_ANTECHAMBER, Vector3(22, -34, -12), Vector3(43, -36, -22), HUB_EAST],
	},
	{
		"name": "west_trunk",
		"bore_start": BORE_TRUNK,
		"bore_end": BORE_CONNECTOR,
		"points": [HUB_ANTECHAMBER, Vector3(-20, -33, 10), Vector3(-40, -38, 20), HUB_WEST],
	},
	{
		"name": "deep_shaft",
		"bore_start": BORE_TRUNK,
		"bore_end": BORE_TRUNK,
		"points": [HUB_EAST, Vector3(68, -70, -28), Vector3(74, -98, -36), HUB_DEEP],
	},
	{
		"name": "core_descent",
		"bore_start": BORE_CONNECTOR,
		"bore_end": BORE_BRANCH,
		"points": [HUB_DEEP, Vector3(58, -145, -18), Vector3(42, -160, 2), CORE_CHAMBER],
	},
	{
		# The point of the mixed bore. 170 m of 2.5 m tunnel closing the biggest
		# loop in the level: it is the fast way from the west side to the bottom,
		# and it is the one route the creature cannot follow you down.
		"name": "the_squeeze",
		"bore_start": BORE_TIGHT + 0.25,
		"bore_end": BORE_TIGHT + 0.25,
		"points":
		[
			HUB_WEST,
			Vector3(-30, -62, 30),
			Vector3(0, -85, 18),
			Vector3(35, -100, -10),
			HUB_DEEP,
		],
	},
	{
		# Routed high, so it re-enters HUB_WEST facing the wrong way and the map
		# stops being a tree you can hold in your head.
		"name": "upper_loop",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_BRANCH,
		"points":
		[
			HUB_EAST,
			Vector3(40, -22, -5),
			Vector3(5, -18, 22),
			Vector3(-25, -26, 32),
			HUB_WEST,
		],
	},
	{
		"name": "spur_ante_north",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_ANTECHAMBER, Vector3(-6, -28, -18), Vector3(-2, -36, -34)],
	},
	{
		"name": "spur_ante_south",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_ANTECHAMBER, Vector3(12, -26, 16), Vector3(18, -20, 32)],
	},
	{
		"name": "spur_east_high",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_EAST, Vector3(76, -50, -8), Vector3(86, -46, 4)],
	},
	{
		"name": "spur_east_low",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_EAST, Vector3(52, -58, -34), Vector3(46, -70, -46)],
	},
	{
		"name": "spur_west_high",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_WEST, Vector3(-72, -34, 36), Vector3(-83, -30, 48)],
	},
	{
		"name": "spur_west_low",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_WEST, Vector3(-60, -52, 12), Vector3(-64, -64, 2)],
	},
	{
		"name": "spur_deep_east",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_DEEP, Vector3(84, -132, -52), Vector3(86, -144, -62)],
	},
	{
		"name": "spur_deep_west",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [HUB_DEEP, Vector3(56, -112, -56), Vector3(44, -108, -70)],
	},
	{
		"name": "spur_core",
		"bore_start": BORE_BRANCH,
		"bore_end": BORE_TIGHT,
		"points": [CORE_CHAMBER, Vector3(14, -178, 32), Vector3(2, -184, 42)],
	},
]
#endregion

#region Layout - chambers
#
# Spheres unioned into the same field as the capsules. They cost nothing extra -
# the field is a min over primitives either way - and they are what stops a
# junction reading as an X-crossing in a pipe.
#
# The hub radii are deliberately only a little wider than the trunk that arrives
# at them. A chamber much bigger than its corridors reads as a room someone built,
# and nothing down here was built.

const CHAMBERS := [
	{"center": HUB_ANTECHAMBER, "radius": 7.0},
	{"center": HUB_EAST, "radius": 7.0},
	{"center": HUB_WEST, "radius": 6.5},
	{"center": HUB_DEEP, "radius": 7.0},
	{"center": CORE_CHAMBER, "radius": 9.0},
	# Dead-end pockets. Somewhere for an ore node to sit and for you to have to
	# turn around in, which at 2 m bore is its own small problem.
	{"center": Vector3(-2, -36, -34), "radius": 2.6},
	{"center": Vector3(18, -20, 32), "radius": 2.6},
	{"center": Vector3(86, -46, 4), "radius": 2.6},
	{"center": Vector3(46, -70, -46), "radius": 2.6},
	{"center": Vector3(-83, -30, 48), "radius": 2.6},
	{"center": Vector3(-64, -64, 2), "radius": 2.6},
	{"center": Vector3(86, -144, -62), "radius": 2.6},
	{"center": Vector3(44, -108, -70), "radius": 2.6},
	{"center": Vector3(2, -184, 42), "radius": 2.6},
]
#endregion

#region Spawn

## Where the player starts, and what the HUD measures "distance home" against.
## A few metres down the shaft rather than in the mouth: a spawn flush with an
## opening puts the camera's near plane inside the cap.
const SPAWN_POSITION := Vector3(1, -9, -1)

## Which way the player faces at spawn - down the shaft, into the dark.
const SPAWN_LOOK_AT := Vector3(-3, -20, 2)
#endregion

#region Teleport stops
#
# One-click jumps to a sample of every size in the level, so the "does it feel
# different at 2 m than at 8 m" question can be answered by clicking back and
# forth rather than by flying four minutes between the two and trying to
# remember. Ordered widest to tightest.
#
# EVERY POSITION HERE SITS ON A CENTRELINE THE LAYOUT ACTUALLY CONTAINS, not
# somewhere near one. A stop picked by eye lands in solid rock, which renders as
# pure black and reads as a broken build rather than as a bad coordinate - that
# happened once already to a screenshot viewpoint. The [stops] check in
# verify_tunnel_system asserts every one of them is in open space.

const TELEPORT_STOPS := [
	{
		"label": "Core chamber",
		"bore": "18 m",
		"position": CORE_CHAMBER,
		"look_at": Vector3(14, -178, 32),
	},
	{
		"label": "Deep hub",
		"bore": "14 m",
		"position": HUB_DEEP,
		"look_at": Vector3(58, -145, -18),
	},
	{
		"label": "Antechamber",
		"bore": "14 m",
		"position": HUB_ANTECHAMBER,
		"look_at": Vector3(22, -34, -12),
	},
	{
		"label": "Entrance shaft",
		"bore": "8 m",
		"position": Vector3(1, -9, -1),
		"look_at": Vector3(-3, -20, 2),
	},
	{
		"label": "East trunk",
		"bore": "8 m",
		"position": Vector3(22, -34, -12),
		"look_at": Vector3(43, -36, -22),
	},
	{
		"label": "West trunk",
		"bore": "6 m",
		"position": Vector3(-40, -38, 20),
		"look_at": HUB_WEST,
	},
	{
		"label": "Upper loop",
		"bore": "3 m",
		"position": Vector3(5, -18, 22),
		"look_at": Vector3(-25, -26, 32),
	},
	{
		"label": "The squeeze",
		"bore": "2.5 m",
		"position": Vector3(0, -85, 18),
		"look_at": Vector3(35, -100, -10),
	},
	{
		"label": "Tight spur",
		"bore": "2.2 m",
		"position": Vector3(48.4, -65.2, -41.2),
		"look_at": Vector3(46, -70, -46),
	},
]
#endregion

#region Live tuning
#
# Bounds for the two sliders in the bottom-left panel. The panel exists so the
# two numbers most likely to be wrong can be argued about while flying, instead
# of by editing a constant and reloading.

const LAMP_ANGLE_MIN := 15.0
const LAMP_ANGLE_MAX := 75.0

const VIEW_DISTANCE_MIN := 6.0
const VIEW_DISTANCE_MAX := 60.0
#endregion
