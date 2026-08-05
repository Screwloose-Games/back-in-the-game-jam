# Power and lighting prototype

Godot 4.7. Run it by naming the scene - the project's main scene is the main
menu, so anything that does not is going to boot that instead:

```
godot --path <repo root> res://prototypes/power_and_lighting/power_and_lighting_prototype.tscn
```

Your lamp is the only thing you can see by, your lamp runs on the suit battery,
and the suit battery is refilled by the cube you have to haul around with you.
This is the prototype for that loop.

## What is currently switched on

**The cube's lamp.** The prototype answers one question at a time, and the rest is
switched off in the *What is switched on* region at the top of `power_knobs.gd`.
The `*_ENABLED` switches decide what runs; the `*_TUNING_ENABLED` ones decide only
what the panel still offers.

| Switch | State | What that means |
|---|---|---|
| `CUBE_LIGHT_ENABLED` | **on** | The cube lights the room and its faces glow. There are two lights in here now - which is exactly what made the helmet lamp impossible to judge, and exactly why it was judged first. |
| `CUBE_TUNING_ENABLED` | **on** | `CUBE LAMP` and `CUBE RESPONSE` are on the panel. **This is the step.** |
| `LAMP_RESPONDS_TO_POWER` | **on** | Both lamps dim and stutter as their battery falls. The suit's answer is settled; the cube's is the open half. |
| `POWER_ENABLED` | **on** | The suit leaks charge, a clipped tether refills it from the cube, and cranking is the only way to refill the cube. Suit bar, cube gauge and state buttons are up, and `F` is one key doing two verbs. |
| `SUIT_BEAM_TUNING_ENABLED` | **off** | The helmet lamp's shape, and the fog and ambient it is seen through, are settled. |
| `SUIT_RESPONSE_TUNING_ENABLED` | **off** | So are its dim and flicker curves and its empty throw. |
| `POWER_TUNING_ENABLED` | **off** | So are the drain and charge rates. **The state buttons are not part of this** and stay up - they are not tuning, they put a battery where you want to look at it, and a lamp being tuned for how it dies needs that more than anything else on the panel. |

None of it is deleted - the code all still runs, the switches just decide what it
is allowed to do, and the numbers behind each part are still in `power_knobs.gd`
under their own regions. Turning any of them back on is one line and nothing else
has to move.

## Tuning the cube

Both lamps run the same `lamp_power_response.gd` on their own numbers, so the
panel that tunes one is literally the same code that tunes the other - which is
what makes the settled helmet lamp useful rather than just finished. It is a fixed
thing in the room to judge the new light against.

`CUBE LAMP` has no cone and no edge falloff: it is an omni light and has neither.
What it has instead is **glow**, because the cube is the only light source in this
game you can also pick up and look at.

**Hue and glow share one colour, on purpose.** A cube glowing a different colour
to the light coming off it stops reading as the source of that light and starts
reading as a box someone else is lighting, so the colour goes through the
prototype rather than straight to the lamp - `set_cube_light_color` is where that
is kept true. It is the one part of a lamp's look that is not the response's.

That colour is stored at **full value in HSV terms** and has to be: the panel's
colour is a hue and a saturation with value pinned at 1.0, so a knob colour with
any less would be changed by the panel merely building itself.

## The two curves

Dimming and flicker are both **editable curves**, not formulas, and the panel
edits them while you fly. Click empty space to add a point, drag a point to move
it, right-click one to drop it, as many points as you like.

The editors mutate the live `Curve` resources that `lamp_power_response.gd`
samples every frame, so a drag shows on the lamp before the mouse button comes
up. Nothing is wired between them; that is the point.

- **dim** - charge fraction across, fraction of full brightness up. Any shape:
  the reason it stopped being an exponent is that one number is one family of
  shapes, and the one people reach for first - hold, sag, hold, give out - was
  not in it.
- **flicker** - charge fraction across, **dropouts per second** up. Flat zero is a
  real setting and the suit uses it: no dropouts at all until the battery is low
  enough to be worth warning about.

**Nothing is saved, and a curve cannot be read off a label the way a slider can**,
so each response section has a print button. It prints that lamp's two curves
formatted as the `Array[Vector2]` constants in `power_knobs.gd`, ready to paste
over them.

## What no power looks like

**The left-hand end of the dim curve.** Drag it to the floor and the lamp simply
goes out; leave it just above and you have a dark reserve. The suit's answer is an
ember at 12% with 14 m of throw; the cube's is still open. Two quite different
games:

- **At zero: the lamp goes out.** Flat black, ambient only, and the cube's gauge
  is the one thing still readable in the room.
- **Just above: a dark reserve.** You can still work, barely, and the question is
  whether that is more frightening than the dark - a lamp that has failed but has
  not stopped is much harder to give up on than one that is plainly dead.

**empty throw** stays a slider, because it is a separate axis: how much the world
shrinks against how much it darkens. Dropping the brightness alone leaves a dim
lamp still reaching the far wall, and that reads as the exposure coming down
rather than as a lamp failing.

## Why the flicker is uneven

The dropouts are a **Poisson process**: they land independently at whatever rate
the flicker curve gives for the current charge, which makes the gaps between them
exponentially distributed. Most gaps are shorter than the mean, a few are much
longer, and two dropouts almost on top of each other are ordinary.

That last part is the whole reason for it. This used to be a fixed interval with
a jitter band around it, and a jittered interval **cannot produce a burst** - it
can only be a bit early or a bit late, and the eye reads the absence of bursts as
a rhythm. There is no jitter knob any more and there cannot be one: the spread of
an exponential is not a free parameter, it is fixed by the rate. Wanting it
burstier means wanting a higher rate, which is what the curve is for.

The rate is *integrated* rather than used to draw a wait in seconds, which is what
lets it change mid-wait: empty the battery with a state button and the next frame
already flickers at the new rate.

## What is locked in

These came out of the lighting pass and are no longer on the panel. They are in
the *Suit optics*, *Draw distance* and *Shadow artefacts* regions of
`power_knobs.gd`, and everything since is judged under them.

| Knob | Value | |
|---|---|---|
| `HELMET_LAMP_ANGLE` | 45 deg half-angle | A 90 degree spread. |
| `HELMET_LAMP_ANGLE_ATTENUATION` | 0.75 | Soft enough to read as a lens rather than a projector, hard enough that the cone is still something you aim. |
| `HELMET_LAMP_ATTENUATION` | 1.0 | Linear along the throw, so the far half of the beam goes on doing work. |
| `HELMET_LAMP_ENERGY` | 3.5 | |
| `HELMET_LAMP_COLOR` | warm white | |
| `HELMET_LAMP_SHADOWS` | on | |
| `FOG_DEPTH_END` | 30 m | Also the lamp's throw and, plus 8 m, the clip plane. |
| `FOG_DEPTH_BEGIN` | 0 m | The murk starts at the visor rather than leaving a clear shell around you. |
| `FOG_DENSITY` | 1.0 | |
| `AMBIENT_ENERGY` | 0.02 | |
| `SHADOW_REVERSE_CULL` | on | |
| `SHADOW_NORMAL_BIAS` | 2.0 | Godot's default. Reverse cull and the zero lamp margin already take the stripes off the walls; more only pulls shadows off the foot of a pillar. |

And from the dimming pass, in *Lamp response* and *Flicker*. Both are point lists
now rather than numbers, so the shape is the answer:

| Knob | Shape | |
|---|---|---|
| `SUIT_DIM_POINTS` | hold, sag, cliff | Full brightness down to about three quarters of a battery, so most of a charge shows you nothing; a long gentle sag through the middle; then a cliff in the last seventh, from two thirds brightness to the ember at 12%. The warning is late and short. |
| `SUIT_FLICKER_POINTS` | silent, then climbing | **Flat zero above about three fifths of a battery.** A healthy suit does not stutter at all, so the first dropout is itself the warning rather than a change in a rate you were already living with. Below that it climbs to 1.5 a second at empty. |
| `SUIT_LAMP_MIN_RANGE_METRES` | 14 m | What a flat suit still shows you. Stored in metres, not as a fraction, because metres are what was judged. |

And from the power pass, in *Suit power* and *Cube power*:

| Knob | Value | |
|---|---|---|
| `SUIT_CAPACITY` | 100 | Arbitrary units; every readout is a percentage of it. |
| `SUIT_DRAIN_PER_SECOND` | 3.0 | 33 seconds of light from a full suit. |
| `SUIT_CHARGE_PER_SECOND` | 12.0 | Nets +9/s while moored, so a refill from empty is about 11 seconds. |
| `CUBE_CAPACITY` | 600 | Six suit charges. |
| `CRANK_PER_SECOND` | 40.0 | 15 seconds fills an empty cube; one second of cranking is worth about 13 seconds of light. |

Cranking is now **faster than the tether**, which makes it a way out of trouble
rather than a penance. Whatever cranking is supposed to cost has to come from the
animation and from having to stop and do it, because it is not coming from the
rate.

## Controls

| Key | Does |
|---|---|
| `WASD` | Thrust along the suit's own axes |
| `Space` / `Ctrl` | Thrust up / down |
| `Q` / `E` | Roll |
| `Shift` | Sprint |
| `R` | Stabilizers - kill drift and tumble |
| `F` **tap** | Grab / release the cube with both hands |
| `F` **hold** | **Crank** the cube, while it is under the crosshair or in your hands |
| `T` | Clip / unclip the tether |
| `Tab` | Reset the suit's pose, the cube's pose, and both batteries |
| `Esc` | Release the mouse so the tuning panel can be clicked |

One key, two verbs, split at `CRANK_HOLD_TIME` (0.25 s). Two consequences worth
knowing before you decide the split is wrong:

- **The grab does not fire until F comes back up.** It cannot: nothing can tell a
  tap from a hold until the key is released. Pickup is therefore a fraction of a
  second later than it was, and whether that is felt is one of the things to
  watch for.
- **Holding F only becomes a crank when the cube is actually in reach.** Lean on
  F at nothing and it stays a grab however long you hold it, so an idle press
  never silently arms the other verb.

## The panel

Only the sections whose feature is switched on are built, so the panel is
currently the state buttons, `CUBE LAMP` and `CUBE RESPONSE`.

**`JUMP TO A STATE`** matters as much as the sliders: suit to 10%, suit empty,
cube empty, refill both. `Cube empty` is the one this step is about - it puts you
straight into the state being tuned instead of hauling the cube around until it
gets there.

**`CUBE LAMP`** is brightness, throw, distance falloff, hue, saturation, glow, and
a shadows toggle. Brightness reaches zero and glow reaches zero, so "a cube that
carries power without lighting anything" and "a cube you can only see when
something else lights it" are both reachable and can be rejected rather than
assumed away. Throw runs past the view distance, so "the cube lights further than
you can see" can be too. Its saturation goes all the way where the helmet lamp's
stops at 0.6 - a helmet lamp with a colour is a broken helmet lamp, but the cube's
whole job is to be told apart from it across a dark room.

**`CUBE RESPONSE`** is the same section the suit had: two curve editors, a flicker
rate, an empty throw, and a print button. **Flicker rate is per lamp now**, not
one multiplier over both - each lamp has its own curve, and silencing one to look
at the other is exactly the comparison worth keeping.

Everything settled is gone from the panel; see *What is locked in*. `BEAM` and
`ROOM` come back with `SUIT_BEAM_TUNING_ENABLED`, the suit's curves with
`SUIT_RESPONSE_TUNING_ENABLED`, the rate sliders with `POWER_TUNING_ENABLED`.

**The panel scrolls.** Two sections and two curve editors come to about 850 px
against the 404 px the 1280x720 window leaves above the panel's corner, so the
column sits in a scroll view capped at whatever room is on screen - and grows back
to hugging its content when there is room for all of it. Use the wheel; the panel
refuses keyboard focus on purpose, so there is no other way in.

The wheel works over the sliders and the curve editors, not only over the gaps
between them, and it does not nudge a slider on the way past. That takes two
things and neither is obvious: sliders have `scrollable` off, and everything in
the column is `MOUSE_FILTER_PASS`. A control left on the default `STOP` ends the
event's walk up the tree, so the wheel would simply do nothing over most of the
panel's surface.

**Shadow striping, for when it comes back.** The GL Compatibility renderer filters
shadows far more narrowly than Forward+ does, so the shadow map's own texel grid
can show through as parallel stripes across any flat wall a lamp is pointed at -
`shadow_bug.png` is what that looks like. Three things hold it off, all now fixed
in `power_knobs.gd`: reverse cull moves the self-shadowing onto faces turned away
from the lamp, normal bias pushes each lookup along the surface normal before it
is tested, and `VIEW_LAMP_MARGIN` is zero so the lamp's range - which is also the
far plane of its shadow map - stops exactly where the fog does and no depth
precision is spent past it.

## The two batteries

They are separate stores with separate rules, and none of the rules live in the
batteries themselves - see `power_system.gd`.

- **The suit** holds a little and leaks constantly, cube or no cube. About three
  minutes from full at the default drain.
- **The cube** holds about six suits' worth and leaks nothing. It loses power
  only through what it hands the suit.
- **The tether is the only charge link.** Clip on with `T` and the suit draws
  from the cube faster than it drains, so it nets upward while you are moored.
  Holding the cube in both hands does nothing for the suit - the grip is how you
  move the cube, the tether is how you live off it.
- **Cranking** is the only way to put power back into the cube. Hold `F` on it.
  A placeholder: this becomes its own verb, with its own animation and its own
  cost, later.

## What the lamps do about it

Both lamps run the same response (`lamp_power_response.gd`) on their own numbers.
As a battery falls its lamp does two separate things:

- **Dims**, along its dim curve. Its throw comes in with its brightness, so a weak
  lamp is a smaller world rather than a darker one.
- **Flickers more often**, along its flicker curve. A dropout on a schedule, not
  per-frame noise. The charge level is carried by how often the dropouts land
  rather than how deep they are, because a light that fails deeper as it drains
  just looks like the dimming that is already happening.

The cube also carries its charge on its outside: eight segments, on all four
vertical faces, unshaded so they stay legible when your own lamp has gone. That
gauge exists to answer whether you can read the cube from across the room in fog
without a HUD element telling you - so if it is unreadable, that is the finding,
not a bug.

## Questions it exists to answer

With the cube lighting the room, these are the ones on the table:

- **Should the cube light the room at all?** A second light source is what made
  the first one hard to judge, and the honest answer might be that the cube is
  something you haul in the dark. Brightness reaches zero so that answer is one
  drag away.
- How far should it reach, against the 30 m you can see? A cube lighting further
  than the fog allows is a cube spending power on nothing.
- What colour, and how saturated? It has to be told from the helmet lamp at a
  glance across a dark room, and it also has to not look like a different game.
- Should the cube glow, and how much? A dark box in the middle of a room it is
  lighting is wrong; a lantern you cannot look at is wrong the other way.
- **How does a cube die?** Same question as the suit, and it need not have the
  same answer - a bigger, dumber box could plausibly be more stubborn, failing
  later and harder.
- Two lamps stuttering on different schedules: does that read as two failing
  lights, or as one broken renderer?

Already answered, in *What is locked in*: everything about the helmet lamp, how
far you can see, every drain and charge rate.

Still open, and not on the panel:

- Can you tell the cube's charge from its own gauge, at range, in fog, with a
  failing lamp - or do you end up flying over to read it?
- Should the cube cost something to run? `CUBE_IDLE_DRAIN_PER_SECOND` has never
  been anything but zero.

Drag the sliders while flying rather than guessing, and use `Cube empty` rather
than waiting for it. **Nothing the panel does is saved.** Print the curves and
read the rest off the labels.

## Layout

| Path | What it is |
|---|---|
| `power_and_lighting_prototype.gd` / `.tscn` | The root. Assembles everything, owns every live setter the panel calls. |
| `power_knobs.gd` | **Every optical and power value, and the switches at the top that decide which of them are in play.** The source of truth; outranks `imported/movement_knobs.gd`. |
| `power_store.gd` | One battery. Capacity, charge, idle drain, and nothing else. |
| `power_system.gd` | Where power is allowed to move: tether charge and cranking. |
| `lamp_power_response.gd` | Drives one light from one battery: the dim curve, and the Poisson flicker schedule. |
| `lamp_curve_editor.gd` | The runtime curve widget. Godot's own is editor-only, so this is the stand-in. |
| `cube_power_gauge.gd` | The segments on the cube's four vertical faces. |
| `power_hud.gd`, `power_bar.gd` | Readout and the suit charge bar. |
| `power_tuning_panel.gd` | The bottom-left panel. |
| `imported/` | Movement, carrying and the chamber, copied from `object_carrying`. See its README. |

## What it deliberately does not have

- **Tunnels.** It runs in the object carrying prototype's CSG room, which is
  cheap and already built. The optics are therefore tuned against a room rather
  than against a 2-3 m bore, so every number here wants re-checking once a
  tunnel scene is cheap to drop a suit into.
- **Oxygen, or anything else the cube is supposed to supply.** Power only.
- **Cube idle drain.** `CUBE_IDLE_DRAIN_PER_SECOND` is 0.0 and is left in the
  knobs as the obvious next thing to try, so turning it on is one number rather
  than a code change.
- **Any persistence.** Every session starts from `power_knobs.gd`. For the curves
  that is a real cost rather than a shrug, which is what `Print curves to console`
  is for - press it before you close the window.
