class_name ChaseKnobs
extends RefCounted

## Every tunable value for the chase prototype, in one place.
##
## These values are read directly by the prototype's scripts and pushed onto the
## scene at startup, so they win over whatever is saved in the .tscn files - there
## is nothing to tweak in the inspector.
##
## THE CREATURE SETS THE SCALE OF THE WORLD, and that is the lesson this file was
## rewritten around. The first version of this prototype ran the chase through the
## object carrying prototype's chamber, which is joined to its back compartment by
## a 5 m hatch. The creature could almost never get through it: its body radius is
## 2.15 m and it tries to hold 3.2 m off the nearest surface, so in a 5 m opening
## it is inside its own comfort distance of all four sides at once and its
## avoidance shoves it back out. It looked like broken pathfinding and it was
## nothing of the kind - the doorway was simply narrower than the creature.
##
## So CORRIDOR_WIDTH is not a matter of taste. See MIN_PASSAGE_WIDTH below.

#region Corridor network
#
# One tube of square cross-section per span, hull unioned first and tunnels
# subtracted after, so junctions are just overlapping volumes and no seams have
# to line up. Same technique as prototypes/navigation/corridor_generator.gd,
# which is where it was taken from.

## Interior width and height of every corridor, in metres.
##
## Ten, because the creature was built for the tentacle crawler's 9 x 8 m corridor
## and behaves itself in something that size. Everything else here is authored on
## a 5 m grid so the walls of a 10 m tube always land on navmesh cell boundaries.
## Must stay above MIN_PASSAGE_WIDTH; the prototype warns at startup if it does
## not.
const CORRIDOR_WIDTH := 10.0

## How thick the hull around a tunnel is, in metres. Thick enough that the bake's
## passage raycast between two adjacent cell centres cannot miss it.
const WALL_THICKNESS := 1.0

## Junctions, named so the paths below read as a map rather than as coordinates.
## Every one of them is a full-width crossing of two 10 m tubes: there are no
## hatches, doorways or squeezes anywhere in this network, on purpose.

## Trunk meets the mid branch. Three ways out, and the hub of both loops.
const JUNCTION_MID := Vector3(0.0, 0.0, 0.0)
## Where the lower loop comes back to the trunk. Three ways out.
const JUNCTION_LOOP_RETURN := Vector3(0.0, 0.0, 35.0)
## Mid branch, lower loop and the long descent all meet. Three ways out.
const JUNCTION_FAR := Vector3(40.0, 0.0, 0.0)
## Foot of the vertical shaft, at the far end of the trunk.
const JUNCTION_SHAFT_FOOT := Vector3(0.0, 0.0, -45.0)
## Head of that shaft, where the upper deck starts.
const JUNCTION_SHAFT_HEAD := Vector3(0.0, 30.0, -45.0)
## Far end of the upper deck, where the descent begins.
const JUNCTION_UPPER_FAR := Vector3(40.0, 30.0, -45.0)

## The network, as runs of waypoints. About 350 m of corridor in total.
##
## Two loops share the mid branch, so there are always two ways round and the
## creature can arrive from a direction you are not watching. The shaft exists to
## make the wall navmesh earn itself: getting from the upper deck to the trunk
## means crawling down thirty metres of vertical wall.
const CORRIDOR_PATHS := [
	# The trunk. Player at the north end, ninety metres of it.
	[Vector3(0.0, 0.0, 45.0), JUNCTION_SHAFT_FOOT],
	# Mid branch, running east off the middle of the trunk.
	[JUNCTION_MID, JUNCTION_FAR],
	# Lower loop: back from the far junction to the trunk.
	[JUNCTION_FAR, Vector3(40.0, 0.0, 35.0), JUNCTION_LOOP_RETURN],
	# Upper loop: shaft up from the trunk's south end, along the upper deck, and
	# a long descent back down to the far junction.
	[JUNCTION_SHAFT_FOOT, JUNCTION_SHAFT_HEAD],
	[JUNCTION_SHAFT_HEAD, JUNCTION_UPPER_FAR],
	[JUNCTION_UPPER_FAR, Vector3(40.0, 0.0, -45.0), JUNCTION_FAR],
]
#endregion

#region Navigation mesh
#
# The creature crawls surfaces, so it needs a navmesh on the walls and the ceiling
# as well as the floor. Recast bakes against an up vector and cannot produce those
# in one pass, so the mesh is assembled by hand: flood the open space with a grid,
# then put a quad on every face where an open cell meets a solid one.
#
# Grid-based rather than per-surface, and that is what makes junctions work. Cut
# each wall on a grid of its own and no two surfaces agree where their shared edge
# is subdivided, so a T-junction comes out as four rectangles that touch and
# cannot be crossed. Here every quad corner is a point on one global lattice, so
# anything that meets, welds.

## Edge length of one navmesh cell, in metres. Divides CORRIDOR_WIDTH exactly, so
## tunnel walls land on cell boundaries instead of a cell's width away from them.
const NAVMESH_CELL := 2.5

## Radius of the sphere that decides whether a cell is open space, in metres.
## Comfortably under half a cell, so a cell whose centre sits the minimum 1.25 m
## off a wall still reads as open.
const NAVMESH_OPENNESS_RADIUS := 0.45

## Which physics layers the bake probes against. Hull only, which is everything
## the corridor generator builds.
const NAVMESH_PROBE_MASK := 1

## Quantisation the navigation map hashes polygon edges with. Must match the map's
## own cell size or adjacent quads stop sharing edges and the mesh falls apart
## into islands.
const NAVMESH_CELL_SIZE := 0.25

## Hard stop on the flood fill. A leak through a wall would otherwise fill the
## entire bounding volume; this turns that into a warning instead of a hang.
const NAVMESH_MAX_CELLS := 40000
#endregion

#region Follower
#
# The chain is: ChaseTarget picks the point on the navmesh nearest the player,
# ChaseTargetFollower walks the navmesh to it, and the creature leashes to the
# follower exactly as it leashes to a human flying a MarkerPilot. Nothing on the
# creature knows which of the two it has.

## Metres per second the follower travels at. This is the ceiling on how fast the
## creature can be dragged, so it is the first number to reach for when the chase
## feels wrong in either direction.
const FOLLOWER_SPEED := 7.0

## How fast the follower converges on its commanded velocity, and how fast it
## stops, both 1/s. Brake is lower than accel for the same reason MarkerPilot's
## is: a marker that halts instantly snaps the creature's leash taut, which reads
## as a hitch in the creature rather than as a stop.
const FOLLOWER_ACCEL := 10.0
const FOLLOWER_BRAKE := 8.0

## Metres of clearance the follower keeps from the hull, and the layers it looks
## for. Inherited wholesale from MarkerPilot. It doubles as the distance the
## marker aims off the navmesh, so the two never disagree.
const FOLLOWER_CLEARANCE := 1.5
const FOLLOWER_CONTAINMENT_MASK := 1

## Seconds between path recalculations. The player moves continuously and the
## navmesh does not, so this trades how stale the path is against how often A*
## runs across a few thousand polygons.
const FOLLOWER_REPATH_INTERVAL := 0.35

## How close the follower must get to a path corner before aiming at the next one,
## and to the destination before it considers itself arrived. Both metres.
const FOLLOWER_PATH_DESIRED_DISTANCE := 2.0
const FOLLOWER_TARGET_DESIRED_DISTANCE := 2.5

## Seconds between reprojections of the player onto the navmesh. Cheaper than a
## repath and it only feeds one, so it runs more often.
const TARGET_REFRESH_INTERVAL := 0.2
#endregion

#region Creature
#
# Overrides pushed onto the instanced crawler.tscn. Everything not listed here
# keeps the value that prototype ships with.

## Top speed in m/s, down from the 30 it was tuned to for a 244 m corridor.
const CREATURE_MAX_SPEED := 9.0

## Metres the creature may fall behind the marker before the leash pulls at all.
##
## Down from the shipped 4.0, and this is the number that decides whether the
## creature can ever actually reach you. The chain of standoffs is: you float in
## the middle of a 10 m corridor, so the nearest navmesh is 5 m away; the marker
## rides FOLLOWER_CLEARANCE off that; and the creature is allowed to trail this
## far behind the marker. Add them up and that is how close it gets before it
## stops closing. At the shipped slack it settled six metres off and hovered there
## forever - it arrived, and then could not touch you.
const CREATURE_LEASH_SLACK := 1.2

## How far off the nearest surface the creature tries to hold itself, in metres.
##
## This is the number CORRIDOR_WIDTH has to be built around - see
## MIN_PASSAGE_WIDTH. Down from the shipped 4.2 so the creature hugs walls rather
## than floating down the middle of the tube, which is the whole point of a
## wall-crawler, and which also buys margin in the 10 m corridors.
const CREATURE_PROBE_COMFORT := 3.2

## The narrowest passage the creature can actually use, in metres.
##
## Twice its comfort distance, and the number the whole level is built around. At
## anything less the creature is inside CREATURE_PROBE_COMFORT of two opposite
## walls at once, the two pushes fight rather than cancel, and it stalls in the
## opening - which is exactly what the 5 m hatch in the first version of this
## prototype did to it. A floor, not a target: it still needs room to turn.
const MIN_PASSAGE_WIDTH := 2.0 * CREATURE_PROBE_COMFORT

## Which layers the creature's body probe and its tentacles query.
##
## Hull only. Both default to hull|prop, and in THIS project layer 2 is the
## player - so left alone the creature would swerve to avoid you as though you
## were a wall, and its tentacles would try to take a grip on you. The second one
## is arguably a better game than the one being prototyped here, but it is not the
## one being prototyped here.
const CREATURE_PROBE_MASK := 1
const CREATURE_TENTACLE_MASK := 1

## Where the creature starts: the middle of the upper deck, as far from the player
## as the network reaches.
##
## Up there on purpose. Reaching you means crawling thirty metres down a vertical
## shaft and then the length of the trunk, so the first run proves both that the
## navmesh connects around corners and that the creature can hold a route through
## several junctions without stalling in one.
const CREATURE_SPAWN := Vector3(20.0, 30.0, -45.0)

## Where the follower starts. Just off the upper deck's floor, under the creature,
## so the leash begins slack instead of yanking on frame one.
const FOLLOWER_SPAWN := Vector3(20.0, 26.5, -45.0)
#endregion

#region Creature light
#
# The corridors are lit by your helmet lamp and the module, and fog closes them
# down at 30 m. Unlit, the creature is invisible until it is about ten metres
# away, which is a fine horror game and a hopeless tuning environment. This is the
# switch between the two: set the energy to zero for the real test.

## Violet, so it is never confused with the module's cool blue or the helmet
## lamp's warm white. Whatever else is happening, you always know which light you
## are looking at.
const CREATURE_LIGHT_COLOR := Color(0.72, 0.42, 0.95)
const CREATURE_LIGHT_RANGE := 14.0
const CREATURE_LIGHT_ENERGY := 1.1
const CREATURE_LIGHT_ATTENUATION := 1.5

## Shadows off. The renderer is GL Compatibility and this light is attached to a
## creature made of 141 moving nodes.
const CREATURE_LIGHT_SHADOWS := false
#endregion

#region Cave acoustics
#
# Everything CaveReverbBus builds, plus the one setting on the creature's own
# audio that decides whether any of it can be heard at a distance.
#
# THE ROOM IS THE POINT. These corridors are 350 m of sealed stone tube and the
# thud is the only sound in them, so the reverb is not polish - it is the only
# thing in the audio that says how big the space is. The target is a slapback you
# can COUNT and then a long dark tail, not a smooth wash and not a roar.

## Name of the bus the creature plays on, and the bus it sends into. Sending to
## SFX rather than to Master is what keeps the options-menu volume slider in
## charge of it - see CaveReverbBus.
const CAVE_BUS := &"CaveSFX"
const CAVE_SEND_BUS := &"SFX"

## Trim on the cave bus, in dB. Adding a wet signal to a dry one adds loudness,
## and this is what puts the thuds back where they sat before the reverb existed
## so turning the cave on is not also turning the creature up.
const CAVE_BUS_VOLUME_DB := -3.0

## The two discrete returns, in milliseconds and dB.
##
## 220 ms is about 75 m of travel, which is the trunk - the first slap is the far
## end of the corridor answering. The second is roughly double and much quieter,
## which is what stops the pair reading as a rhythm of its own. Panned apart
## because a return arriving from the same place as the source is the one thing
## that sounds like an effect rather than like a room.
const CAVE_DELAY_TAP1_MS := 220.0
const CAVE_DELAY_TAP1_DB := -6.0
const CAVE_DELAY_TAP1_PAN := -0.3
const CAVE_DELAY_TAP2_MS := 430.0
const CAVE_DELAY_TAP2_DB := -12.0
const CAVE_DELAY_TAP2_PAN := 0.35

## The feedback loop behind them: how long the echo train runs.
##
## -14 dB is deliberately low. Eight strands land about two and a half times a
## second, so anything that sustains for long overlaps the NEXT thud and the gait
## turns into a continuous roar. This is the first knob to pull down if the
## double-tap stops being legible.
const CAVE_DELAY_FEEDBACK_MS := 300.0
const CAVE_DELAY_FEEDBACK_DB := -14.0

## Hz above which each return is rolled off. Stone eats the top end first, so a
## fifth echo should be a boom and not a click.
const CAVE_DELAY_FEEDBACK_LOWPASS_HZ := 3000.0

## The tail. Room size just under maximum and moderate damping give roughly three
## to four seconds - big enough to be a cave, short enough that it has decayed
## before the creature's next pair of strands lands.
##
## Raise CAVE_REVERB_DAMPING first if it builds into a wash.
const CAVE_REVERB_ROOM_SIZE := 0.9
const CAVE_REVERB_DAMPING := 0.3
const CAVE_REVERB_SPREAD := 1.0

## Milliseconds before the tail starts, and how much of it feeds back in. The gap
## is what separates "this room is large" from "this room is reflective": with no
## predelay the tail arrives on top of the transient and just smears it.
const CAVE_REVERB_PREDELAY_MS := 60.0
const CAVE_REVERB_PREDELAY_FEEDBACK := 0.4

## Wet against dry. Both high: the impact has to stay sharp enough to locate,
## while the tail has to be loud enough to be the room rather than a hint of one.
const CAVE_REVERB_DRY := 0.55
const CAVE_REVERB_WET := 0.55

## Fraction of the low end kept out of the tail. Small, but without it the thud's
## own bottom octave rings for four seconds and everything turns to mud.
const CAVE_REVERB_HIPASS := 0.05

## Metres at which a thud has faded to nothing, up from the 40 the crawler ships.
##
## NOT A REVERB SETTING, and the other half of the effect. AudioStreamPlayer3D
## attenuates BEFORE the bus, so at 40 m a thud is silent - dry and wet alike -
## and the cave can then only ever tell you the creature is close. The trunk is
## 90 m, so at 70 the far end of it is audible and you hear the thing coming down
## the corridor before the fog gives it up. That is most of what this was for.
const CREATURE_AUDIO_MAX_DISTANCE := 70.0
#endregion

#region Catch
#
# CrawlerBody has no collider anywhere - kinematic on purpose - so without this the
# creature swims straight through you and the prototype has no fail state and no
# clock.

## Radius in metres of the sphere that counts as caught.
##
## THE CREATURE'S REACH, not its waist. Its torso is 2.15 m across and its
## tentacles throw several metres past that, so being inside five metres of it is
## already being inside the animal. It also has to clear the standoff the chase
## settles at - see CREATURE_LEASH_SLACK - or the catch can never fire at all and
## the prototype has a fail state on paper only.
const CATCH_RADIUS := 5.0

## The catcher sits on layer 3 and watches layer 2. Layer 3 is the bit the tentacle
## crawler prototype reserved for the creature and deliberately left unoccupied;
## this is what it was reserved for.
const CATCH_LAYER := 4
const CATCH_MASK := 2

## Seconds of held breath between being caught and being put back. Long enough to
## read the flash on the HUD.
const CATCH_RESPAWN_DELAY := 1.2
#endregion

#region Spawns

## Where the player starts: the north end of the trunk, the far end of the network
## from the creature.
const PLAYER_SPAWN := Vector3(0.0, 0.0, 40.0)

## Where the module starts, and where R returns it to. Twenty metres down the
## trunk, so it has to be gone and fetched rather than being underfoot.
const MODULE_SPAWN := Vector3(0.0, 0.0, 20.0)
#endregion
