class_name PowerKnobs
extends RefCounted

## Every optical and power value for the power and lighting prototype, in one
## place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win over
## whatever is saved in the .tscn files - there is nothing to tweak in the
## inspector, and no exported copy of these that could drift out of sync.
##
## THIS FILE OUTRANKS imported/movement_knobs.gd. That one was copied whole from
## the object carrying prototype and still carries a Draw Distance region and a
## CARRY_OBJECT_LIGHT_* set; the suit applies them to itself in its own _ready,
## and power_and_lighting_prototype.gd overwrites them from here immediately
## after. Movement, the grip, the tether and the chamber are still that file's;
## everything you can see by is this one's.

#region What is switched on
#
# The prototype answers one question at a time, and everything that answers a
# different one is switched off here rather than deleted. All of it works, all of
# it is wanted back, and the numbers behind each part are still in their own
# regions below.
#
# THE QUESTION NOW IS THE CUBE'S LAMP: the same questions the helmet lamp has
# already answered - how bright, how far, what colour, what shadows - and then how
# it fails, which the helmet lamp has answered too. Everything about the suit's
# light is settled and off the panel.
#
# The *_ENABLED switches decide what runs. The *_TUNING_ENABLED ones decide only
# what the panel still offers, and turning one off is how an answered question
# stops being re-opened every time the panel is opened for something else.

## Whether the batteries do anything.
##
## ON: the suit leaks charge whatever it is doing, gets it back from the cube
## through a clipped tether, and cranking is the only way to put anything into the
## cube. The suit bar, the cube's own gauge and the state buttons come with it,
## and F becomes one key doing two verbs - tap to grip, hold to crank.
const POWER_ENABLED := true

## Whether the lamps dim and flicker as their battery falls.
##
## ON, and it governs BOTH lamps. The suit's answer is settled - see the two SUIT
## point lists below - and the cube's is the open half.
const LAMP_RESPONDS_TO_POWER := true

## Whether the cube lights the room and glows.
##
## ON at last. There are two lights in the room now, which is exactly what made
## the helmet lamp impossible to judge and exactly why it was judged first: it is
## a fixed thing to tune the new one against.
const CUBE_LIGHT_ENABLED := true

## Whether the panel still offers the helmet lamp's shape, and the fog and ambient
## it is seen through. OFF - see the Suit optics, Draw distance and Shadow
## artefacts regions.
const SUIT_BEAM_TUNING_ENABLED := false

## Whether the panel still offers the helmet lamp's dim and flicker curves. OFF -
## the two SUIT point lists and SUIT_LAMP_MIN_RANGE_METRES are the answer.
const SUIT_RESPONSE_TUNING_ENABLED := false

## Whether the panel offers the cube's lamp: its optics and its two curves. ON.
## This is the step.
const CUBE_TUNING_ENABLED := true

## Whether the panel still offers the drain and charge rates. OFF - the Suit power
## and Cube power regions are settled.
##
## THE STATE BUTTONS ARE NOT PART OF THIS and stay up whatever it says. They put a
## battery straight where you want to look at it, and a cube lamp being tuned for
## how it dies needs that more than anything else on the panel.
const POWER_TUNING_ENABLED := false
#endregion

#region Suit optics
#
# What the helmet lamp looks like at FULL power. Every one of these is the top of
# a range the lamp falls down as the suit drains - see the Lamp response region.
#
# SETTLED, and no longer on the panel. These were tuned against the room with
# nothing else in it emitting, and they are what the rest of the prototype is now
# judged under. Change one here and everything after it moves with it.

## Brightness of the helmet lamp at full charge.
const HELMET_LAMP_ENERGY := 3.5

## Width of the helmet lamp cone in degrees, as a HALF-ANGLE - so 45 is a
## 90-degree cone. Wider than the 35 the suit ships with: a narrow beam lights a
## disc directly ahead and leaves the walls of a room this size unlit, which
## makes every dimming knob below read as "the room went dark" rather than as
## "the lamp got weaker".
const HELMET_LAMP_ANGLE := 45.0

## How sharply the beam falls off from its centre to the edge of the cone. Low
## is a flat disc of light with a hard rim; high is a hot spot that fades out.
## Enough of a hot spot here to read as a lens rather than a projector, while the
## cone stays something you can plainly aim.
const HELMET_LAMP_ANGLE_ATTENUATION := 0.75

## How sharply the beam falls off with distance. The linear fall: the far half of
## the throw goes on doing work instead of being handed to the fog early.
const HELMET_LAMP_ATTENUATION := 1.0

## Colour of the helmet lamp. Warm white, against the cube's cool blue, so which
## light you are seeing by is never in question - which matters most exactly when
## the suit is nearly out and the two are comparable in strength.
const HELMET_LAMP_COLOR := Color(1.0, 0.96, 0.89)

## Whether the helmet lamp casts shadows. On: shadows are most of what makes a
## lamp worth having in a room full of pillars, and a dimming lamp with no
## shadows just reads as the exposure coming down.
const HELMET_LAMP_SHADOWS := true

## Near-black. There is no sky in here and no directional light, so this is the
## floor the whole room falls to once both lamps are out.
const AMBIENT_ENERGY := 0.02
#endregion

#region Draw distance

## Metres at which fog starts to thicken. ZERO: the murk begins at the visor and
## ramps outward from there, rather than leaving a clear shell around the suit
## that everything close in sits inside.
const FOG_DEPTH_BEGIN := 0.0

## Metres at which geometry is fully swallowed by fog. This is the number that
## actually sets how far you can see.
const FOG_DEPTH_END := 30.0

## How sharply fog ramps between begin and end. Higher reads as thicker murk.
const FOG_DENSITY := 1.0

## How far past the fog the lamp throws, and how far past that the camera clips.
##
## FOG_DEPTH_END IS THE ONLY ONE OF THE THREE ANYONE SHOULD SET, and the reason
## is the same one tunnel_knobs.gd gives: past the lamp's throw the rock is lit
## by AMBIENT_ENERGY alone and reads as black however clear the air is, and a
## clip plane inside the fog pops geometry out before the fog has hidden it.
## Deriving the other two makes both invariants structural.
##
## THE LAMP MARGIN IS ZERO RATHER THAN SLACK. A spot light's range is also the far
## plane of its shadow map, and the shorter that plane is the more depth precision
## every shadow test gets - see the Shadow artefacts region. Geometry at the fog's
## end is fully swallowed by it, so the metres handed back cost nothing anyone can
## see. Below zero it would start trading against the invariant above.
const VIEW_LAMP_MARGIN := 0.0
const VIEW_CLIP_MARGIN := 8.0

## How far the helmet lamp throws at full charge, in metres. Derived.
const HELMET_LAMP_RANGE := FOG_DEPTH_END + VIEW_LAMP_MARGIN

## Hard clip distance. Derived.
const CAMERA_FAR := FOG_DEPTH_END + VIEW_CLIP_MARGIN
#endregion

#region Shadow artefacts
#
# The GL Compatibility renderer filters shadows far more narrowly than Forward+
# does, so the shadow map's own texel grid shows through as parallel stripes
# across any flat surface a lamp is pointed at - see shadow_bug.png. These two are
# what hold that off, and both go onto EVERY lamp in the room rather than onto one
# of them: the cause is the renderer, not the lamp, so a value tuned on the helmet
# lamp and read back off the cube would be answering a different question.

## Whether lamps render back faces into their shadow maps instead of front faces.
##
## Self-shadowing then lands on the surfaces turned away from the lamp, which are
## the ones nothing is looking at. It is only correct for closed solid casters,
## and the chamber is CSG solid; the thin and single-sided things in here - the
## tether line, the cube's gauge segments - already cast no shadow at all.
const SHADOW_REVERSE_CULL := true

## How far a shadow lookup is pushed along the surface normal before it is tested,
## in shadow-map texels.
##
## The knob that addresses the striping directly: the offset scales with how much
## depth a single texel spans, which is what goes wrong on a wall seen nearly
## edge-on - and a helmet lamp sees every wall that way, because it points wherever
## the camera points. Too high and shadows pull away from the foot of a pillar.
##
## Left at Godot's own default. With reverse cull on and the lamp's range pulled
## back to exactly the fog, the stripes are already off the walls, so there is
## nothing here to buy and the pulling-away is the only thing more would cost.
const SHADOW_NORMAL_BIAS := 2.0
#endregion

#region Suit power
#
# SETTLED, and no longer on the panel. A suit charge is thirty-three seconds and a
# tether pays it back in eleven: a much tighter loop than these started at. Being
# out of power is meant to be something that keeps happening to you rather than
# something you plan around once an expedition.

## How much charge the suit battery holds. The unit is arbitrary and only the
## ratios below matter, so it is set to 100 and every readout is a percentage.
const SUIT_CAPACITY := 100.0

## How full the suit starts, 0 to 1. Not 1.0 on purpose: a prototype that opens
## at full charge spends its first stretch showing you nothing.
const SUIT_START_FRACTION := 0.6

## Charge the suit loses per second, always, cube or no cube. At 100 capacity
## this is thirty-three seconds from full to dead.
const SUIT_DRAIN_PER_SECOND := 3.0

## Charge per second the suit pulls out of a tethered cube.
##
## MUST EXCEED SUIT_DRAIN_PER_SECOND or clipping in does nothing but slow the
## dying down, and the tether stops being worth the 10 m leash. The margin is
## what decides whether topping up is something you do while working or something
## you stop and wait for; at 12 against 3 the suit nets 9/s, so a full recharge
## from empty is about eleven seconds of being moored.
const SUIT_CHARGE_PER_SECOND := 12.0
#endregion

#region Cube power
#
# SETTLED, and no longer on the panel, except CUBE_IDLE_DRAIN_PER_SECOND - which
# has never been anything but zero and is a question nobody has opened yet.

## How much charge the cube holds. Six suits' worth: enough that the cube is the
## thing you plan around rather than the thing you watch, and few enough that
## cranking is not theoretical.
const CUBE_CAPACITY := 600.0

## How full the cube starts, 0 to 1.
const CUBE_START_FRACTION := 0.5

## Charge the cube loses per second on its own. ZERO: the cube spends power only
## on the suit. Left here as a knob rather than removed, because "life support
## running costs something" is the obvious next question this prototype poses and
## turning it on should be one number, not a code change.
const CUBE_IDLE_DRAIN_PER_SECOND := 0.0

## Charge per second cranking puts into the cube. Fifteen seconds fills an empty
## cube, and one second of it is worth about thirteen seconds of light.
##
## ABOVE SUIT_CHARGE_PER_SECOND, so cranking is the fastest that power moves
## anywhere in this system. That makes it a way out of trouble rather than a
## penance - which means the cost of cranking has to come from the animation and
## from having to stop and do it, because it is not coming from the rate. Stands
## in for a proper cranking verb later.
const CRANK_PER_SECOND := 40.0
#endregion

#region Lamp response
#
# How a lamp answers the battery behind it. Shared shape, separate points for the
# suit and the cube, so the two can be made to fail differently.
#
# THE DIMMING IS A CURVE, NOT A FORMULA. It used to be an exponent on the charge
# fraction, and one number is one family of shapes - the thing it could not
# express is the one people reach for first, a lamp that holds, sags, holds again
# and then gives out. The points below seed a Curve the panel edits in place while
# the game runs: charge fraction across, fraction of full brightness up.
#
# ITS VALUE AT ZERO IS THE NO-POWER BRIGHTNESS. There is no separate floor knob
# any more - drag the left-hand end down to nothing for a lamp that simply goes
# out, or leave it just off the bottom for a dark reserve you can still work by.

## The suit's dimming curve. SETTLED, and no longer on the panel.
##
## Three stretches, and the shape is the answer: full brightness down to about
## three quarters of a battery, so most of a charge shows you nothing; a long
## gentle sag through the middle; then a cliff in the last seventh, from two
## thirds brightness down to the ember at the bottom. The warning is late and
## short, which is the frightening version.
const SUIT_DIM_POINTS: Array[Vector2] = [
	Vector2(0.000, 0.120),
	Vector2(0.139, 0.655),
	Vector2(0.385, 0.917),
	Vector2(0.751, 1.000),
	Vector2(1.000, 1.000),
]

## The cube's, still a seed rather than an answer - CUBE_TUNING_ENABLED has this
## one on the panel.
const CUBE_DIM_POINTS: Array[Vector2] = [
	Vector2(0.0, 0.08),
	Vector2(0.5, 0.48),
	Vector2(1.0, 1.0),
]

## How far the helmet lamp still throws on a flat battery, in metres.
##
## The other half of the no-power lamp, and the half that is easy to forget. It
## is not on the dim curve because it is a separate axis: how much the world
## shrinks against how much it darkens. Left alone, a dim lamp goes on reaching
## the far wall and the only thing that has changed is the exposure. A reserve
## light that reads as a reserve light is dim AND short.
##
## In metres rather than as a fraction because metres are what was judged - how
## much room is left in front of you - and they stay true if the throw moves.
const SUIT_LAMP_MIN_RANGE_METRES := 14.0
const SUIT_LAMP_MIN_RANGE_FRACTION := SUIT_LAMP_MIN_RANGE_METRES / HELMET_LAMP_RANGE

## The cube's, as a fraction of CUBE_LIGHT_RANGE. Still a seed.
const CUBE_LAMP_MIN_RANGE_FRACTION := 0.3
#endregion

#region Flicker
#
# A dropout on a schedule, NOT per-frame noise. Noise on the energy every frame
# reads as a broken material or a bad shader; a lamp that cuts out for a moment
# and comes back reads as a lamp about to die. How OFTEN the dropouts land is
# what carries the charge level - rare when full, constant when nearly out.
#
# THE SCHEDULE IS A POISSON PROCESS. Dropouts land independently at the rate the
# curve below sets, so the gaps between them are exponentially distributed: most
# are shorter than the mean, a few are much longer, and two landing almost on top
# of each other is perfectly ordinary. That last part is what a failing lamp does
# and what nothing built out of a fixed interval can do however much jitter is
# thrown at it - a jittered interval still cannot produce a burst, and the eye
# reads the absence of bursts as a rhythm.
#
# So there is no jitter knob any more, and there cannot be one: the spread of an
# exponential is not a free parameter, it is fixed by the rate. Wanting it
# burstier means wanting a higher rate.

## Whether lamps flicker at all. Off is the control case for judging the dim
## curve on its own.
const FLICKER_ENABLED := true

## The suit's flicker curve: charge fraction across, dropouts per second up.
## SETTLED, and no longer on the panel.
##
## IT IS FLAT ZERO ABOVE ABOUT THREE FIFTHS OF A BATTERY, which is the decision
## in it. A healthy suit does not stutter at all, so the first dropout is itself
## the warning rather than a change in a rate you were already living with. Below
## that it climbs the whole way to one and a half a second at empty.
const SUIT_FLICKER_POINTS: Array[Vector2] = [
	Vector2(0.000, 1.500),
	Vector2(0.161, 0.786),
	Vector2(0.363, 0.214),
	Vector2(0.619, 0.000),
	Vector2(1.000, 0.000),
]

## The cube's schedule, still a seed. Slower at both ends on the guess that the
## cube is a bigger, dumber box and should read as more stubborn than the suit -
## which is exactly the sort of guess CUBE_TUNING_ENABLED exists to settle.
const CUBE_FLICKER_POINTS: Array[Vector2] = [
	Vector2(0.0, 0.63),
	Vector2(0.5, 0.06),
	Vector2(1.0, 0.03),
]

## Top of the flicker curve's axis, in dropouts per second. At three a second the
## lamp is down about a quarter of the time, which is as far as a failing lamp can
## be pushed before it stops reading as a lamp at all.
const FLICKER_RATE_MAX := 3.0

## How long one dropout lasts, in seconds. This is short on purpose: past about a
## quarter second it stops being a flicker and starts being the lamp going out.
const FLICKER_DURATION := 0.09

## What the lamp falls to during a dropout, as a fraction of the brightness it
## would otherwise have. Not 0.0 - a hard cut to black strobes, and the fog goes
## with it, which looks like a dropped frame rather than a failing lamp.
const FLICKER_DEPTH := 0.15

## Seed for the dropout schedule, so two runs at the same knobs flicker the same
## way and a change you make is the only thing that differs between them.
const FLICKER_RANDOM_SEED := 20260803
#endregion

#region Cube optics
#
# What the cube's lamp looks like at FULL charge, and the open question. These are
# the same decisions the Suit optics region already records for the helmet lamp,
# asked again for a light that is carried rather than worn - and asked with the
# helmet lamp settled beside it, which is the whole reason it went first.

## Colour of the cube's lamp, and of the glow on the cube's own faces. One value
## feeds both, so the thing you are hauling always looks like the source of the
## light coming off it - see set_cube_light_color, which is where that is kept
## true. Cool against the helmet lamp's warm white.
##
## FULL VALUE IN HSV TERMS, and it has to be. The panel's colour is a hue and a
## saturation with the value pinned at 1.0, because brightness is its own slider
## and a colour carrying brightness too makes the two fight. A knob colour with
## any less than full value would therefore be changed by the panel merely
## building itself, and the number here would not be the one on the screen.
const CUBE_LIGHT_COLOR := Color(0.579, 0.758, 1.0)

## Brightness of the cube's lamp at full charge.
const CUBE_LIGHT_ENERGY := 2.0

## How far the cube's lamp reaches at full charge, in metres. Kept under
## FOG_DEPTH_END, so a fully charged cube lights the room out to about where the
## fog closes in anyway.
const CUBE_LIGHT_RANGE := 16.0

## How sharply the cube's lamp falls off across its range.
const CUBE_LIGHT_ATTENUATION := 1.0

## How brightly the cube's own faces glow. Throws no light on anything - the lamp
## does that - it only keeps the cube from reading as a dark box sitting in the
## middle of a room it is supposed to be lighting.
const CUBE_GLOW := 1.6

## Whether the cube's lamp casts shadows.
const CUBE_LIGHT_SHADOWS := true
#endregion

#region Cube gauge
#
# The charge readout on the cube itself. A HUD number would answer "how much is
# left" without answering the question the prototype is actually about, which is
# whether you can tell from across the room, in fog, with your own lamp failing.

## How many segments the gauge is divided into. Few enough to read at a glance in
## fog; more than that and it becomes a bar you have to measure.
const GAUGE_SEGMENTS := 8

## Size of one segment in metres: width across the cube's face, then height.
const GAUGE_SEGMENT_SIZE := Vector2(0.34, 0.055)

## Gap between segments in metres.
const GAUGE_SEGMENT_GAP := 0.022

## How far the gauge stands off the cube's face, in metres. Enough that it does
## not z-fight with the face it is mounted on.
const GAUGE_SURFACE_OFFSET := 0.004

## Colour of a lit segment at full charge, and at empty. The gauge goes from cool
## to alarm on its own, so the cube says how it is doing even in a frame where
## its lamp happens to be mid-dropout.
const GAUGE_FULL_COLOR := Color(0.45, 0.95, 0.75)
const GAUGE_EMPTY_COLOR := Color(1.0, 0.32, 0.22)

## Colour of a spent segment. Dim rather than black, so the gauge still reads as
## a gauge with a length when it is nearly empty rather than as one floating dot.
const GAUGE_UNLIT_COLOR := Color(0.1, 0.12, 0.15)
#endregion

#region Cranking

## There is no crank range knob. Reach is the suit's own grab ray, and it has to
## be, now that one key does both jobs: a crank you could start from further away
## than you could grab from would mean the same press did different things at
## different distances. Change MovementKnobs.GRAB_RANGE and both move together.

## How long F has to be held before it stops being a grab and becomes a crank,
## in seconds.
##
## One key, two verbs, and this number is the whole difference between them. Too
## short and a deliberate grab turns into a crank because you did not let go
## sharply enough; too long and cranking feels like the game is waiting to be
## convinced. The grab does not fire until the key comes back up either way,
## which is a real cost - the pickup is a fraction of a second later than it used
## to be - and whether that delay is felt is worth watching for.
const CRANK_HOLD_TIME := 0.25
#endregion

#region Spawn

## Where the suit starts. Far enough back that the cube has to be found before it
## can be grabbed.
const SUIT_SPAWN := Vector3(0.0, 0.0, 6.0)
#endregion

#region Live tuning
#
# Bounds for the sliders in the bottom-left panel. Nothing the panel does is
# saved - read the value off the label and put the ones you liked back up top.
#
# Most of these belong to sliders the panel is not currently building: the light
# bounds because those values are settled, the dim and flicker ones because that
# question has not been opened yet. They stay because the switch that hides a
# section is meant to be worth flipping back. See the What is switched on region.

const LAMP_ANGLE_MIN := 15.0
const LAMP_ANGLE_MAX := 75.0

## How sharply the beam fades from its centre to the rim of the cone. The two
## ends are different lamps: near zero is a flat disc with a cut edge, like a
## projector; high is a hot spot with no edge at all, which is what a helmet lamp
## behind a lens actually looks like.
const LAMP_EDGE_FALLOFF_MIN := 0.0
const LAMP_EDGE_FALLOFF_MAX := 4.0

## How sharply the beam fades with distance. 1.0 is roughly linear across the
## throw; above it the light dies close in and the far half of the cone becomes
## suggestion rather than illumination.
const LAMP_DISTANCE_FALLOFF_MIN := 0.2
const LAMP_DISTANCE_FALLOFF_MAX := 4.0

const LAMP_ENERGY_MIN := 0.5
const LAMP_ENERGY_MAX := 8.0

const VIEW_DISTANCE_MIN := 6.0
const VIEW_DISTANCE_MAX := 60.0

## Where the fog starts to close in. Held below the view distance by the setter,
## because fog that begins past where it ends is not a look, it is a bug.
const FOG_BEGIN_MIN := 0.0
const FOG_BEGIN_MAX := 20.0

## How thick the murk gets between those two. This is a lighting knob as much as
## an atmospheric one: fog is what makes a beam visible as a beam rather than as
## a lit patch on the far wall.
const FOG_DENSITY_MIN := 0.0
const FOG_DENSITY_MAX := 4.0

## The floor the room falls to away from the lamp. A few hundredths is the
## difference between rock you cannot see and rock that is not there, and it
## changes every judgement about the lamp's throw.
const AMBIENT_MIN := 0.0
const AMBIENT_MAX := 0.25

## Hue and saturation rather than three channels: two sliders cover every colour
## anyone would actually try, and an RGB triple makes it far too easy to land on
## something with no value left in it and conclude the lamp is broken.
const LAMP_HUE_MIN := 0.0
const LAMP_HUE_MAX := 1.0
const LAMP_SATURATION_MIN := 0.0
const LAMP_SATURATION_MAX := 0.6

## The cube's saturation reaches all the way, where the helmet lamp's stops at
## 0.6. A helmet lamp with a colour is a broken helmet lamp; the cube's whole job
## is to be told apart from it at a glance across a dark room.
const CUBE_SATURATION_MAX := 1.0

## The cube's lamp is a light in a room rather than a beam you aim, so its
## brightness reaches zero - a cube that carries power without lighting anything
## is one of the answers on the table.
const CUBE_ENERGY_MIN := 0.0
const CUBE_ENERGY_MAX := 8.0

## How far the cube reaches, in metres. Runs past FOG_DEPTH_END, so "the cube
## lights further than you can see" is reachable and can be rejected rather than
## assumed away.
const CUBE_RANGE_MIN := 1.0
const CUBE_RANGE_MAX := 40.0

## How brightly the cube's own faces glow. Zero is a cube that is only visible
## when something else lights it, which is worth seeing once.
const CUBE_GLOW_MIN := 0.0
const CUBE_GLOW_MAX := 6.0

## Push along the surface normal, in shadow-map texels. Zero takes the offset off
## outright, which is the quickest way to see the striping it is there to remove.
const SHADOW_NORMAL_BIAS_MIN := 0.0
const SHADOW_NORMAL_BIAS_MAX := 12.0

## Multiplier on how often lamps flicker. 1.0 is the schedule above; higher
## shortens every interval, so the whole curve gets jumpier at once.
const FLICKER_SCALE_MIN := 0.0
const FLICKER_SCALE_MAX := 5.0

## What the lamp still throws at zero charge, as a fraction of its full throw.
## REACHES ZERO, which is the lamp going out entirely, and 1.0, which is the
## control case: a lamp that dims without ever getting smaller. There is no
## matching brightness slider - that end of the question is the left-hand end of
## the dim curve.
const RANGE_FLOOR_MIN := 0.0
const RANGE_FLOOR_MAX := 1.0

const SUIT_CAPACITY_MIN := 20.0
const SUIT_CAPACITY_MAX := 400.0

const SUIT_DRAIN_MIN := 0.0
const SUIT_DRAIN_MAX := 5.0

const CHARGE_RATE_MIN := 0.0
const CHARGE_RATE_MAX := 12.0

const CUBE_CAPACITY_MIN := 100.0
const CUBE_CAPACITY_MAX := 2000.0

const CRANK_RATE_MIN := 0.0
const CRANK_RATE_MAX := 40.0
#endregion
