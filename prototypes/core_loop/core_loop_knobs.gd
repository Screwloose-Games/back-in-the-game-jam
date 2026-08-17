class_name CoreLoopKnobs
extends RefCounted

## Every tunable value for the core gameplay loop prototype, in one place, plus
## the hand-authored map layout.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win over
## whatever is saved in the .tscn files.
##
## THIS FILE IS STILL WHERE A DEFAULT LIVES. The handful the tuning panel puts a
## slider on are overridden by core_loop_settings.tres, which the SAVE button
## writes - but that resource declares its defaults AS these consts, so there is
## still exactly one place any number is written down, and RESET means "read this
## file again".
##
## WHAT IS BORROWED AND WHAT IS OURS. The drill, crystal and debris numbers below
## are seeded from drill_and_mining/drill_knobs.gd and are DELIBERATE COPIES, not
## references: that prototype is unfinished, and when it settles its values will
## be locked there while these stay tunable here. Everything the suit does about
## flying, gripping and tethering is NOT copied - the suit reads MovementKnobs
## directly, because flight feel is a question the navigation and object carrying
## prototypes already answered.

#region What is switched on

## Whether contact with the creature costs anything beyond being seen.
##
## OFF, which is what this stage is for: a bump flips the creature to chasing and
## refreshes its timer, and nothing else happens. Being caught should first be
## something you can feel coming and get away from; a respawn on touch ends the
## run before the escape has been played even once.
const CATCH_IS_LETHAL := false

## Whether the creature exists at all. OFF is the control case for judging the
## mining and hauling loop on its own.
const MONSTER_ENABLED := true

## Whether the drill costs suit charge. The single number the drill and mining
## prototype has never had, which is why it arrives here as a slider.
const DRILL_DRAWS_POWER := true

## An emissive dot at every junction, hue keyed to the junction index.
##
## Not decoration. Sixteen routes of near-identical rock with no up and no down
## means the player is lost inside two minutes, and that one finding drowns every
## other finding this prototype exists to produce.
const JUNCTION_BEACONS := true
#endregion

#region Physics layers
#
# Bit VALUES, matching project.godot's [layer_names]: 1 hull, 2 player,
# 3 debris, 4 carryable, 5 creature, 6 ore, 7 loose_crystal.

const HULL_LAYER := 1
const PLAYER_LAYER := 2
const DEBRIS_LAYER := 4
const CARRYABLE_LAYER := 8

## Rock and the crystal still embedded in it.
const ORE_LAYER := 32

## A freed crystal, and nothing else. The layer change IS the state change - an
## embedded crystal physically cannot be collected.
const CRYSTAL_LAYER := 64

## What the suit collides with. Wider than either donor: CarrierSuit masks
## hull|carryable and DrillSuit masks hull|debris, and neither masks ore, so a
## verbatim copy of either would let you fly through the thing you are mining.
const SUIT_MASK := HULL_LAYER | DEBRIS_LAYER | CARRYABLE_LAYER | ORE_LAYER
#endregion

#region Map - dimensions
#
# The layout is ported from tunnel_system/tunnel_knobs.gd: same six junctions,
# same routes, same bones. What changed is the realisation - CSG boxes raised at
# _ready() rather than a baked signed distance field - and the widths.
#
# WIDTHS ARE CHOSEN AGAINST THE CREATURE, not against the player. It measures
# 3.9 m across and keeps probe_comfort = 3.2 m off every wall, so it needs 6.4 m
# of passage and physically cannot enter anything narrower. That is the whole
# point of the mixed width: the trunks are where it can reach you and the refuge
# routes are where it cannot.

## Width of a trunk route, metres. The width the chase prototype was tuned in, so
## the creature's pursuit is being judged at the size it is known to work at.
const WIDTH_TRUNK := 10.0

## Width of a connector or a wide spur, metres. Above the creature's 6.4 m
## minimum with 0.8 m either side - passable, and it has to mean it.
const WIDTH_CONNECTOR := 8.0

## Width of a refuge route, metres. Comfortably under the creature's minimum, so
## "duck in here" is a hard rule rather than a gamble.
const WIDTH_REFUGE := 4.0

## Rock around every bore. Only ever seen edge-on at a junction mouth, so it does
## not need to be thick - it needs to be non-zero, or the union leaves no solid
## for the subtraction to cut into.
const WALL_THICKNESS := 1.0

## The player's collision radius. Mirrors the SphereShape3D in the suit scene.
const PLAYER_RADIUS := 0.4
#endregion

#region Map - junctions
#
# Named because their coordinates must match EXACTLY between the routes that meet
# there. Sharing one of these constants between two routes is how a branch or a
# loop gets declared, so connectivity is true by construction rather than by luck.

## The mouth.
const ENTRANCE := Vector3(0, -4, 0)

## Foot of the entrance shaft. Four ways out: back up, east, west, and a spur.
const HUB_ANTECHAMBER := Vector3(0, -30, 0)

## The upper loop rejoins here, so you can arrive from two directions and not be
## able to tell which without having tracked your own route.
const HUB_EAST := Vector3(60, -45, -20)

## The only junction where a trunk meets the squeeze.
const HUB_WEST := Vector3(-55, -40, 25)

## 120 m down. Reachable by trunk the long way round or by the squeeze the short
## way, which is the whole decision the layout exists to pose.
const HUB_DEEP := Vector3(70, -120, -40)

## The terminus. Deepest point, biggest chamber, worst place to be caught.
const CORE_CHAMBER := Vector3(30, -170, 20)
#endregion

#region Map - routes
#
# One entry becomes a run of CSG box pairs: a hull box and a bore box per span.
# `points` is an open polyline, so a route bends by having more waypoints rather
# than by carrying a curve.

const ROUTES := [
	{
		"name": "entrance_shaft",
		"width": WIDTH_TRUNK,
		"points": [ENTRANCE, Vector3(4, -11, -3), Vector3(-3, -20, 2), HUB_ANTECHAMBER],
	},
	{
		"name": "east_trunk",
		"width": WIDTH_TRUNK,
		"points": [HUB_ANTECHAMBER, Vector3(22, -34, -12), Vector3(43, -36, -22), HUB_EAST],
	},
	{
		"name": "west_trunk",
		"width": WIDTH_TRUNK,
		"points": [HUB_ANTECHAMBER, Vector3(-20, -33, 10), Vector3(-40, -38, 20), HUB_WEST],
	},
	{
		"name": "deep_shaft",
		"width": WIDTH_TRUNK,
		"points": [HUB_EAST, Vector3(68, -70, -28), Vector3(74, -98, -36), HUB_DEEP],
	},
	{
		# A TRUNK, not a connector, and the navmesh decided that as much as the
		# design did. At 8 m its quads stopped linking to the deep hub's and the
		# whole branch baked as an ISLAND - the creature could wake down there and
		# never leave it, which reads as the noise system being broken rather than
		# as a mesh problem. Widening also makes the best rock in the network the
		# most dangerous to work, which is the trade this route should have been
		# posing anyway.
		"name": "core_descent",
		"width": WIDTH_TRUNK,
		"points":
		[
			HUB_DEEP,
			Vector3(66, -133, -30),
			Vector3(58, -145, -18),
			Vector3(50, -153, -8),
			Vector3(42, -160, 2),
			Vector3(36, -166, 12),
			CORE_CHAMBER,
		],
	},
	{
		# The longest way of saying no. 170 m closing the biggest loop in the
		# level: the fast way from the west side to the bottom, and the one route
		# the creature cannot follow you down.
		"name": "the_squeeze",
		"width": WIDTH_REFUGE,
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
		"width": WIDTH_CONNECTOR,
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
		"width": WIDTH_REFUGE,
		"points": [HUB_ANTECHAMBER, Vector3(-6, -28, -18), Vector3(-2, -36, -34)],
	},
	{
		"name": "spur_ante_south",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_ANTECHAMBER, Vector3(12, -26, 16), Vector3(18, -20, 32)],
	},
	{
		"name": "spur_east_high",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_EAST, Vector3(76, -50, -8), Vector3(86, -46, 4)],
	},
	{
		"name": "spur_east_low",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_EAST, Vector3(52, -58, -34), Vector3(46, -70, -46)],
	},
	{
		"name": "spur_west_high",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_WEST, Vector3(-72, -34, 36), Vector3(-83, -30, 48)],
	},
	{
		"name": "spur_west_low",
		"width": WIDTH_REFUGE,
		"points": [HUB_WEST, Vector3(-60, -52, 12), Vector3(-64, -64, 2)],
	},
	{
		"name": "spur_deep_east",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_DEEP, Vector3(84, -132, -52), Vector3(86, -144, -62)],
	},
	{
		"name": "spur_deep_west",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_DEEP, Vector3(56, -112, -56), Vector3(44, -108, -70)],
	},
	{
		"name": "spur_core",
		"width": WIDTH_CONNECTOR,
		"points": [CORE_CHAMBER, Vector3(14, -178, 32), Vector3(2, -184, 42)],
	},
]

## Every route the creature is meant to be unable to enter, by name. Not derived
## from `width` at runtime: this list is what the verifier asserts the navmesh
## does NOT cover, and a rule read off the same number it is checking proves
## nothing.
const REFUGE_ROUTES := ["the_squeeze", "spur_ante_north", "spur_west_low"]
#endregion

#region Map - chambers
#
# Spheres cut into the same combiner as the corridors. They are what stops a
# junction reading as an X-crossing in a pipe.
#
# The hub radii are only a little wider than the trunk that arrives at them. A
# chamber much bigger than its corridors reads as a room somebody built, and
# nothing down here was built.

const CHAMBERS := [
	{"center": HUB_ANTECHAMBER, "radius": 7.5},
	{"center": HUB_EAST, "radius": 7.5},
	{"center": HUB_WEST, "radius": 7.0},
	{"center": HUB_DEEP, "radius": 7.5},
	{"center": CORE_CHAMBER, "radius": 9.5},
	# Dead-end pockets. Somewhere for an ore node to sit and for you to have to
	# turn around in.
	{"center": Vector3(18, -20, 32), "radius": 4.5},
	{"center": Vector3(86, -46, 4), "radius": 4.5},
	{"center": Vector3(46, -70, -46), "radius": 4.5},
	{"center": Vector3(-83, -30, 48), "radius": 4.5},
	{"center": Vector3(86, -144, -62), "radius": 4.5},
	{"center": Vector3(44, -108, -70), "radius": 4.5},
	{"center": Vector3(2, -184, 42), "radius": 4.5},
	# The two refuge dead ends stay small, so they still read as somewhere you
	# squeezed into rather than somewhere you arrived.
	{"center": Vector3(-2, -36, -34), "radius": 2.8},
	{"center": Vector3(-64, -64, 2), "radius": 2.8},
]

## Radius of a beacon sphere, metres.
const BEACON_SIZE := 0.4

## How far a junction beacon throws. Short: it is a landmark, not a lamp, and one
## that lit its own chamber would do the helmet lamp's job for it.
const BEACON_LIGHT_RANGE := 6.0
const BEACON_LIGHT_ENERGY := 0.8
#endregion

#region Spawns

## Where the player starts. A few metres down the shaft rather than in the mouth:
## a spawn flush with an opening puts the camera's near plane inside the cap.
const SUIT_SPAWN := Vector3(1, -9, -1)

## Which way the player faces at spawn - down the shaft, into the dark.
const SUIT_LOOK_AT := Vector3(-3, -20, 2)

## Where the life support cube starts. Behind and below the suit, inside the
## shaft, so the first thing you do is turn around and find it.
const CUBE_SPAWN := Vector3(1, -13, -1)

## Where the creature and its follower are parked while dormant. Far outside the
## network, because a dormant creature is only hidden and disabled - parking it
## on a route would let its probe rays and its contact sphere sit in a corridor
## you are about to fly down.
const CREATURE_DORMANT_POSITION := Vector3(0, 400, 0)
#endregion

#region Movement
#
# Flight feel is settled and lives in MovementKnobs, which the suit reads
# directly. Only what THIS map changed is here.

## Cruising speed cap, metres per second. Above the 2.0 the donor suit ships
## with, because that was tuned in a 30 m room and this network is 200 m across.
const MAX_SPEED := 4.0
const MAX_SPEED_MIN := 1.0
const MAX_SPEED_MAX := 12.0

## Thrust acceleration, metres per second squared.
const THRUST_ACCELERATION := 10.0

## Multiplier on THRUST_ACCELERATION while sprint is held. From the navigation
## prototype, which is the only donor that has sprint at all.
const SPRINT_ACCELERATION_MULTIPLIER := 2.0

## Multiplier on MAX_SPEED while sprint is held. This is the number that decides
## whether you can outrun the creature, which moves at CREATURE_MAX_SPEED.
const SPRINT_SPEED_MULTIPLIER := 2.5

## How fast the speed ceiling falls back after sprint is released, in metres per
## second squared. The ceiling rises the instant sprint goes down and eases back,
## so releasing coasts rather than snapping.
const SPRINT_FALLOFF_RATE := 2.0
#endregion

#region Draw distance
#
# The power and lighting prototype's numbers, not the drill prototype's.
# drill_knobs.gd says loudly that its ambient 0.7 room is not the game's
# lighting; this is.

const FOG_DEPTH_BEGIN := 0.0

## Metres at which geometry is fully swallowed by fog. This is the number that
## actually sets how far you can see.
const FOG_DEPTH_END := 26.0
const FOG_DEPTH_END_MIN := 6.0
const FOG_DEPTH_END_MAX := 60.0

const FOG_DENSITY := 1.0
const FOG_LIGHT_COLOR := Color(0.09, 0.11, 0.15)

## How far past the fog the lamp throws, and how far past that the camera clips.
##
## FOG_DEPTH_END IS THE ONLY ONE OF THE THREE ANYONE SHOULD SET. Past the lamp's
## throw the rock is lit by AMBIENT_ENERGY alone and reads as black however clear
## the air is, and a clip plane inside the fog pops geometry out before the fog
## has hidden it. Deriving the other two makes both invariants structural.
const VIEW_LAMP_MARGIN := 0.0
const VIEW_CLIP_MARGIN := 8.0

## How far the helmet lamp throws at full charge, in metres. Derived.
const HELMET_LAMP_RANGE := FOG_DEPTH_END + VIEW_LAMP_MARGIN

## Hard clip distance. Derived.
const CAMERA_FAR := FOG_DEPTH_END + VIEW_CLIP_MARGIN

const HELMET_LAMP_ENERGY := 3.5

## Width of the helmet lamp cone in degrees, as a HALF-angle, so 45 is a 90
## degree cone.
const HELMET_LAMP_ANGLE := 45.0
const HELMET_LAMP_ANGLE_ATTENUATION := 0.75
const HELMET_LAMP_ATTENUATION := 1.0

## Warm white, against the cube's cool blue, so which light you are seeing by is
## never in question - which matters most exactly when the suit is nearly out and
## the two are comparable in strength.
const HELMET_LAMP_COLOR := Color(1.0, 0.96, 0.89)
const HELMET_LAMP_SHADOWS := true

## Near-black. There is no sky down here and no directional light, so this is the
## floor the whole network falls to once both lamps are out.
const AMBIENT_ENERGY := 0.02
const AMBIENT_ENERGY_MIN := 0.0
const AMBIENT_ENERGY_MAX := 0.25

## Whether lamps render back faces into their shadow maps instead of front faces.
## Only correct for closed solid casters, and the CSG shell is solid.
const SHADOW_REVERSE_CULL := true
const SHADOW_NORMAL_BIAS := 2.0
#endregion

#region Suit power

## How much charge the suit battery holds. The unit is arbitrary and only the
## ratios matter, so it is 100 and every readout is a percentage.
const SUIT_CAPACITY := 100.0

## How full the suit starts, 0 to 1. Not 1.0 on purpose: a prototype that opens
## at full charge spends its first stretch showing you nothing.
const SUIT_START_FRACTION := 0.6

## Charge the suit loses per second while its lamp is on, cube or no cube. At 100
## capacity this is thirty-three seconds from full to dead.
const SUIT_DRAIN_PER_SECOND := 3.0
const SUIT_DRAIN_MIN := 0.0
const SUIT_DRAIN_MAX := 8.0

## Charge per second the suit pulls out of a tethered cube.
##
## MUST EXCEED SUIT_DRAIN_PER_SECOND plus whatever the drill is costing, or
## clipping in only slows the dying down and the tether stops being worth its
## 10 m leash.
const SUIT_CHARGE_PER_SECOND := 12.0
const SUIT_CHARGE_MIN := 0.0
const SUIT_CHARGE_MAX := 30.0

## The suit's dimming curve, charge fraction across and brightness up. Settled in
## the power and lighting prototype: full brightness down to about three quarters
## of a battery, a long gentle sag through the middle, then a cliff in the last
## seventh. The warning is late and short, which is the frightening version.
const SUIT_DIM_POINTS: Array[Vector2] = [
	Vector2(0.000, 0.120),
	Vector2(0.139, 0.655),
	Vector2(0.385, 0.917),
	Vector2(0.751, 1.000),
	Vector2(1.000, 1.000),
]

## How far the helmet lamp still throws on a flat battery, in metres.
##
## A separate axis from the dim curve: how much the world shrinks against how
## much it darkens. Left alone, a dim lamp goes on reaching the far wall and the
## only thing that changed is the exposure. A reserve light that reads as one is
## dim AND short.
const SUIT_LAMP_MIN_RANGE_METRES := 12.0
const SUIT_LAMP_MIN_RANGE_FRACTION := SUIT_LAMP_MIN_RANGE_METRES / HELMET_LAMP_RANGE

## The suit's flicker curve, charge fraction across and dropouts per second up.
## Flat zero above about three fifths of a battery, so flicker is information
## rather than atmosphere.
const SUIT_FLICKER_POINTS: Array[Vector2] = [
	Vector2(0.000, 1.500),
	Vector2(0.161, 0.786),
	Vector2(0.363, 0.214),
	Vector2(0.619, 0.000),
	Vector2(1.000, 0.000),
]

const FLICKER_ENABLED := true
const FLICKER_RATE_MAX := 3.0
const FLICKER_DURATION := 0.09
const FLICKER_DEPTH := 0.15
const FLICKER_RANDOM_SEED := 20260809
#endregion

#region Cube power

## How much charge the cube holds. Six suits' worth: enough that the cube is the
## thing you plan around rather than the thing you watch.
const CUBE_CAPACITY := 600.0

## How full the cube starts, 0 to 1.
const CUBE_START_FRACTION := 0.5

## Charge the cube loses per second on its own. ZERO: the cube spends power only
## on the suit. Left as a knob rather than removed, because "life support running
## costs something" is the obvious next question and turning it on should be one
## number, not a code change.
const CUBE_IDLE_DRAIN_PER_SECOND := 0.0

## Charge per second cranking puts into the cube.
##
## ABOVE SUIT_CHARGE_PER_SECOND, so cranking is the fastest that power moves
## anywhere in this system. That makes it a way out of trouble rather than a
## penance - which means its cost has to come from having to stop, hold still and
## make the loudest noise in the game next to the drill, because it is not coming
## from the rate.
const CRANK_PER_SECOND := 40.0
const CRANK_MIN := 0.0
const CRANK_MAX := 80.0

## Held on its own key rather than sharing one with the grip.
##
## The power and lighting prototype split tap-grip from hold-crank on F by
## ERASING the project's `grab` action at runtime and re-synthesising it through
## Input.action_press with a physics priority to match. That works there because
## nothing else wants the key. Here the drill and the collector both do, so the
## crank gets its own binding and `grab` is left alone.
const CRANK_ACTION := &"crank"
const CRANK_KEY := KEY_C

## The cube's own lamp. Cool blue against the helmet's warm white.
const CUBE_LIGHT_COLOR := Color(0.579, 0.758, 1.0)
const CUBE_LIGHT_ENERGY := 2.0
const CUBE_LIGHT_RANGE := 16.0
const CUBE_LIGHT_ATTENUATION := 1.0
const CUBE_LIGHT_SHADOWS := true
const CUBE_GLOW := 1.0

## The cube's dimming curve: the suit's shape with a darker floor and a steeper
## climb out of it, so cranking a dead cube shows you something on the first turn
## of the handle rather than the tenth.
const CUBE_DIM_POINTS: Array[Vector2] = [
	Vector2(0.000, 0.071),
	Vector2(0.077, 0.512),
	Vector2(0.290, 0.810),
	Vector2(0.751, 1.000),
	Vector2(1.000, 1.000),
]

## The cube's glow curve. It sags further and faster than its lamp does, so the
## cube announces its own trouble before the light it casts does.
const CUBE_GLOW_POINTS: Array[Vector2] = [
	Vector2(0.000, 0.071),
	Vector2(0.178, 0.190),
	Vector2(0.325, 0.369),
	Vector2(0.479, 0.750),
	Vector2(0.751, 1.000),
	Vector2(1.000, 1.000),
]

const CUBE_FLICKER_POINTS: Array[Vector2] = [
	Vector2(0.000, 1.500),
	Vector2(0.098, 0.750),
	Vector2(0.269, 0.250),
	Vector2(0.619, 0.000),
	Vector2(1.000, 0.000),
]
const CUBE_FLICKER_SCALE := 0.7
const CUBE_LAMP_MIN_RANGE_FRACTION := 0.3

## The cube itself. Heavy enough that hauling it costs most of your thrust, and
## heavier still once let go of, which is what makes a taut tether reel you in
## toward the cube rather than towing it after you.
const CUBE_SIZE := 1.0
const CUBE_MASS := 1000.0
const CUBE_HELD_MASS := 200.0
const CUBE_LINEAR_DAMP := 0.05
const CUBE_ANGULAR_DAMP := 0.05

## The render layer the cube's own mesh sits on, so the cube's lamp can be told
## to ignore it. The lamp is INSIDE the box; without this it casts the box's own
## shadow over the entire chamber.
##
## CubePowerGauge hard-codes the same number and reads its segment count and size
## from PowerKnobs, which is why neither of those appears here - a knob that
## nothing reads is worse than no knob.
const CUBE_RENDER_LAYER := 2
#endregion

#region Drill
#
# COPIED FROM drill_and_mining/drill_knobs.gd, deliberately. See this file's
# header: that prototype is unfinished, and these have to stay tunable here after
# its own values are locked.
#
# THREE OF THEM HAVE BEEN RETUNED, AND THE REASON IS MEASURED. At the inherited
# CARVE_RATE 0.55, CARVE_RADIUS 0.22 and ESCAPE_CLEARANCE 0.16, a crystal cannot
# be freed by a beam at all - verify_core_loop held the trigger on one for sixty
# seconds, took 11% of the rock off, and never moved the escape opening off zero.
#
# That is not a bug over there. drill_and_mining's own [release] check passes, but
# it frees its crystal by calling carve() forty times at each of eight points
# stepping out from the crystal - about 8.0 of erosion per point. A beam delivers
# 0.009 per frame and its hit point RECEDES with the surface, so the erosion
# spreads along the bore instead of accumulating anywhere, and the last few
# centimetres beside the crystal never open because the crystal itself blocks the
# shot. That prototype has never had to free a crystal with the beam.
#
# CARVE_RADIUS is the lever that fixes it: the erosion taper is (1 - d/radius)
# squared, so at the old 0.22 a point 0.16 out got 7% of the rate and at 0.35 it
# gets 43%. Measured at these values, one hardness-1.0 node takes 18.6 s of held
# trigger with the crosshair sweeping - long enough for the drill's own noise to
# fetch the creature, which is the whole point of the loop.

const DRILL_ACTION := &"drill"
const DRILL_MOUSE_BUTTON := MOUSE_BUTTON_LEFT

## Offset of the DRAWN beam from the camera. The ray is cast from the camera, so
## the crosshair never lies.
const MUZZLE_OFFSET := Vector3(0.22, -0.17, -0.25)

const DRILL_RANGE := 6.0
const DRILL_RANGE_MIN := 1.0
const DRILL_RANGE_MAX := 15.0

## How fast the rock surface recedes at the centre of the bore, metres per second.
## RETUNED UP from the drill prototype's 0.55 - see the region header.
const CARVE_RATE := 1.00
const CARVE_RATE_MIN := 0.05
const CARVE_RATE_MAX := 2.5

## How wide a hole the beam opens, as against how fast it deepens it.
##
## RETUNED UP from the drill prototype's 0.22, and this is the one that decides
## whether a crystal can be freed by a beam at all. See the region header.
const CARVE_RADIUS := 0.35
const CARVE_RADIUS_MIN := 0.05
const CARVE_RADIUS_MAX := 0.60

const BEAM_RADIUS := 0.035
const BEAM_JITTER := 0.25
const IMPACT_DOT_RADIUS := 0.085

## Charge per second the drill takes out of the suit while it is cutting.
##
## THE NUMBER THIS PROTOTYPE EXISTS TO FIND. At 6.0 against a 3.0 idle drain the
## suit spends charge three times as fast while drilling as while flying, so a
## full battery is about eleven seconds of continuous cutting - which is roughly
## one crystal if the bore goes well. Whether that is tense or merely annoying is
## the question, and it is why this ships as a slider rather than a const.
const DRILL_POWER_PER_SECOND := 6.0
const DRILL_POWER_MIN := 0.0
const DRILL_POWER_MAX := 25.0
#endregion

#region Ore nodes

const FIELD_RESOLUTION := 24
const VOXEL_SIZE := 0.10
const SUBCHUNK_CELLS := 8

## Sub-chunks remeshed per frame ACROSS ALL NODES. The field is always current
## and the mesh lags it; this is how far behind it is allowed to get.
const REMESH_BUDGET := 3

const NODE_RADIUS := 1.0
const NODE_SURFACE_NOISE := 0.17

## Where the crystals are, and how hard.
##
## PLACEMENT IS THE RISK CURVE. Six of the eight sit in chambers and dead ends the
## creature can reach, and the two in refuge spurs are the safe ones - so choosing
## safety costs you the longer flight, and the richest rock is at the bottom of
## the network with the worst walk home.
const ORE_NODES := [
	# Antechamber. The tutorial one: soft, close to spawn, wide chamber.
	{"position": Vector3(4, -32, 3), "seed": 21_060_811, "hardness": 0.6},
	# East hub, both reachable.
	{"position": Vector3(56, -43, -16), "seed": 41_990_233, "hardness": 1.0},
	{"position": Vector3(63, -48, -24), "seed": 77_310_452, "hardness": 1.4},
	# West hub.
	{"position": Vector3(-52, -38, 22), "seed": 13_884_907, "hardness": 1.0},
	# Deep hub.
	{"position": Vector3(74, -118, -43), "seed": 55_201_744, "hardness": 1.4},
	# Core chamber. Deepest, hardest, longest haul home.
	{"position": Vector3(35, -168, 16), "seed": 90_114_326, "hardness": 1.8},
	# The two in refuge spurs. Safe from the creature, awkward to work in - a
	# 4 m bore leaves about a metre around a 2 m ball of rock.
	{"position": Vector3(-64, -64, 2), "seed": 33_672_015, "hardness": 1.0},
	{"position": Vector3(-2, -36, -34), "seed": 68_940_137, "hardness": 0.6},
]
#endregion

#region Crystal

const CRYSTAL_RADIUS := 0.34
const CRYSTAL_MASS := 12.0

## Probes on a golden-angle sphere looking for a way out of the rock. High, and it
## has to be: the widest tube found across all of them is what frees the crystal.
const ESCAPE_PROBE_COUNT := 256
const ESCAPE_CHECK_INTERVAL := 0.15

## How wide a clear tube out of the rock the crystal needs before it comes loose.
## MUST STAY UNDER CARVE_RADIUS, or a straight bore can never free one and you
## have to sweep the hole open.
##
## RETUNED DOWN from the drill prototype's 0.16 - see the region header.
const ESCAPE_CLEARANCE := 0.10
const ESCAPE_CLEARANCE_MIN := 0.05
const ESCAPE_CLEARANCE_MAX := 0.60

const CRYSTAL_FREE_IMPULSE := 0.55
const CRYSTAL_FREE_SPIN := 0.7

## How close you have to get to a freed crystal to collect it, measured from its
## centre. The suit is a 0.4 m sphere, so the gap you close is this minus that.
const COLLECT_RADIUS := 0.6
const COLLECT_RADIUS_MIN := 0.2
const COLLECT_RADIUS_MAX := 2.5

const COLLECT_NOTICE_TIME := 2.5
#endregion

#region Debris

const DEBRIS_ENABLED := true
const DEBRIS_SPAWN_RATE := 30.0
const DEBRIS_HEFT_WAITS := 3.0
const DEBRIS_MEAN_HEFT := 0.32
const DEBRIS_SIZE_MIN := 0.06
const DEBRIS_SIZE_MAX := 0.17
const DEBRIS_ASPECT_JITTER := 0.35
const DEBRIS_HEAVY_MASS_SCALE := 4.0
const DEBRIS_HEAVY_LIFETIME_SCALE := 2.5
const DEBRIS_KNOCK := 18.0
const DEBRIS_SPREAD_DEGREES := 26.0
const DEBRIS_LIFETIME := 1.8
const DEBRIS_FADE_FRACTION := 0.3
const DEBRIS_POOL_SIZE := 96
const DEBRIS_MASS := 1.5
const DEBRIS_SPIN := 7.0
const DEBRIS_LINEAR_DAMP := 0.08
const DEBRIS_ANGULAR_DAMP := 0.04
#endregion

#region Noise
#
# LOUDNESS IS A RADIUS IN METRES: the distance at which the creature can hear
# that source. Every other number in the monster region is measured against these,
# so keeping the unit physical is what stops the whole system becoming a set of
# unrelated magic numbers.

## How often a held source reports, in seconds. Not per frame: the director rolls
## a spawn chance against each report, so the tick rate would otherwise be a
## hidden multiplier on how often the creature appears.
const NOISE_TICK_INTERVAL := 0.25

## Drilling. Loud enough to be heard from the far end of a trunk route, which is
## the whole tension of the loop - the thing you came here to do is the thing that
## fetches it.
const DRILL_NOISE_RADIUS := 60.0
const DRILL_NOISE_MIN := 0.0
const DRILL_NOISE_MAX := 120.0

## Cranking. As loud as the drill, and it has to be held for fifteen seconds to
## fill a cube from flat.
const CRANK_NOISE_RADIUS := 60.0

## Sprinting. Loud enough that running away is not free, quiet enough that it
## still buys you distance.
const SPRINT_NOISE_RADIUS := 20.0

## Thrusters and stabilizers at cruising speed. Small: moving has to stay almost
## silent, or "stop making noise and wait" is not a move you can play.
const THRUST_NOISE_RADIUS := 12.0
const THRUST_NOISE_MIN := 0.0
const THRUST_NOISE_MAX := 40.0

## Above this radius a noise can wake a dormant creature. Between the sprint and
## the drill values, so only drilling and cranking can bring it out.
const SPAWN_TRIGGER_MIN_RADIUS := 30.0
#endregion

#region Monster

## Chance per second, while a loud noise is being made, that a dormant creature
## wakes up. At 0.08 the mean wait is about twelve seconds of drilling, so most
## single crystals are safe and a long session is not.
const SPAWN_CHANCE_PER_SECOND := 0.08
const SPAWN_CHANCE_MIN := 0.0
const SPAWN_CHANCE_MAX := 1.0

## How far, ALONG THE NAVMESH, a spawn point has to be from the noise that woke
## the creature. One or two tunnels: close enough to arrive while you are still
## working, far enough that it never simply appears next to you.
const SPAWN_MIN_PATH := 35.0
const SPAWN_MAX_PATH := 90.0

## Straight-line distance from the player a spawn point must also clear. The path
## check alone is not enough - a route that doubles back can be 60 m long and
## 15 m away through the rock, which reads as the creature materialising.
const SPAWN_MIN_PLAYER_DISTANCE := 25.0

## How close the creature has to be for a noise to give the player away
## completely. Inside this, any noise flips it from hunting to chasing.
const CHASE_TRIGGER_RADIUS := 18.0
const CHASE_TRIGGER_MIN := 2.0
const CHASE_TRIGGER_MAX := 60.0

## How long a chase runs on one refresh, in seconds. Short on purpose: the escape
## is sprint away, break the trigger radius, then stop thrusting and wait. A long
## chase makes that unplayable, because you cannot go silent while being seen.
const CHASE_DURATION := 6.0
const CHASE_DURATION_MIN := 1.0
const CHASE_DURATION_MAX := 30.0

## How long the creature goes without hearing anything before it gives up and
## despawns, in seconds.
const DESPAWN_SILENCE := 25.0
const DESPAWN_SILENCE_MIN := 5.0
const DESPAWN_SILENCE_MAX := 120.0

## How often the director re-points its quarry marker while chasing, in seconds.
const CHASE_REFRESH_INTERVAL := 0.2

## Where a woken creature can come from.
##
## EVERY ONE OF THESE IS ON A ROUTE THE CREATURE CAN ACTUALLY GET DOWN, which is
## why the refuge routes are absent - a spawn inside the squeeze puts it somewhere
## the navmesh does not reach and it never arrives, which reads as the whole
## system being broken.
##
## Which one gets used is decided at runtime by path length from the noise, not by
## this order; the list only has to be spread widely enough that there is usually
## something one or two tunnels away wherever you are working.
##
## THE CORE DESCENT IS ABSENT for the same reason, and a worse one - see
## NAVMESH_ISLAND_ROUTES below. Waking down there would strand it.
const MONSTER_SPAWN_POINTS := [
	Vector3(4, -11, -3),
	Vector3(-3, -20, 2),
	HUB_ANTECHAMBER,
	Vector3(22, -34, -12),
	Vector3(43, -36, -22),
	HUB_EAST,
	Vector3(-20, -33, 10),
	Vector3(-40, -38, 20),
	HUB_WEST,
	Vector3(68, -70, -28),
	Vector3(74, -98, -36),
	HUB_DEEP,
	Vector3(40, -22, -5),
	Vector3(5, -18, 22),
	Vector3(-25, -26, 32),
]

## Routes whose navmesh bakes as an ISLAND, disconnected from the rest.
##
## KNOWN, MEASURED, AND NOT A CONFIGURATION MISTAKE. core_descent is the steepest
## diagonal in the network - it drops 50 m while moving 40 m sideways, twice - and
## a world-axis lattice crossing a surface at that angle emits a staircase whose
## quads meet four-to-an-edge at the inside corners. Godot's navigation map links
## polygons in pairs and reports the rest as "more than 2 edges tried to occupy
## the same map rasterization space", dropping them; enough dropped edges in a row
## severs the branch.
##
## Ruled out by experiment, so nobody has to repeat them: widening the route from
## 8 m to 10 m, halving the fill cell from 1.5 m to 1.0 m (which made it worse),
## doubling the mesh cell_size to 0.5 m, adding intermediate waypoints, removing
## every chamber sphere, and detaching the squeeze from the deep hub.
##
## WHAT IT COSTS: the creature cannot reach the core chamber, so the deepest and
## richest rock is safe to work. That is a real hole in the loop and it is why
## this list exists rather than the fact being left to be discovered. The fix is
## in WallNavmeshBaker - a fill that also opened diagonal neighbours, or a merge
## pass over coincident edges - and that file belongs to the chase prototype, so
## it is not this one's to change mid-jam.
const NAVMESH_ISLAND_ROUTES := ["core_descent"]
#endregion

#region Creature
#
# The creature arrives tuned for a 244 m corridor it shared with nothing. Both
# masks matter: they default to hull|prop, and in THIS project layer 2 is the
# player, so untouched the body probe reads the player as a wall to swerve away
# from and the tentacles try to take a grip on one.

const CREATURE_MAX_SPEED := 9.0
const CREATURE_MAX_SPEED_MIN := 1.0
const CREATURE_MAX_SPEED_MAX := 20.0

const CREATURE_LEASH_SLACK := 1.2

## How far off every wall the creature holds. DOUBLED, this is the narrowest
## passage it can pass down, which is what WIDTH_REFUGE is chosen against.
const CREATURE_PROBE_COMFORT := 3.2

## Hull only. Not the player, and not ore.
const CREATURE_PROBE_MASK := HULL_LAYER
const CREATURE_TENTACLE_MASK := HULL_LAYER

const CREATURE_LIGHT_COLOR := Color(0.72, 0.42, 0.95)
const CREATURE_LIGHT_RANGE := 14.0
const CREATURE_LIGHT_ENERGY := 1.1
const CREATURE_LIGHT_ATTENUATION := 1.5
const CREATURE_LIGHT_SHADOWS := false

## THE CREATURE'S REACH, not its waist. Its torso is 2.15 m across and its
## tentacles throw several metres past that.
##
## MUST BEAT THE STANDOFF CHAIN or the contact can never fire: half the corridor
## width, plus FOLLOWER_CLEARANCE, plus CREATURE_LEASH_SLACK. In a 10 m trunk
## that is 5.0 + 1.5 + 1.2 = 7.7, which is why this is 8.5 and not the 5.0 the
## chase prototype shipped. CoreLoopSettings.invariant_failures() checks it
## against whatever the slider is left on.
const CATCH_RADIUS := 8.5
const CATCH_RADIUS_MIN := 1.0
const CATCH_RADIUS_MAX := 16.0

const CATCH_LAYER := 4
const CATCH_MASK := PLAYER_LAYER

## How long the creature's audio carries. Raised past the fog on purpose: you
## should hear it coming down the trunk before the murk gives it up.
const CREATURE_AUDIO_MAX_DISTANCE := 70.0
const CAVE_BUS := &"CaveSFX"
const CAVE_SEND_BUS := &"SFX"
const CAVE_BUS_VOLUME_DB := -3.0
#endregion

#region Follower

const FOLLOWER_SPEED := 7.0
const FOLLOWER_ACCEL := 10.0
const FOLLOWER_BRAKE := 8.0
const FOLLOWER_REPATH_INTERVAL := 0.35
const FOLLOWER_PATH_DESIRED_DISTANCE := 2.0
const FOLLOWER_TARGET_DESIRED_DISTANCE := 2.5

## How far off any wall the marker holds. Containment pushes it this far out and
## the path corners are lifted by the same number, so the two agree rather than
## fight.
const FOLLOWER_CLEARANCE := 1.5
const FOLLOWER_CONTAINMENT_MASK := HULL_LAYER

## How often the target re-projects onto the navmesh, in seconds.
const TARGET_REFRESH_INTERVAL := 0.2
#endregion

#region Navigation mesh
#
# WallNavmeshBaker floods open space with physics queries and puts a quad on every
# open-meets-solid face. It knows nothing about geometry, which is what makes the
# map a swappable node.
#
# THESE ARE NOT THE CHASE PROTOTYPE'S VALUES and could not be. Its 2.5 m cell and
# 0.45 m openness radius were chosen for one 10 m box corridor; over a network
# that also contains 4 m refuge routes, that pair paints navmesh into passages the
# creature cannot fit down, and it then jams in one looking exactly like broken
# pathfinding.

## Grid edge length, metres. Smaller than the chase prototype's 2.5 so the lattice
## can still find open cells near the axis of a trunk once the openness radius
## below is asking for 2.4 m of clearance.
const NAVMESH_CELL := 1.5

## The sphere radius that decides whether a cell counts as open.
##
## THIS IS THE KNOB THAT KEEPS THE CREATURE OUT OF THE REFUGE ROUTES, and it is
## why it is 2.4 rather than the 0.45 that only has to clear a marker. A 4 m bore
## offers 2.0 m of clearance at its axis and fails; an 8 m bore offers 4.0 and
## passes. Everything the creature should not enter is therefore not on the mesh
## at all, rather than on it and unreachable in practice.
const NAVMESH_OPENNESS_RADIUS := 2.4

## Hull only.
const NAVMESH_PROBE_MASK := HULL_LAYER

## The NavigationMesh's own quantisation, which is what the map hashes polygon
## edges with. A mismatch reads as a mesh that looks right in the debug overlay
## and cannot be pathed across.
const NAVMESH_CELL_SIZE := 0.25

## Leak guard. The fill is bounded by reachability, so passing this means the
## shell has a hole in it rather than that the network got big.
const NAVMESH_MAX_CELLS := 60000

## How far outside the network's own extent the fill is fenced.
const NAVMESH_BOUNDS_MARGIN := 20.0
#endregion
