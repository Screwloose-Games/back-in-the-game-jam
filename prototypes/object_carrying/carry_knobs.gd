class_name CarryKnobs
extends RefCounted

## Every tunable value for the object carrying prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win
## over whatever is saved in the .tscn files.
##
## THIS FILE IS STILL WHERE A DEFAULT LIVES, and there is still no exported copy
## that could drift out of sync. The few values the tuning panel puts a slider on
## are overridden by carry_settings.tres, which the SAVE button writes - but that
## resource declares its defaults AS these consts and takes its slider bounds the
## same way, so no number is written down twice and RESET means "read this file
## again". Everything without a slider is read straight from here as before.
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

## The player's mass in kg. It weighs collisions against loose bodies, and it is
## half of the mass ratio that decides whether you move the module or it moves
## you - compare it against CARRY_OBJECT_HELD_MASS for hauling and against
## CARRY_OBJECT_MASS for being reeled in on the tether.
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
# You do not carry anything in zero g, you hold onto it. Two things can hold
# onto the module at once and they are independent: your hands (the grip) and
# the line clipped to your harness (the tether). Both are springs between the
# suit and the module, and both pull on each end - the module gets an impulse,
# you get the equal and opposite one.
#
# Every spring here is specified as a frequency and a damping ratio rather than
# raw stiffness, and the actual stiffness is derived per link from the two
# masses. That keeps these numbers meaningful on their own - "a 2.2 Hz wobble,
# nearly critically damped" - and means changing either mass does not force a
# retune. What the masses do change is who moves, and that is the whole
# difference between hauling the module and being anchored to it.

## How far the grab ray reaches, in metres. Measured from the eye, so it wants
## to stay short: this is arm's reach, not a tractor beam. Shared by the hands
## and the tether clip - the line is clipped on by hand here, not fired.
const GRAB_RANGE := 2.0

# --- Grip -------------------------------------------------------------------
#
# Two hands, not one. Each takes its own point on the module and gets its own
# spring, and two springs a shoulder's width apart hold the module square:
# every way the module could turn out of your hands except one shows up as the
# two springs disagreeing, and a pair of opposed pulls is a couple that unwinds
# it. A single anchor can only haul the module's centre about and let it pivot
# freely on the grab point, which is what made a one-handed hold swing.
#
# The one turn two hands cannot hold is a roll about the line running through
# them. GRIP_TWIST_* is the wrist stiffness that holds that one.

## Distance between the hands in metres, straddling the point you aimed at.
## This is the lever the pair of springs works through, so it sets how hard the
## grip resists the module turning in your hands: halve it and the module is
## four times easier to twist. Too wide and a small module ends up held by two
## points hanging in space either side of it.
const GRIP_HAND_SEPARATION := 0.7

## Where the module's centre ends up once it is settled in your hands, in
## suit-local metres. Negative z is forward, so this is out in front and a
## little below the eye. Push it further out and the module stops filling the
## view but gains leverage over your heading.
const GRIP_CARRY_OFFSET := Vector3(0.0, -0.5, -1.5)

## Seconds spent easing from the pose you caught the module in to the carry
## pose. The hands take hold with no tension whatever angle you came in at, and
## this is how long they take to bring it square and in front of you. Short
## enough and taking hold reads as a snatch; at 0.0 the module jumps into place
## the instant you press grab.
const GRIP_SETTLE_TIME := 0.55

## Natural frequency of each hand's spring in hertz. Low is a slack, rubbery
## hold that lets the module trail and wallow; high is a firm clamp that turns
## you and the module into something close to one rigid body. The pair is
## derated so this stays the frequency of the grip as a whole rather than of
## one hand.
const GRIP_SPRING_FREQUENCY := 2.2

## Damping as a fraction of critical. 1.0 brings the module into place without
## overshooting, below that it swings past and settles, and near 0.0 it
## oscillates in your hands more or less forever. Kept high: a heavy module
## that visibly bounces on the way to the carry pose reads as light.
const GRIP_SPRING_DAMPING_RATIO := 0.9

## Ceiling on grip force in newtons, across both hands. Nothing should reach it
## in normal play; it is here so a single bad frame - a deep collision, a stall
## - cannot launch either body across the chamber. Keep it above what the
## springs make at GRIP_BREAK_DISTANCE, or the grip saturates instead of
## letting go.
const GRIP_MAX_FORCE := 20000.0

## How far a hand can be pulled off its hold, in metres, before the grip slips
## and both let go. This is what stops the link reading as a rubber band: yank
## hard enough, or drive the module into something solid hard enough, and you
## simply lose it.
const GRIP_BREAK_DISTANCE := 1.2

## Natural frequency of the wrist spring in hertz, resisting a roll about the
## line through your hands. Below GRIP_SPRING_FREQUENCY because wrists are the
## weakest part of a two-handed hold. 0.0 lets the module spin freely on that
## one axis while staying held on every other.
const GRIP_TWIST_FREQUENCY := 2.0

## Damping as a fraction of critical for the wrist spring.
const GRIP_TWIST_DAMPING_RATIO := 0.9

## Ceiling on wrist torque in newton-metres, for the same reason as
## GRIP_MAX_FORCE.
const GRIP_TWIST_MAX_TORQUE := 8000.0

## How much of the suit's own manoeuvring - thrust, and the stabilizers braking
## - moves you and the module as one body while it is in your hands, from 0.0 to
## 1.0.
##
## At 0.0 it all goes into the suit alone and the module comes along only because
## your hands drag it after you. That is honest, and it is why a burst straight
## up or down pitches you over, and why braking out of one pitches you back: the
## module rides out in front of your centre of mass, so the pull that gets it
## moving, or stops it, arrives on a long lever.
##
## At 1.0 the module gets its own share of the force directly, at its centre, so
## the two of you set off and pull up together and manoeuvring does not turn you.
## What still does is the module swinging, settling into your hands, or fetching
## up against something, which is the part worth feeling.
##
## Either way it costs the same. The force has both masses to shift whichever way
## it is routed, so a load has always made you slower to get going and slower to
## stop - bracing only stops it throwing your aim around while it does.
const GRIP_BRACING := 1.0

## How strongly grip force applied off your centre of mass twists you. This is
## the main tell that you are loaded - let the module swing out to one side and
## hauling it back slews your aim around. 0.0 makes the load purely linear.
const GRIP_SPIN_TRANSFER := 0.5

## The same, for the wrist spring's torque. Well under GRIP_SPIN_TRANSFER: the
## reaction to squaring the module up should be felt, not fought.
const GRIP_TWIST_SPIN_TRANSFER := 0.2

# --- Tether ----------------------------------------------------------------
#
# The same two-body spring, anchored to a harness point behind you rather than
# at your hands, and completely slack below its length, so it only ever pulls
# and only ever along its own line.
#
# Which end of it moves is not set here - it comes out of the mass ratio. The
# module is CARRY_OBJECT_MASS while nobody is holding it, several times what
# the suit weighs, so a taut line reels you in toward the module rather than
# dragging the module after you. That is what makes it an anchor: to get past
# the length of the line you have to unclip, not out-thrust it.

## Length of the line in metres. Below this the tether is limp and exerts
## nothing whatsoever; this is how far back the object settles under tow.
const TETHER_LENGTH := 10.0

## Where the line is anchored on the suit, in suit-local metres: behind and
## a little below the eye, so the load trails rather than crowds the view.
## Negative z is forward, so the z here wants to be positive.
const TETHER_ANCHOR_OFFSET := Vector3(0.0, -0.25, 0.45)

## Natural frequency of the tether spring in hertz, applied only to the
## stretch past TETHER_LENGTH. Deliberately below GRIP_SPRING_FREQUENCY: a
## rope that snaps taut as hard as a hand grip would defeat the point.
const TETHER_SPRING_FREQUENCY := 1.0

## Damping as a fraction of critical, along the line only. High enough that
## reaching the end of the line arrests you and leaves you there; drop it and
## you yo-yo on the end of the rope, which reads as elastic rather than moored.
const TETHER_SPRING_DAMPING_RATIO := 0.1

## Ceiling on tether force in newtons, for the same reason as GRIP_MAX_FORCE.
const TETHER_MAX_FORCE := 8000.0

## How far past TETHER_LENGTH the line can stretch before it parts, in metres.
## Measured as stretch rather than absolute distance, so it stays meaningful
## if TETHER_LENGTH changes.
const TETHER_BREAK_STRETCH := 1.5

## How strongly tether force twists you. The anchor sits behind your centre of
## mass, so a taut line already tends to swing you around to face away from
## the load; keep this well under GRIP_SPIN_TRANSFER or being reeled in turns
## into fighting your own heading.
const TETHER_SPIN_TRANSFER := 0.25

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

## Radius the rope is drawn at, in metres. Purely how it looks; the simulation
## knows nothing about it.
##
## Deliberately under TETHER_ROPE_RADIUS, which is the radius the rope actually
## behaves as. Drawing it that thick would make it lie exactly on the surfaces
## its points are held off, but it would also be a third of a metre across -
## wider than the module is by a third, and thicker than its own links are long,
## so it would pinch through itself at every bend and knot outright where a
## slack rope doubles back. Half a hand's width reads as a heavy tether and
## takes a bend of well over a right angle before it starts to pinch.
##
## What it costs is that the rope floats off surfaces by the difference. That is
## the honest trade here: the drawn rope can lie on things or it can be a rope
## rather than a pipe.
const TETHER_ROPE_DRAW_RADIUS := 0.05

## How many flat faces the drawn rope is built from around its circumference.
## Six is enough for something this thin; the whole rope is rebuilt every frame,
## so this is the one number here with a running cost.
const TETHER_ROPE_DRAW_SIDES := 6

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

## Edge length of the module in metres. It wants to stay comfortably wider than
## GRIP_HAND_SEPARATION, so both hands land on the module rather than out in
## space either side of it.
const CARRY_OBJECT_SIZE := 1.0

## Mass of the module in kg while nobody has hold of it - drifting, or on the
## end of the tether. Against PLAYER_MASS of 90 this is most of seven suits, so
## a taut line moves you about seven times as far as it moves the module, and
## shouldering into the module barely shifts it. This is the number that makes
## the tether an anchor rather than a leash.
const CARRY_OBJECT_MASS := 1000.0

## Mass of the module in kg while it is in your hands, swapped in on grab and
## back out on release.
##
## Physically a cheat, and the reason for it is that one mass cannot serve both
## jobs: heavy enough to be an anchor is heavy enough that you can barely haul
## it, and light enough to haul is light enough to tow around on a string. Read
## it as bracing against the module and using it as a reaction mass rather than
## fighting it at arm's length.
##
## What it buys, against a 90 kg suit thrusting at THRUST_ACCELERATION: your
## thrusters make 900 N, and 900 N into the 290 kg of you and the module comes
## out at about 3.1 m/s^2, so hauling it costs you two thirds of your
## acceleration. Raise it and the module wins more of that argument.
const CARRY_OBJECT_HELD_MASS := 200.0

## Where the object starts, and where R returns it to. Sits just inside
## FOG_DEPTH_END from PLAYER_SPAWN, so it is dimly visible on the first frame
## rather than having to be hunted down before the prototype can be tested.
const CARRY_OBJECT_SPAWN := Vector3(0.0, 0.0, 0.0)

## Nothing slows down in vacuum, but a little damping stops the object
## wandering the whole chamber after one nudge. Set to 0.0 for true drift.
const CARRY_OBJECT_LINEAR_DAMP := 0.05
const CARRY_OBJECT_ANGULAR_DAMP := 0.05

# --- Module lamp ------------------------------------------------------------
#
# The module carries its own light. Held, it sits a metre and a half in front of
# your visor, which is squarely between the helmet lamp and everything you are
# trying to steer around - carrying it unlit means hauling a shadow ahead of you
# down the very corridor you are trying to see. Lit, the load is the reason you
# can see rather than the reason you cannot.
#
# It stays lit whether or not anyone has hold of it, which also makes it
# something you can spot across a dark chamber instead of hunting for.

## Colour of the module's lamp, and of the glow on the module's own faces. One
## value feeds both, so the thing you are carrying always looks like the source
## of the light it is throwing. Cool against the helmet lamp's warm white, so
## the two are told apart at a glance.
const CARRY_OBJECT_LIGHT_COLOR := Color(0.55, 0.72, 0.95)

## How far the module's lamp reaches, in metres. Kept under FOG_DEPTH_END, so
## carrying it lights the room out to about where the fog closes in anyway.
const CARRY_OBJECT_LIGHT_RANGE := 14.0

## Brightness of the module's lamp. Held, this is most of what you see by, so it
## is a bigger lever on how the prototype reads than anything else here.
const CARRY_OBJECT_LIGHT_ENERGY := 2.0

## How sharply the lamp falls off across its range. Higher keeps the light
## gathered close around the module; 1.0 spreads it evenly to the edge.
const CARRY_OBJECT_LIGHT_ATTENUATION := 1.0

## How brightly the module's own faces glow. This throws no light on anything -
## the lamp does that - it is only what keeps the module from reading as a dark
## box sitting in the middle of a room it is supposed to be lighting.
const CARRY_OBJECT_GLOW := 1.6

## Whether the module's lamp casts shadows. Shadows are most of what makes the
## lamp worth having, since a pillar you are about to swing the load into is
## something you see by its shadow long before you see the pillar. They are also
## the expensive half of it, so here is the switch.
const CARRY_OBJECT_LIGHT_SHADOWS := true

## Where the player starts, far enough back that the object has to be found
## before it can be grabbed.
const PLAYER_SPAWN := Vector3(0.0, 0.0, 6.0)
#endregion
