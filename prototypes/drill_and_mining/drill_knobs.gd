class_name DrillKnobs
extends RefCounted

## Every value for the drill and mining prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win over
## whatever is saved in the .tscn files - there is nothing to tweak in the
## inspector, and no exported copy of these that could drift out of sync.
##
## THIS FILE OUTRANKS imported/drill_movement_knobs.gd. That one was copied whole
## from the navigation prototype and still carries a Draw Distance region and the
## whole corridor layout; the suit applies its own two optical values in _ready
## and drill_and_mining_prototype.gd overwrites them from here immediately after.
## Movement is that file's; everything about rock, beam and murk is this one's.

#region What is switched on
#
# The prototype answers one question at a time, and everything that answers a
# different one is switched off here rather than deleted.
#
# STAGE 1 ASKED whether cutting a crystal free of the rock around it is
# satisfying. IT DOES, WITH CONDITIONS, and the conditions are why the rock is
# now a voxel field rather than eighty chunks - see the Ore node region.
#
# Still not in play, each waiting on its own switch: power draw, the lamp as a
# mechanic, sound, the creature, and anywhere to take a crystal once you have it.

## Whether a carve throws anything into the room.
##
## ON, and it is now the loudest thing in the prototype. Off is worth a look
## exactly once, to see how much of the drill's weight was coming from the spray
## rather than from the hole.
const DEBRIS_ENABLED := true

## How a freed crystal is collected. OFF: fly into it. ON: hold it in the
## crosshair and press the grab key.
const COLLECT_REQUIRES_KEY := false

# THERE IS NO *_TUNING_ENABLED SWITCH HERE, and one cannot be added. The power
# prototype has them because it hand-built its own panel; this one uses the
# shared PrototypeTuningPanel, which builds itself from whatever the settings
# resource exports and has no way to be told to skip a property. @export_range IS
# the opt-in, as prototypes/AGENTS.md says - so retiring an answered question
# means deleting its @export_range from drill_settings.gd, which leaves the const
# below as the answer.
#endregion

#region Physics layers
#
# Bitmask values, not layer indices, matching the convention in every other
# prototype here. The names for 1-4 are in project.godot; 5 and 6 are this
# prototype's and are named there too.

const HULL_LAYER := 1
const PLAYER_LAYER := 2
const DEBRIS_LAYER := 4

## Rock, and a crystal still embedded in it.
##
## THE DRILL DOES NOT USE THIS LAYER. It walks the voxel field directly - see
## VoxelField.raymarch - because the collision shapes are rebuilt on a budget and
## therefore lag the field by a frame or two. Rock collision exists so that you
## bump into a node while flying, and for nothing else.
const ORE_LAYER := 16

## A crystal that has come loose, and nothing else.
##
## The layer change IS the state change. The collector on the suit masks this and
## not ORE_LAYER, so an embedded crystal cannot be collected by flying at it -
## not because something checks a flag, but because the two are not on speaking
## terms until the rock lets go.
const CRYSTAL_LAYER := 32
#endregion

#region Drill

## Which mouse button drills, and what the action is called.
##
## Registered onto the running InputMap at startup rather than written into
## project.godot - the prototype keeps its own bindings, the same way the power
## prototype does, and project.godot is shared with every other prototype and
## with the game.
const DRILL_ACTION := &"drill"
const DRILL_MOUSE_BUTTON := MOUSE_BUTTON_LEFT

## Where the beam appears to come from, in camera space: down and to the right,
## as though there were a tool in that hand.
##
## THE RAY IS NOT CAST FROM HERE. It is cast from the camera, so the crosshair
## tells the truth about what will be hit; only the drawn beam starts at the
## muzzle.
const MUZZLE_OFFSET := Vector3(0.22, -0.17, -0.25)

## How far the beam reaches, in metres.
##
## Short on purpose. The whole difficulty of mining in zero-G is holding station
## against your own drift, and a beam that reaches across the room lets you dodge
## that entirely.
const DRILL_RANGE := 6.0
const DRILL_RANGE_MIN := 1.0
const DRILL_RANGE_MAX := 15.0

## How fast the rock surface recedes at the centre of the bore, in metres per
## second.
##
## THIS REPLACES THE OLD CHUNK HEALTH, and it is the same finding wearing better
## clothes. Playtesting stage 1 settled on 10 health against 90 a second - nine
## chunks a second, at which point the chunk had stopped being the unit of
## destruction and started being the thing in the way. A rate in metres per
## second says directly what that was groping for.
##
## At this rate the 0.7 m of rock between the surface and the crystal is about a
## second and a half, and widening the hole enough to get the crystal out is
## another second or two.
const CARVE_RATE := 0.55
const CARVE_RATE_MIN := 0.05
const CARVE_RATE_MAX := 2.5

## Radius of the bore, in metres. How wide a hole the beam opens, as against how
## fast it deepens it.
##
## Erosion tapers to nothing at this radius, so the hole comes out rounded rather
## than as a stamped cylinder.
const CARVE_RADIUS := 0.22
const CARVE_RADIUS_MIN := 0.05
const CARVE_RADIUS_MAX := 0.60

## Radius of the drawn beam, in metres, and how much it flickers frame to frame
## as a fraction of that. A dead still cylinder reads as a prop.
const BEAM_RADIUS := 0.035
const BEAM_JITTER := 0.25

## Radius of the dot where the beam lands, in metres.
const IMPACT_DOT_RADIUS := 0.085
#endregion

#region Ore node
#
# A node is a signed distance field on a dense grid, wrapped around an
# indestructible crystal. Negative is rock, positive is space, and the drill
# erodes the field rather than deleting anything discrete.
#
# WHY THIS AND NOT THE EIGHTY-CHUNK SHELL IT REPLACES: the shell was tuned in a
# playtest to ten health a chunk against ninety a second, which removed nine
# chunks a second. At that rate what the drill felt like was set by the chunk
# grid rather than by the beam, and 0.34 m is a coarse grid to feel. The field is
# three times finer and continuous, so the bore is the beam's own width and the
# rate is a number in metres per second.
#
# ZYLANN'S VOXEL TOOLS IS IN THIS REPO AND IS DELIBERATELY NOT USED. Its shipped
# binaries have no web build, this project has a web export preset, and a node is
# a 2.4 m cube rather than a world - none of what that addon is for.

## Cells per axis, and how big one is in metres. 24 cells at 0.1 m is a 2.4 m
## cube per node, which is 15,625 corner values - 62 KB.
const FIELD_RESOLUTION := 24
const VOXEL_SIZE := 0.10

## Cells per sub-chunk edge. 8 gives 3x3x3 sub-chunks a node, and a carve of the
## default radius touches between one and eight of them.
##
## Smaller means cheaper remeshes and more draw calls; larger, the reverse. This
## is the dial to reach for if drilling hitches.
const SUBCHUNK_CELLS := 8

## How many sub-chunks may be remeshed in one frame, across all nodes. The rest
## wait their turn.
##
## Remeshing is GDScript and is by far the most expensive thing here. The budget
## is what stops a wide carve from spending twenty milliseconds in one frame; the
## cost of it is that the rock can lag the beam very slightly under sustained
## fire, which is the trade worth watching in a playtest.
const REMESH_BUDGET := 3

## Radius of a node's rock in metres, and how far its surface wanders either way.
## Keep the two together under half the field's extent (1.2 m) or the ball is
## clipped flat where it meets the edge of the grid.
const NODE_RADIUS := 1.0
const NODE_SURFACE_NOISE := 0.17

## Where the nodes are, how they are seeded, and how tough each one is.
##
## The seed makes a node reproducible: the same number gives the same lumps every
## run, which is what lets two playtests of a tuning change be compared at all.
## Hardness divides the carve rate, so 1.8 is a node that takes nearly twice as
## long - one that is over quickly, two ordinary, one deliberate slog.
##
## Two of them are pushed into a wall. You cannot get behind those, and finding
## out whether that is interesting or merely annoying is half of what the room is
## for.
const ORE_NODES := [
	{"position": Vector3(0.0, 0.0, -3.0), "seed": 21_060_811, "hardness": 1.0},
	{"position": Vector3(-6.5, 1.5, -8.0), "seed": 41_990_233, "hardness": 0.6},
	{"position": Vector3(11.4, -1.0, -2.0), "seed": 77_310_452, "hardness": 1.0},
	{"position": Vector3(4.0, 4.4, -9.5), "seed": 13_884_907, "hardness": 1.8},
]
#endregion

#region Crystal

## Radius of the crystal itself, in metres.
const CRYSTAL_RADIUS := 0.34

## Mass of a freed crystal in kg. Heavier than a rock fragment, so nudging it is
## a decision rather than an accident.
const CRYSTAL_MASS := 12.0

## How many directions out of the rock are tested, spread by the golden angle.
##
## HIGH, AND IT HAS TO BE. A probe that is a few degrees off the axis of the hole
## you drilled walks out of the side of it before it reaches open air, and reports
## rock. At 48 probes the worst gap between directions is about 16 degrees, which
## over the length of a node is a quarter of a metre sideways - wider than the
## bore - so whether a crystal came loose depended on how nearly your aim happened
## to line up with one of them. At 256 the gap is around 7 degrees and a straight
## bore is found from anywhere.
##
## The cost is paid back by ESCAPE_CHECK_INTERVAL rather than by being small.
const ESCAPE_PROBE_COUNT := 256

## How often the escape test may run, in seconds.
##
## It is a few thousand field samples, and it does not need to be current: a
## crystal that comes loose a tenth of a second late is a crystal that came loose.
## Running it on every frame the beam is cutting is what would make the probe
## count expensive.
const ESCAPE_CHECK_INTERVAL := 0.15

## How wide a clear tube out of the rock the crystal needs, in metres.
##
## THE FIELD'S OWN VALUE ANSWERS THIS. A signed distance field says, at every
## point, how far the nearest rock is - so a sample of at least this much means
## everything within that radius of the point is empty, and one number per step
## along a probe settles what a cone of rays would have to be traced for. That is
## the whole reason the rock is an SDF and not a bitmask.
##
## MUST BE UNDER CARVE_RADIUS or a straight hole can never free anything and you
## have to sweep the beam around to widen one - which is a different game, and a
## slower one. DrillSettings.invariant_failures says so when a slider breaks it.
##
## Well below CRYSTAL_RADIUS as well, which is to say the crystal squeezes out of
## a hole quite a lot too small for it. Stage 1 was played with the old cone knob
## at its maximum, so forgiving is what was asked for; the physically honest 0.34
## is a drag away, and wants a wider bore to go with it.
const ESCAPE_CLEARANCE := 0.16
const ESCAPE_CLEARANCE_MIN := 0.05
const ESCAPE_CLEARANCE_MAX := 0.60

## Impulse and tumble the crystal leaves with, along the hole it came out of.
## Enough that it visibly comes loose - one that stayed exactly where it was
## would be indistinguishable from one still held.
const CRYSTAL_FREE_IMPULSE := 0.55
const CRYSTAL_FREE_SPIN := 0.7

## How close you have to get to collect a freed crystal, in metres, measured from
## its centre. The suit is a 0.4 m sphere, so the gap you close is this minus that.
const COLLECT_RADIUS := 0.6
const COLLECT_RADIUS_MIN := 0.2
const COLLECT_RADIUS_MAX := 2.5

## How long the HUD says so after something happens, in seconds.
const COLLECT_NOTICE_TIME := 2.5
#endregion

#region Debris
#
# THE SPRAY IS NOW ITS OWN THING, and that is the second half of what stage 1
# found. With chunks, one chunk death was one thrown object, so how fast rock
# vanished and how violently it flew were the same number - and the playtest
# pushed both to their limits at once. A field has nothing discrete to throw, so
# fragments are spawned at a rate, sized how you like, and hurled as hard as you
# like, none of which is tied to how fast the hole deepens.
#
# WHICH WAY THEY GO IS THE BEAM REFLECTED OFF THE ROCK, and that costs nothing
# because the field's gradient is the surface normal - see
# DrillBeam._spray_direction. Down a deep bore that is straight back at your
# visor; off a wall at a glance it sheets away sideways.

## Fragments thrown per second while the beam is cutting rock, ON AVERAGE.
##
## Arrivals are a POISSON PROCESS, not a metronome: the gap to the next fragment
## is drawn from an exponential distribution with this mean. Evenly spaced
## fragments read as a conveyor no matter how fast they come, and rock does not
## come off on a schedule.
##
## HIGH, and it can be, because most of what it throws is now grit: heft makes a
## fragment big only when the gap that earned it was long, so raising the rate
## fills the room with dust and makes a slab rarer rather than making everything
## more numerous and the same size.
const DEBRIS_SPAWN_RATE := 30.0
const DEBRIS_SPAWN_RATE_MIN := 0.0
const DEBRIS_SPAWN_RATE_MAX := 60.0

## How long a gap earns a full-sized fragment, in multiples of the average gap.
##
## THE WAIT IS THE FRAGMENT. A long gap is the drill having hung on to a piece
## rather than having thrown nothing, so it comes off bigger, heavier, slower and
## it lasts longer. Everything below scales off that one number.
##
## Measured in mean waits, so it means the same thing at any rate. Exponential
## waits put about e^-3, or 5%, of fragments at this ceiling - which is what
## makes a slab an event rather than the texture.
const DEBRIS_HEFT_WAITS := 3.0

## The average heft that produces, for working out how many fragments are in the
## air. E[min(u / 3, 1)] for u exponential with mean 1, which is
## (1 - 4e^-3) / 3 + e^-3. Re-derive it if DEBRIS_HEFT_WAITS moves.
const DEBRIS_MEAN_HEFT := 0.32

## Edge length of a fragment, in metres, at heft 0 and heft 1. Around voxel
## scale, so what flies off looks like it came out of the hole.
const DEBRIS_SIZE_MIN := 0.06
const DEBRIS_SIZE_MAX := 0.17

## How far each axis of a fragment may wander from that edge, as a fraction of
## it. Without this heft would produce a graded set of cubes.
const DEBRIS_ASPECT_JITTER := 0.35

## What the heaviest fragment weighs, against the lightest.
##
## THIS IS ALSO WHY A BIG FRAGMENT IS SLOW, and it is the only reason - the
## impulse below does not change. The same kick of rock coming apart moves a
## heavier piece less, so mass carries the size, the weight of the hit and the
## speed on one number rather than three that can disagree.
const DEBRIS_HEAVY_MASS_SCALE := 4.0

## How much longer the heaviest fragment lasts, against the lightest. Big pieces
## should still be in the room after the grit that came with them has gone.
const DEBRIS_HEAVY_LIFETIME_SCALE := 2.5

## Impulse given to a fragment, in newton-seconds. THE SAME FOR EVERY FRAGMENT -
## what varies is the mass it lands on, so speed comes out of
## DEBRIS_HEAVY_MASS_SCALE and not from a second knob here.
##
## Against the lightest fragment that is 12 m/s; against the heaviest, 3.
##
## Stage 1 was played with this at 15, which was that slider's maximum - so the
## answer was "at least this, and possibly more". The default is now past where
## the old ceiling was and the ceiling is well past that.
const DEBRIS_KNOCK := 18.0
const DEBRIS_KNOCK_MIN := 0.0
const DEBRIS_KNOCK_MAX := 45.0

## Half-angle of the cone the knock is scattered through, in degrees. At zero
## every fragment leaves along exactly the beam, which reads as a conveyor.
const DEBRIS_SPREAD_DEGREES := 26.0

## How long the LIGHTEST fragment lasts before it is recycled, in seconds. A
## heavy one lasts DEBRIS_HEAVY_LIFETIME_SCALE times this.
##
## Short, because the spawn rate is high: the two multiply into how many are in
## the air, and DEBRIS_POOL_SIZE is the ceiling on that. At 30 a second and a
## mean heft of 0.32 the average fragment lives 2.7 s, so about 80 are loose
## while the beam is cutting.
const DEBRIS_LIFETIME := 1.8
const DEBRIS_LIFETIME_MIN := 0.5
const DEBRIS_LIFETIME_MAX := 20.0

## The last of a fragment's life, as a fraction of it, spent shrinking away
## rather than blinking out.
const DEBRIS_FADE_FRACTION := 0.3

## How many fragments may exist at once. The oldest is recycled when the pool
## runs dry, so the cap is on what is in the room and never on what you may drill.
##
## Sized to sit above the ~80 the defaults imply, with room for the fact that a
## Poisson process arrives in clumps rather than on average. This is also a draw
## call and a rigid body apiece, so it is the first number to cut if the web
## build struggles - before the rate, which is what the spray is made of.
const DEBRIS_POOL_SIZE := 96

## Mass of the LIGHTEST fragment in kg. Against the suit's 90 kg, light enough to
## be swatted aside - grit should not shove you off station. A heavy one is
## DEBRIS_HEAVY_MASS_SCALE times this and is meant to be felt.
const DEBRIS_MASS := 1.5

## Peak tumble a fragment leaves with, in radians per second.
const DEBRIS_SPIN := 7.0

## Nothing slows down in vacuum, but a little damping stops fragments touring the
## room forever. Set both to 0.0 for true drift.
const DEBRIS_LINEAR_DAMP := 0.08
const DEBRIS_ANGULAR_DAMP := 0.04
#endregion

#region Chamber
#
# One open room. The pillars are not obstacles to thread - they are there so a
# suit that is drifting looks different from one that is not, which an empty box
# cannot show you.

## Interior dimensions of the room in metres: wide, tall, deep.
const CHAMBER_SIZE := Vector3(24.0, 12.0, 24.0)

## How thick the hull around the room is, in metres.
const WALL_THICKNESS := 0.6

## Free-standing pillars, as centre and size, running floor to ceiling.
const PILLARS := [
	{"center": Vector3(-8.0, 0.0, 2.0), "size": Vector3(1.2, 12.0, 1.2)},
	{"center": Vector3(7.0, 0.0, 6.0), "size": Vector3(1.6, 12.0, 1.6)},
]

## Where the suit starts, facing -Z.
const SUIT_SPAWN := Vector3(0.0, 0.0, 6.0)
#endregion

#region Draw distance

## Metres at which fog starts to thicken.
##
## Past DRILL_RANGE on purpose. Fog that begins at the visor puts a wash of
## near-black over the rock you are working on, and this stage is about being
## able to read that rock.
const FOG_DEPTH_BEGIN := 7.0

## Metres at which geometry is fully swallowed by fog - the number that actually
## sets how far you can see.
const FOG_DEPTH_END := 22.0
const FOG_DEPTH_END_MIN := 4.0
const FOG_DEPTH_END_MAX := 60.0

## How sharply fog ramps between begin and end.
const FOG_DENSITY := 1.0

## What the murk is coloured, and therefore what a fully fogged surface fades to.
## Much lighter than the navigation and tunnel prototypes' near-black, which
## faded the far half of a 24 m room to a void.
const FOG_LIGHT_COLOR := Color(0.09, 0.11, 0.15)

## Hard clip distance in metres. Keep it above FOG_DEPTH_END or geometry pops
## out before the fog has hidden it.
const CAMERA_FAR := 32.0
const CAMERA_FAR_MIN := 4.0
const CAMERA_FAR_MAX := 90.0

## The helmet lamp.
##
## THIS IS NOT THE GAME'S LIGHTING AND MUST NOT BE COPIED AS IF IT WERE.
## power_and_lighting owns that question and answered it at 45 degrees and
## energy 3.5, seen through a fog that starts at the visor. Judging a crater wall
## against a lamp that is itself failing would be judging two things at once, so
## the lamp here is turned up until it stops being a variable.
const HELMET_LAMP_RANGE := 20.0
const HELMET_LAMP_ANGLE := 52.0
const HELMET_LAMP_ENERGY := 1.5

## Ambient light: the floor under everything the lamp is not pointed at. Far
## above the power prototype's 0.02, so you can find the next node without flying
## the room in a grid.
const AMBIENT_COLOR := Color(0.46, 0.50, 0.58)
const AMBIENT_ENERGY := 0.7
const AMBIENT_ENERGY_MIN := 0.0
const AMBIENT_ENERGY_MAX := 1.5

## Shadow artefacts, both taken from power_and_lighting where they were worked
## out. The GL Compatibility renderer filters shadows far more narrowly than
## Forward+ does, so a shadow map's own texel grid shows through as parallel
## stripes across any flat surface a lamp is pointed at. Reverse cull moves the
## self-shadowing onto faces turned away from the lamp; normal bias pushes each
## lookup along the surface normal before it is tested.
const SHADOW_REVERSE_CULL := true
const SHADOW_NORMAL_BIAS := 2.0
#endregion
