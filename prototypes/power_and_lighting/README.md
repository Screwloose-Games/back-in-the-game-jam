# Power and lighting prototype

Godot 4.7. Run it by naming the scene - the project's main scene is the main
menu, so anything that does not is going to boot that instead:

```
godot --path <repo root> res://prototypes/power_and_lighting/power_and_lighting_prototype.tscn
```

Your lamp is the only thing you can see by, your lamp runs on the suit battery,
and the suit battery is refilled by the cube you have to haul around with you.
This is the prototype for that loop.

## Integrated multiplayer demo

`power_and_lighting_multiplayer_demo.tscn` is the two-player network proof built
from this room and its settled power/lighting values. It deliberately leaves the
finished single-player prototype intact.

The demo uses Godot's high-level multiplayer model rather than a custom gameplay
packet format:

- `MultiplayerSpawner` creates deterministic player nodes `1` and `2`.
- Each player's `Inputs` node samples bounded intent. `ClientPredictor3D` sends
  sequenced commands, moves the local suit immediately, and reconciles it to
  host snapshots.
- Player `StateSync` nodes publish atomic prediction snapshots and interpolate
  remote suits. The cube `StateSync`, cube physics, and shared power all retain
  peer 1 authority.
- Lamp brightness, cube glow, and tether drawing are local presentation derived
  from synchronized state.

Build the browser version without changing the project's real main scene:

```sh
./tools/export_power_multiplayer_demo_web.sh
cd releases/power-multiplayer-demo-web
python3 -m http.server --bind 127.0.0.1 8002
```

Open `http://127.0.0.1:8002/` in two browsers. Host in one, enter its code in the
other. The default endpoint is the signaling service in `infrastructure/`; for a
local Worker, replace it in both windows with `ws://localhost:8787`.

The multiplayer scene opens with its own briefing. Its deliberately small
interaction set is: `WASD` thrust, `Space`/`Shift` up/down, trackpad or mouse to
look, `Q`/`E` roll, hold `R` to brake drift, and hold `F` within three metres of
the cube to crank it. The blue tether is automatic in this demo; unlike the
single-player prototype documented below, `F` does not grab or release anything.

## This prototype is finished

Nothing is open. Both lamps are settled - how bright, how far, what colour, how
they fail - both batteries are settled, and the last question, what you are
allowed to do to your own lamp, came back as an off switch and nothing else. Every
`*_TUNING_ENABLED` switch is off and the panel is down to the two sets of buttons
that put the scene somewhere worth looking at.

| Switch | State | What that means |
|---|---|---|
| `LAMP_MODES_ENABLED` | **on** | `1` puts the helmet lamp out and stops the drain with it, `2` brings both back. Nothing to tune: see *The lamp switch*. |
| `CUBE_LIGHT_ENABLED` | **on** | The cube lights the room and its faces glow. Two lights in here - which is exactly what made the helmet lamp impossible to judge, and exactly why it was judged first. |
| `LAMP_RESPONDS_TO_POWER` | **on** | Both lamps dim and stutter as their battery falls, and the cube's faces dim with them. Both answers are settled. |
| `POWER_ENABLED` | **on** | The suit leaks charge while its lamp is on, a clipped tether refills it from the cube, and cranking is the only way to refill the cube. Suit bar, cube gauge and state buttons are up, and `F` is one key doing two verbs. |
| `CUBE_TUNING_ENABLED` | **off** | The cube's optics and its three curves are settled. |
| `SUIT_BEAM_TUNING_ENABLED` | **off** | The helmet lamp's shape, and the fog and ambient it is seen through, are settled. |
| `SUIT_RESPONSE_TUNING_ENABLED` | **off** | So are its dim and flicker curves and its empty throw. |
| `POWER_TUNING_ENABLED` | **off** | So are the drain and charge rates. **The state and lamp buttons are not part of this** and stay up - they are not tuning, they put a battery or a lamp where you want to look at it. |

The switches stay because the answers are worth being able to re-open one line at
a time, and because what is switched off is where the reasoning for each answer
lives. Nothing is deleted; the code all still runs.

## The lamp switch

`1` puts the lamp out. `2` brings it back. On is the settled helmet lamp,
unchanged in every respect; out is no light and no drain at all.

**Out costs nothing.** The suit battery stops dead while the lamp is out, so
hiding in the dark is always survivable and the only thing it takes from you is
being able to see. That is a decision and not a default: the alternative is a life
support drain that runs whatever the lamp is doing, which makes darkness a delay
rather than a refuge - and turns the last of a battery into a countdown you cannot
stop instead of a resource you are choosing how to spend.

### What was cut, and why

This started as **four** settings - off, dimmed, normal and overcharged, each
buying a different amount of light for a different rate of drain. The middle two
were built, flown, and cut. They were numbers you could set rather than decisions
you would make:

- **Overcharged** could only ever buy brightness. `HELMET_LAMP_RANGE` is already
  exactly `FOG_DEPTH_END`, so light thrown past it lands where the fog has
  swallowed the room anyway - it buys nothing you can see and costs shadow map
  precision on everything you can. Brightness alone was not worth 2.2x the drain.
- **Dimmed** was never worth choosing until you had nearly run out, by which point
  it is a warning light rather than a choice.

Four settings where one of them is right almost all of the time is not four
settings; it is one lamp and three traps. What survived is the off switch, because
it is the only one that changed what you **do** rather than what you see.

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

- **glow** - the cube only. Charge fraction across, fraction of `CUBE_GLOW` up. It
  drives the emission on the cube's own faces rather than a light, which is why it
  lives on the prototype and not on `lamp_power_response.gd`: the colour of that
  material is already the prototype's, tied to the lamp's hue, and splitting one
  material between two owners is how the hue and the energy end up a frame apart.

**Nothing is saved, and a curve cannot be read off a label the way a slider can**,
so each response section has a print button. It prints that lamp's curves - three
for the cube, two for the suit - formatted as the `Array[Vector2]` constants in
`power_knobs.gd`, ready to paste over them.

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

And from the cube pass, in *Cube optics* and the three `CUBE_*` point lists:

| Knob | Value | |
|---|---|---|
| `CUBE_LIGHT_ENERGY` / `CUBE_LIGHT_RANGE` | 2.0 / 16 m | Kept under the 30 m you can see, so a full cube lights the room out to about where the fog closes in anyway. |
| `CUBE_LIGHT_COLOR` | cool blue | Against the helmet lamp's warm white, so which light you are seeing by is never in question - which matters most exactly when the suit is nearly out and the two are comparable. |
| `CUBE_GLOW` | 1.0 | The top of the glow curve now, not a fixed level. |
| `CUBE_DIM_POINTS` | the suit's shape, darker floor | A flat cube is left with less than a flat suit is, but it recovers most of its brightness in the first few percent of a crank - so cranking a dead cube shows you something on the first turn of the handle rather than the tenth. |
| `CUBE_GLOW_POINTS` | sags earlier than the lamp | The faces are already down to a third when the lamp still holds four fifths, so a cube across the room announces its own trouble before the light it casts does. The glow is the early warning and the lamp is the late one. |
| `CUBE_FLICKER_POINTS` + `CUBE_FLICKER_SCALE` | the suit's, pushed later and run at 0.7x | **The cube is the more stubborn of the two.** At a fifth of a battery it drops out at under half the suit's rate. Two lights failing at visibly different speeds is what lets you tell which one is in trouble without looking at either gauge. |

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

And from the lamp pass, in *Lamp modes*:

| Knob | Value | |
|---|---|---|
| `LAMP_MODE_NAMES` | off, on | Two settings, not four. See *The lamp switch* for what dimmed and overcharged were and why they were cut. |
| `LAMP_START_MODE` | on | The prototype opens on the lamp every earlier stage was judged against. |
| off's drain | 0.0 | **The whole of the decision.** The battery stops dead while the lamp is out, so the dark is a refuge rather than a delay. One number away from the opposite. |

## Controls

| Key | Does |
|---|---|
| `1` / `2` | Helmet lamp out / on. Out drains nothing. |
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

Only the sections whose feature is switched on are built, so the panel is now down
to two sets of buttons: the state buttons and `LAMP`.

**`JUMP TO A STATE`** matters as much as the sliders: suit to 10%, suit empty,
cube empty, refill both, and a `set cube to` slider for the fractions between
them. That slider is **one-way** like the buttons beside it - it puts the cube
where you want it and does not follow it afterwards, so cranking leaves it reading
where you last left it. The live number is the HUD's `cube` line.

**`LAMP`** is two buttons and nothing else, because there is nothing here to tune:
on is the settled helmet lamp and out is the absence of it. They do what `1` and
`2` do, for when the mouse is already free.

Everything settled is gone from the panel; see *What is locked in*. `BEAM` and
`ROOM` come back with `SUIT_BEAM_TUNING_ENABLED`, the suit's curves with
`SUIT_RESPONSE_TUNING_ENABLED`, `CUBE LAMP` and `CUBE RESPONSE` with
`CUBE_TUNING_ENABLED`, the rate sliders with `POWER_TUNING_ENABLED`.

**The panel scrolls.** With the cube sections up it comes to about 850 px against
the 404 px the 1280x720 window leaves above the panel's corner, so the column sits
in a scroll view capped at whatever room is on screen - and grows back to hugging
its content when there is room for all of it. Use the wheel; the panel refuses
keyboard focus on purpose, so there is no other way in.

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

- **The suit** holds a little and leaks whenever its lamp is on, cube or no cube.
  33 seconds from full. With the lamp out it does not leak at all - see *The lamp
  switch*.
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

The cube does a third thing: its **faces dim on their own curve**, ahead of the
lamp. See `CUBE_GLOW_POINTS` in *What is locked in*.

The cube also carries its charge on its outside: eight segments, on all four
vertical faces, unshaded so they stay legible when your own lamp has gone. That
gauge exists to answer whether you can read the cube from across the room in fog
without a HUD element telling you - so if it is unreadable, that is the finding,
not a bug.

## What it answered

Everything it was built to. In *What is locked in*: the helmet lamp's shape,
brightness, colour and shadows; how far you can see and what the fog does to it;
how both lamps dim and stutter as their batteries fall; what the cube looks like
and how it dies; every capacity, drain and charge rate. And last, that the lamp
wants an off switch and does not want a dial.

**What it did not answer, and what a real build would have to.**

- Can you tell the cube's charge from its own gauge, at range, in fog, with a
  failing lamp - or do you end up flying over to read it? The gauge exists to test
  exactly this and it was never put under pressure.
- **The cube's light barely survives the fog.** `FOG_DEPTH_END` is 30 m with a
  near-black fog colour, so a surface at 20 m keeps well under half of whatever is
  lighting it. Your own lamp never shows this because it only ever lights what is
  near you; the cube's light lands on the far half of the room and most of it is
  erased. GL Compatibility has no volumetric fog, so the air will never glow near
  a light - the options are a thinner fog, a brighter cube, or a billboard halo on
  the cube itself. None was taken here.
- Should the cube cost something to run? `CUBE_IDLE_DRAIN_PER_SECOND` has never
  been anything but zero.
- Cranking is a placeholder. It is faster than the tether, which makes it a way out
  of trouble rather than a penance, and whatever it is supposed to cost has to come
  from an animation that does not exist yet.

**Nothing the panel does is saved.** The curve print buttons are how a shape leaves
a session; everything else reads off a label.

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
