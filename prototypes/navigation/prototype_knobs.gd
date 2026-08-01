class_name PrototypeKnobs
extends RefCounted

## Every tunable value for the navigation prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win
## over whatever is saved in the .tscn files - there is nothing to tweak in the
## inspector, and no exported copy of these that could drift out of sync.

# --- Movement --------------------------------------------------------------

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
const THRUST_ACCELERATION := 10

## Ceiling on drift speed, in metres per second.
const MAX_SPEED := 4.0

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
## INERTIAL only.
const ANGULAR_DRAG := 2.0

## Fraction of drift speed shed per second while stabilizers (Shift) are held.
const LINEAR_STABILIZER_RATE := 4.0

## Fraction of tumble rate shed per second while stabilizers are held.
## INERTIAL only - in DIRECT mode there is no spin to arrest.
const ANGULAR_STABILIZER_RATE := 5.0

## Fraction of speed kept on the frame an impact begins. Lower bites harder.
const COLLISION_ENERGY_RETAINED := 0.6

## Fraction of speed shed per second while scraping along a surface.
const SCRAPE_FRICTION := 1.5

# --- Draw distance ---------------------------------------------------------

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

# --- Corridor dimensions ---------------------------------------------------

## Interior width and height of the tunnel, in metres.
const CORRIDOR_WIDTH := 2.4

## How thick the hull around the tunnel is, in metres.
const WALL_THICKNESS := 0.4

const SPAWN_OBSTACLES := true

## Metres of corridor between protruding wall cubes.
const METRES_BETWEEN_OBSTACLES := 9.0

const OBSTACLE_SIZE := 0.45

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
