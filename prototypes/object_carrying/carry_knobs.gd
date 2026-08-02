class_name CarryKnobs
extends RefCounted

## Every tunable value for the object carrying prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win
## over whatever is saved in the .tscn files - there is nothing to tweak in the
## inspector, and no exported copy of these that could drift out of sync.
##
## The Movement and Draw Distance regions start out matching the navigation
## prototype exactly, so anything that feels different here is the carried
## object and not a retuned suit.

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

## Ceiling on tumble rate in radians per second.
const MAX_ANGULAR_SPEED := 10.0

## Fraction of tumble rate shed per second with no input held at all. This is
## the dial between the two rotation modes: at 0.0 a flick spins you until you
## counter it (raw tumble), and as it climbs the spin dies sooner after you
## stop moving the mouse, approaching DIRECT.
##
## Applies in both modes, because collisions and a loaded grip both put spin on
## the body in DIRECT too.
const ANGULAR_DRAG := 2.0

## Fraction of drift speed shed per second while stabilizers (Shift) are held.
const LINEAR_STABILIZER_RATE := 4.0

## Fraction of tumble rate shed per second while stabilizers are held.
const ANGULAR_STABILIZER_RATE := 5.0

## How much of the into-the-wall speed is thrown back out again on impact.
## 0.0 absorbs the hit dead, 1.0 is a perfect elastic bounce.
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

## The player's mass in kg. It weighs collisions against loose bodies, and it
## is half of the mass ratio that decides whether you move the carried object
## or it moves you - compare it against CARRY_OBJECT_MASS.
const PLAYER_MASS := 90.0
#endregion

#region Draw Distance

## Metres at which fog starts to thicken. Below this you see clearly.
const FOG_DEPTH_BEGIN := 2.0

## Metres at which geometry is fully swallowed by fog. This is the number that
## actually sets how far you can see.
const FOG_DEPTH_END := 30.0

## How sharply fog ramps between begin and end. Higher reads as thicker murk.
const FOG_DENSITY := 1.0

## Hard clip distance in metres. Anything past this is not drawn at all. Keep
## it above FOG_DEPTH_END, or geometry visibly pops out before fog has hidden
## it; startup logs a warning if that gets violated.
const CAMERA_FAR := 50.0

## How far the helmet lamp throws, in metres.
const HELMET_LAMP_RANGE := 40
#endregion

#region Carrying
#
# You do not carry anything in zero g, you hold onto it. Both carry modes are
# a spring between a point on your suit and the point on the object you
# grabbed, and both pull on each end: the object gets an impulse, you get the
# equal and opposite one. Everything about how a load feels comes out of that
# spring and the mass on the far end of it.
#
# Every spring here is specified as a frequency and a damping ratio rather
# than raw stiffness, and the actual stiffness is derived per object from the
# two masses. That keeps these numbers meaningful on their own - "a 2.5 Hz
# wobble, slightly underdamped" - and means changing CARRY_OBJECT_MASS does
# not force a retune.

enum CarryMode {
	## Held at arm's length, right where you grabbed it. The spring has no
	## slack, so the object answers your every move immediately and sits in
	## the middle of your view the whole time.
	GRIP,
	## Roped to a harness point behind you. The line does nothing until it
	## pulls taut, so the object trails well back and stays out of your way,
	## and every correction arrives late and through one axis. It also catches
	## on the hull and bends around it, so where the pull comes from depends on
	## what you have taken the rope past.
	TETHER,
}

## Which mode a fresh run starts in. Either way T switches live, so this is
## only about which one you want to be holding when the scene opens.
const CARRY_MODE := CarryMode.GRIP

## How far the grab ray reaches, in metres. Measured from the eye, so it wants
## to stay short: this is arm's reach, not a tractor beam. Shared by both
## modes - a tether is thrown by hand here, not fired.
const GRAB_RANGE := 2.0

## Natural frequency of the grip spring in hertz. Low is a slack, rubbery hold
## that lets the object trail well behind you; high is a firm clamp that turns
## you and the object into something close to one rigid mass.
const CARRY_SPRING_FREQUENCY := 2.5

## Damping as a fraction of critical. 1.0 pulls the object into place without
## overshooting, below that it swings past and settles, and near 0.0 it
## oscillates on the end of the grip more or less forever.
const CARRY_SPRING_DAMPING_RATIO := 0.6

## Ceiling on grip force in newtons. Nothing should reach it in normal play;
## it is here so a single bad frame - a deep collision, a stall - cannot
## launch either body across the chamber.
const CARRY_MAX_FORCE := 4000.0

## How far the grip can stretch, in metres, before it slips and lets go. This
## is what stops the link reading as a rubber band: yank hard enough, or drive
## the object into something solid hard enough, and you simply lose it.
const CARRY_BREAK_DISTANCE := 1.2

## How strongly grip force applied off your centre of mass twists you. This is
## the main tell that you are loaded - thrust while the object is off to one
## side and it slews your aim around. 0.0 makes the load purely linear.
const CARRY_SPIN_TRANSFER := 1.5

# --- Tether ----------------------------------------------------------------
#
# The same two-body spring, with two changes that account for the whole
# difference in feel. It anchors to a harness point behind you rather than at
# your hands, and it goes completely slack below its length, so it only ever
# pulls and only ever along its own line. The object ends up trailing you at
# TETHER_LENGTH, out of your view until you turn to look for it, and it stops
# answering small corrections at all.

## Length of the line in metres. Below this the tether is limp and exerts
## nothing whatsoever; this is how far back the object settles under tow.
const TETHER_LENGTH := 12

## Where the line is anchored on the suit, in suit-local metres: behind and
## a little below the eye, so the load trails rather than crowds the view.
## Negative z is forward, so the z here wants to be positive.
const TETHER_ANCHOR_OFFSET := Vector3(0.0, -0.25, 0.45)

## Natural frequency of the tether spring in hertz, applied only to the
## stretch past TETHER_LENGTH. Deliberately below CARRY_SPRING_FREQUENCY: a
## rope that snaps taut as hard as a hand grip would defeat the point.
const TETHER_SPRING_FREQUENCY := 1.2

## Damping as a fraction of critical, along the line only. Low leaves the
## object bouncing on the end of the tether after every stop.
const TETHER_SPRING_DAMPING_RATIO := 0.4

## Ceiling on tether force in newtons, for the same reason as CARRY_MAX_FORCE.
const TETHER_MAX_FORCE := 4000.0

## How far past TETHER_LENGTH the line can stretch before it parts, in metres.
## Measured as stretch rather than absolute distance, so it stays meaningful
## if TETHER_LENGTH changes.
const TETHER_BREAK_STRETCH := 1.5

## How strongly tether force twists you. The anchor sits behind your centre of
## mass, so a taut line already tends to swing you around to face away from
## the load; keep this well under CARRY_SPIN_TRANSFER or towing turns into
## fighting your own heading.
const TETHER_SPIN_TRANSFER := 0.6

# --- Rope -------------------------------------------------------------------
#
# The line is a chain of points with segments between them that refuse to
# stretch, simulated in tether_rope.gd. It goes round a pillar because its
# points cannot get inside the pillar, and it comes back off when they are free
# to move again - there is no list of bends and nothing that reasons about
# corners.
#
# Going the long way round costs length out of the same TETHER_LENGTH the
# straight run spends, so a load with metres of slack can pull taut from
# rounding one pillar. If the line parts too readily once draped over
# something, TETHER_BREAK_STRETCH is the knob, not these.

## How far apart the rope's simulated points sit, in metres. This is what the
## rope can wrap: it only bends where it has a point, so the spacing wants to
## be well under the size of the things it should catch on, and it is what a
## corner gets shaved by when the rope goes round one. Halving it doubles the
## work every step, and the count follows TETHER_LENGTH so a longer rope stays
## just as detailed.
const TETHER_ROPE_SEGMENT := 0.2

## Passes of the length constraint per step. A rope under real tension needs
## several to pass the pull all the way down the chain; too few and it stretches
## visibly under a heavy load.
const TETHER_ROPE_ITERATIONS := 12

## Fraction of a rope point's speed shed per second. Nothing damps a rope in
## vacuum, so this is here only to stop the chain ringing after a hard yank.
## At 0.0 the rope keeps every wobble it is ever given.
const TETHER_ROPE_DAMPING := 2.0

## How far a segment may close up, as a fraction of its rest length, before it
## pushes back. Real rope has thickness and will not gather into a point;
## without this the slack all piles into one corner of the chain and a single
## segment is left holding metres of rope in one straight run, which reads as
## the rope ignoring everything it is lying across. 0.0 lets it collapse.
const TETHER_ROPE_SPREAD := 0.85

## How far off a surface a rope point rests, in metres.
##
## This is the margin the rope keeps for itself, and it is what stops the rope
## being drawn inside anything. Lifting a point out of the hull and solving the
## segment lengths pull against each other, and whatever the lengths win back
## comes straight out of this margin: at 0.05 a hand's length of rope ends up
## inside a pillar on a tight turn, at 0.16 it is a few centimetres at worst.
## The cost is that the rope visibly hovers off surfaces rather than lying on
## them, so this is a trade between a rope that floats and a rope that clips.
const TETHER_ROPE_RADIUS := 0.16

## Fraction of the along-the-wall speed a rope point loses when it scrapes.
## 0.0 slides freely round corners, 1.0 sticks where it first touched.
const TETHER_ROPE_FRICTION := 0.4

## Which physics layers the rope collides with. Hull only: a rope that could
## catch on the load it is tied to, or on you, would fight itself.
const TETHER_ROPE_LAYERS := 1
#endregion

#region Chamber
#
# One open room, deliberately plain. There are a few pillars and one wall to
# thread the object through, and that is all the geometry the prototype needs
# - the question here is what the load feels like, not whether you can
# navigate.

## Interior dimensions of the room in metres: wide, tall, deep.
const CHAMBER_SIZE := Vector3(30.0, 14.0, 40.0)

## How thick the hull around the room is, in metres.
const WALL_THICKNESS := 0.6

## Free-standing pillars, as centre and size. They run floor to ceiling so
## there is no way to slip over the top of one while loaded.
const PILLARS := [
	{"center": Vector3(-6.0, 0.0, -6.0), "size": Vector3(1.6, 14.0, 1.6)},
	{"center": Vector3(7.0, 0.0, -3.0), "size": Vector3(1.2, 14.0, 1.2)},
	{"center": Vector3(2.0, 0.0, 8.0), "size": Vector3(2.2, 14.0, 2.2)},
	{"center": Vector3(-9.0, 0.0, 6.0), "size": Vector3(1.2, 14.0, 1.2)},
]

## Round pillars, as centre and radius, floor to ceiling like the square ones.
## Placed opposite a square pillar of about the same width so the two can be
## wrapped back to back: a rope behaves differently against an edge than
## against a curve, and this is how you tell which one you are looking at.
const ROUND_PILLARS := [
	{"center": Vector3(7.0, 0.0, 12.0), "radius": 0.9},
]

## How many flat faces a round pillar is built from. Its collision is those
## same faces, so this is really the size of the corners it still has: keep the
## chord between faces under TETHER_ROPE_SEGMENT or a rope has coarser
## geometry to catch on here than on the square pillars.
const ROUND_PILLAR_SIDES := 32

## How far down the room the divider wall sits, on the z axis.
const DIVIDER_DEPTH := -13.0

## Thickness of the divider wall in metres.
const DIVIDER_THICKNESS := 0.8

## Width and height of the opening through the divider. Generous on purpose:
## the object should fit with room to spare, so a bad approach is a matter of
## momentum rather than of clearance.
const DIVIDER_GAP := Vector2(5.0, 5.0)

## Edge length of the carried object in metres. Big enough that the grab point
## is well off its centre of mass, which is what makes it swing.
const CARRY_OBJECT_SIZE := 1.0

## Mass of the carried object in kg. Against PLAYER_MASS of 90 this is roughly
## four suits: you can move it, but every correction costs you.
const CARRY_OBJECT_MASS := 45.0

## Where the object starts, and where R returns it to. Sits just inside
## FOG_DEPTH_END from PLAYER_SPAWN, so it is dimly visible on the first frame
## rather than having to be hunted down before the prototype can be tested.
const CARRY_OBJECT_SPAWN := Vector3(0.0, 0.0, 0.0)

## Nothing slows down in vacuum, but a little damping stops the object
## wandering the whole chamber after one nudge. Set to 0.0 for true drift.
const CARRY_OBJECT_LINEAR_DAMP := 0.05
const CARRY_OBJECT_ANGULAR_DAMP := 0.05

## Where the player starts, far enough back that the object has to be found
## before it can be grabbed.
const PLAYER_SPAWN := Vector3(0.0, 0.0, 6.0)
#endregion
