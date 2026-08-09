class_name DrillMovementKnobs
extends RefCounted

## Every tunable value for the navigation prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win
## over whatever is saved in the .tscn files.
##
## THIS FILE IS STILL WHERE A DEFAULT LIVES, and there is still no exported copy
## that could drift out of sync. The few values the tuning panel puts a slider on
## are overridden by navigation_settings.tres, which the SAVE button writes - but
## that resource declares its defaults AS these consts and takes its slider bounds
## the same way, so no number is written down twice and RESET means "read this
## file again". Everything without a slider is read straight from here as before.

#region Movement

enum RotationMode {
	## Mouse and roll input map straight onto this frame's rotation. Snappy and
	## familiar; the tumble readout stays at zero because nothing accumulates.
	DIRECT,
	## Mouse and roll input accelerate a spin that persists between frames.
	## How long it persists is set by ANGULAR_DRAG, which dials this mode from
	## raw free tumble all the way back toward DIRECT.
	INERTIAL,
}

const ROTATION_MODE := RotationMode.INERTIAL

## Thruster strength in metres per second squared, per axis.
const THRUST_ACCELERATION := 8.0

## Ceiling on drift speed, in metres per second.
const MAX_SPEED := 2.0

## Multiplier on THRUST_ACCELERATION while sprint (Shift) is held.
const SPRINT_ACCELERATION_MULTIPLIER := 2.0

## Multiplier on MAX_SPEED while sprint is held.
const SPRINT_SPEED_MULTIPLIER := 2.5

## How fast the speed ceiling falls back to MAX_SPEED after sprint is released,
## in metres per second squared. The ceiling rises the instant sprint is held,
## so this only governs the way back down: without it, letting go of Shift at
## full sprint would snap you to MAX_SPEED in a single frame. Raise it far above
## THRUST_ACCELERATION for that hard snap.
const SPRINT_FALLOFF_RATE := 2.0

## Radians of rotation per pixel of mouse movement.
const MOUSE_SENSITIVITY := 0.0022

## Q/E roll speed in radians per second (DIRECT), or its acceleration
## (INERTIAL).
const ROLL_RATE := 2.0

## Gain applied to aim input when it feeds angular velocity. INERTIAL only -
## has no effect in DIRECT mode.
const ANGULAR_ACCELERATION := 6.0

## Ceiling on tumble rate in radians per second. INERTIAL only.
const MAX_ANGULAR_SPEED := 10.0

## Fraction of tumble rate shed per second with no input held at all. This is
## the dial between the two rotation modes: at 0.0 a flick spins you until you
## counter it (raw tumble), and as it climbs the spin dies sooner after you
## stop moving the mouse, approaching DIRECT. Spin decays to roughly 5% of its
## peak after 3 / ANGULAR_DRAG seconds, so 3.0 settles in about a second.
##
## Applies in both modes, because collisions put spin on the body in DIRECT
## too. At 0.0 an impact leaves you tumbling until you counter it or hit the
## stabilizers, in either mode.
const ANGULAR_DRAG := 1.0

## Fraction of drift speed shed per second while stabilizers (R) are held.
const LINEAR_STABILIZER_RATE := 4.0

## Fraction of tumble rate shed per second while stabilizers are held.
## INERTIAL only - in DIRECT mode there is no spin to arrest.
const ANGULAR_STABILIZER_RATE := 5.0

## How much of the into-the-wall speed is thrown back out again on impact.
## 0.0 absorbs the hit dead, 1.0 is a perfect elastic bounce. This is what
## makes a wall deflect you instead of just taxing your speed.
const COLLISION_RESTITUTION := 0.35

## How much of the along-the-wall speed is scrubbed off on impact. 0.0 is a
## frictionless skate along the surface, 1.0 stops the sliding dead.
const COLLISION_FRICTION := 0.25

## How strongly the friction at a contact point twists the body. This is what
## makes a glancing blow set you spinning rather than sliding off level. 0.0
## disables impact spin entirely.
const COLLISION_SPIN_TRANSFER := 1.5

## Fraction of speed shed per second while still scraping along a surface
## after the initial impact has been resolved.
const SCRAPE_FRICTION := 1.5

## The player's mass in kg, used only to weigh collisions against loose debris.
## Compare it against LIGHT_DEBRIS_MASS and HEAVY_DEBRIS_MASS: an object at
## this mass trades momentum with you evenly, lighter ones get swatted away,
## heavier ones push you off course.
const PLAYER_MASS := 90.0
#endregion

#region Draw Distance

## Metres at which fog starts to thicken. Below this you see clearly.
const FOG_DEPTH_BEGIN := 2.0

## Metres at which geometry is fully swallowed by fog. This is the number that
## actually sets how far you can see - raise it to open the corridor up, lower
## it to close in.
const FOG_DEPTH_END := 10.0

## How sharply fog ramps between begin and end. Higher reads as thicker murk.
const FOG_DENSITY := 1.0

## Hard clip distance in metres. Anything past this is not drawn at all. Keep
## it above FOG_DEPTH_END, or geometry visibly pops out before fog has hidden
## it; startup logs a warning if that gets violated.
const CAMERA_FAR := 20.0

## How far the helmet lamp throws, in metres.
const HELMET_LAMP_RANGE := 14.0
#endregion

#region Map Geometry
# --- Corridor dimensions ---------------------------------------------------

## Interior width and height of the tunnel, in metres.
const CORRIDOR_WIDTH := 2.4

## How thick the hull around the tunnel is, in metres.
const WALL_THICKNESS := 0.4

# --- Spikes ----------------------------------------------------------------
#
# Boxes jutting inward off the tunnel walls at assorted lengths and angles.
# They are terrain only - nothing about them hurts you, they just make a
# corridor awkward to thread. A spike at SPIKE_MIN_LENGTH reads as a small
# stub cube; one at SPIKE_MAX_LENGTH is a proper spar to steer around.

const SPAWN_SPIKES := true

## Fixed so the same map comes back every run. Change it to roll a new field
## of spikes; the corridor layout itself does not move.
const SPIKE_RANDOM_SEED := 20260731

## How often along a corridor a spike is considered, in metres. Smaller means
## denser clusters are possible and generation costs more.
const SPIKE_SAMPLE_STEP := 0.6

## Chance of placing a spike at a sample point in the emptiest stretches.
const SPIKE_SPARSE_CHANCE := 0.02

## Chance of placing one in the thickest clusters.
const SPIKE_DENSE_CHANCE := 0.32

## How quickly density swings between sparse and dense along the corridor.
## Lower spreads the clusters out into long stretches, higher chops the map
## into short alternating patches.
const SPIKE_CLUSTER_FREQUENCY := 0.06

const SPIKE_MIN_LENGTH := 0.4
const SPIKE_MAX_LENGTH := 1.5

const SPIKE_MIN_THICKNESS := 0.18
const SPIKE_MAX_THICKNESS := 0.5

## Maximum lean away from straight-out-of-the-wall, in degrees.
const SPIKE_MAX_TILT_DEGREES := 45.0

## How far a spike's base is buried in the wall so it never floats free of it.
const SPIKE_EMBED_DEPTH := 0.15

# --- Debris ----------------------------------------------------------------
#
# Loose objects drifting in the corridors, as opposed to the spikes, which are
# immovable terrain. Two grades: light junk that barely registers when you hit
# it, and heavy masses that will genuinely redirect you but still give way.
#
# The player's response to hitting one is a proper two-body impulse exchange,
# so these masses are what decide the feel - a debris mass well under
# PLAYER_MASS gets swatted aside, one well over it shoves you off course.

const SPAWN_DEBRIS := true

## Metres of corridor between debris considerations.
const DEBRIS_SAMPLE_STEP := 2.0

const LIGHT_DEBRIS_CHANCE := 0.8
const LIGHT_DEBRIS_SIZE := 0.32
const LIGHT_DEBRIS_MASS := 4.0

const HEAVY_DEBRIS_CHANCE := 0.16
const HEAVY_DEBRIS_SIZE := 0.85
const HEAVY_DEBRIS_MASS := 220.0

## Nothing slows down in vacuum, but a little damping stops loose objects
## wandering the whole map after one nudge. Set to 0.0 for true drift.
const DEBRIS_LINEAR_DAMP := 0.15
const DEBRIS_ANGULAR_DAMP := 0.1

## Speed and spin debris starts with, so the corridors are not static.
const DEBRIS_INITIAL_DRIFT := 0.25
const DEBRIS_INITIAL_SPIN := 0.4

# --- Corridor layout -------------------------------------------------------
#
# The map is a list of paths, each an open polyline of waypoints joined by
# straight tunnel spans. Angles are whatever the coordinates imply, so 45s and
# odd angles cost nothing. Any waypoint two paths share becomes a junction
# automatically - that is how branches and loops are declared.
#
# The junctions are named because their coordinates must match exactly between
# the paths that meet there.

## Trunk meets the first dead-end branch. Three ways out.
const JUNCTION_FIRST_BRANCH := Vector3(0, 0, -14)

## Trunk meets the foot of the vertical shaft. Three ways out.
const JUNCTION_SHAFT_FOOT := Vector3(10, 0, -24)

## Where the upper loop comes back down to the trunk. Three ways out, and the
## point that makes the map genuinely ambiguous: you can arrive here from two
## directions and cannot tell which without tracking your own route.
const JUNCTION_LOOP_RETURN := Vector3(24, 0, -24)

## Upper level branch point. Three ways out.
const JUNCTION_UPPER := Vector3(10, 10, -34)

const CORRIDOR_PATHS := [
	# Trunk: long approach, a 45 right, then a straight run east.
	[Vector3(0, 0, 0), JUNCTION_FIRST_BRANCH, JUNCTION_SHAFT_FOOT, JUNCTION_LOOP_RETURN],
	# Dead end west, kinked 45 so you cannot see the cap from the junction.
	[JUNCTION_FIRST_BRANCH, Vector3(-11, 0, -14), Vector3(-18, 0, -21)],
	# The loop: straight up a shaft, along the upper level, then a 45 descent
	# back onto the trunk. Walking it returns you to a corridor you have
	# already seen, facing the wrong way.
	[
		JUNCTION_SHAFT_FOOT,
		Vector3(10, 10, -24),
		JUNCTION_UPPER,
		Vector3(24, 10, -34),
		JUNCTION_LOOP_RETURN,
	],
	# Upper dead end, another 45.
	[JUNCTION_UPPER, Vector3(2, 10, -42)],
	# Final spur off the loop return, ending on a deliberately odd angle so it
	# does not read as part of the 45/90 grammar. The end marker sits here.
	[JUNCTION_LOOP_RETURN, Vector3(24, 0, -10), Vector3(32, 0, -4)],
]
#endregion
