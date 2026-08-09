# Drill and mining prototype

Godot 4.7. Run it by naming the scene - the project's main scene is the main
menu, so anything that does not is going to boot that instead:

```
godot --path <repo root> res://prototypes/drill_and_mining/drill_and_mining_prototype.tscn
```

Four lumps of rock are floating in a room. Each one has a crystal inside it. You
have a laser drill. Cut a hole big enough and the crystal drifts out; fly into it
and it is yours.

## Stage 1, and only stage 1

This is the first stage and it asks **one** question:

> **Does it feel good to cut a crystal free of the rock around it?**

Everything that would answer a different question is not here. There is no power
draw, the lamp is light and not a mechanic, there is no sound, no creature, and
nowhere to take a crystal once you have it. Those are later stages, and the
`#region What is switched on` block at the top of `drill_knobs.gd` is where each
one will arrive - as a `const` switched from `false` to `true`, the way
`power_knobs.gd` retired each of its answered stages rather than deleting them.

The answer so far is **yes, with conditions**, and the conditions are why the
rock is what it is - see below. Every number is still a starting point.

## Controls

| Key | Does |
|---|---|
| `LMB` **hold** | Drill. The beam runs while you hold it. |
| `WASD` | Thrust along the suit's own axes |
| `Space` / `Ctrl` | Thrust up / down |
| `Q` / `E` | Roll |
| `Shift` | Sprint |
| `R` | Stabilizers - kill drift and tumble |
| `Tab` | Rebuild the fields and respawn |
| `Esc` | Release the mouse so the tuning panel can be clicked |

**The drill is dead while the mouse is free.** Escape is the only way to reach
the panel, and a left click on a slider must not also cut a hole in something, so
firing is gated on the mouse being captured. If the beam has stopped working,
press Escape.

## What the rock is, and what it is not

**The ore nodes are the only destructible thing in the prototype.** The chamber
walls are not, the pillars are not, and nothing here generalises to them. A node
is a **2.4 m cube of signed distance field** wrapped around a crystal - 24 cells
an axis at 0.1 m each, 15,625 corner values, 62 KB. Negative is rock, positive is
space, and the magnitude is roughly the distance to the nearest surface.

The design doc lists deformable terrain as an unowned stretch goal whose fallback
is "ore nodes still work; they just stop being carveable". A node-sized field is
still that fallback: it is four small grids in fixed places, not terrain, and
nothing outside a node can be cut.

**The first version of this was eighty discrete chunks with health**, and the
playtest that replaced it is worth recording, because it is the reason for
everything below. Chunk health went to 10 against a drill rate of 90 - nine
chunks a second - at which point the chunk had stopped being the unit of
destruction and started being the thing in the way. What was wanted was a drill
that **unlodges material quickly and throws it out violently**, and the chunk
shell could only say that in units of 0.34 m.

**Zylann's Voxel Tools is in this repo and is deliberately not used.** Its
shipped binaries have no web build, this project has a web export preset, and a
node is a 2.4 m cube rather than a streamed world. None of what that addon is
for.

### The field is eroded, not subtracted from

`VoxelField.erode()` **adds** a small amount to the field around the bore,
tapered to nothing at `CARVE_RADIUS`. That is the difference between a rate and a
step: a hard sphere subtraction per frame would advance the hole by its own
radius every frame - metres a second - with no way to slow it that does not also
narrow it. Adding instead makes the surface recede at a rate in metres per
second, set directly by `CARVE_RATE`, while the bore stays the beam's own width.

The taper is squared, so the middle of the bore cuts fastest and the rim barely
at all. That is what rounds a hole rather than stamping a cylinder into the rock.

### Naive surface nets, faceted

`surface_net_mesher.gd` turns each sub-chunk into a triangle soup: one vertex per
cell whose eight corners disagree on a sign, at the mean of the crossings on that
cell's edges, and one quad per grid edge that changes sign, joining the four
cells around it.

**The quad is defined by adjacency, not by a lookup table.** That is the whole
reason it is surface nets and not marching cubes, and it is the same reason
`tunnel_system/tunnel_sdf_baker.gd` chose it: there is no 256-entry case table,
so there is no case that can be mistranscribed into a hole - and a hole looks
exactly like a winding bug while being an entirely different problem.

**Vertices are never shared.** Every triangle carries its own three with one flat
normal, which costs three times the vertices and buys two things: the hard
angular crater walls the prototype is after, and one `PackedVector3Array` that
serves as both the `ArrayMesh` surface and the `ConcavePolygonShape3D` face list
with no second pass.

A sub-chunk meshes a **one-cell skirt** past its own low side. Without it two
neighbouring sub-chunks each stop at their shared boundary and leave a crack you
can see straight through the node.

### Three things kept out of step

This is most of understanding `ore_node.gd`:

| | Currency |
|---|---|
| the **field** | Always current. The drill erodes it and reads it back the same frame, so what you cut is exactly what you aimed at. |
| the **mesh** | One or two frames behind under sustained fire. Remeshing is GDScript and runs on a budget of `REMESH_BUDGET` sub-chunks a frame across all nodes. |
| the **collision** | Rebuilt with the mesh, so equally behind. |

Nothing that has to be exact touches the last two. **The drill does not cast a
physics ray** - it calls `VoxelField.raymarch()` and walks the field in half-cell
steps with four bisections at the crossing. A ray cast against the collision
shapes would carve at a surface that is a few frames stale, and would do it
worst exactly when you are cutting hardest. Rock collision exists so you bump
into a node while flying, and for nothing else.

`REMESH_BUDGET` is the dial to reach for if drilling hitches, and `SUBCHUNK_CELLS`
is the one behind it: smaller sub-chunks mean cheaper remeshes and more draw
calls, larger the reverse.

### Two traps that both look like a lighting problem

Both shipped in the first version and both were found by looking at a screenshot,
not by any check in `verify_drill.tscn`. They are written down because the
symptom points at entirely the wrong thing.

**A `Basis` built in the wrong order mirrors the mesh.** `Basis(x, y, z)` wants
`z = x cross y`; the other order has determinant -1, and a mirrored transform
reverses winding and turns normals inward. It renders as a boulder that is *pitch
black under a lamp aimed straight at it* while still casting a perfectly correct
shadow on the wall behind. Every instinct says "the lamp is too dim". The lamp is
fine.

**An instance colour is not gamma-corrected for you.** This one no longer applies
- the rock is a plain material now - but it cost an hour and the next person to
reach for `set_instance_color` should know: a material's `albedo_color` is
converted from sRGB to linear on its way to the GPU and an instance colour is
not, so the same numbers come out about five times too bright and blow out the
instant a lamp touches them. It is written down in `rock_material.tres` too.

**And one that is a genuine lighting problem:** a crater is a pit full of faces
turned away from the lamp, which is the worst case for GL Compatibility's narrow
shadow filtering - it shows the shadow map's own texel grid as parallel stripes
across every face. `SHADOW_REVERSE_CULL` and `SHADOW_NORMAL_BIAS` hold it off;
both are lifted straight from `power_and_lighting`, which worked them out first.

**And one that is neither:** the node's surface noise has to be *high frequency*
to exist at all. At 0.1 m cells a feature needs about half a metre of wavelength
before the mesher can express it, and the first pass used frequencies around 7 -
a metre and a half - which meshed into a smooth white egg. `fill_sphere()` runs
its grain band at 11 to 13.

## How a crystal comes out

**Through a hole, not by being stripped.**

The rule that suggests itself is "clear every cell touching the crystal", and it
is the wrong one: it makes you strip the whole node every time, which is the same
work whatever you do, so where you point stops mattering. The entire reason to
cut rock rather than shoot a health bar is that aim should decide something.

So instead: **256 directions** are laid down around the crystal by the golden
angle, and each asks *how wide a clear tube fits along me, out of the rock*. The
crystal is free the moment any one of them can fit `ESCAPE_CLEARANCE`.

**The field answers that in one pass and no search.** Its magnitude at a point is
the distance to the nearest rock, so the *narrowest sample along a probe is
exactly the widest tube that fits down the whole of it* - one number per step,
against a cone of rays that would otherwise have to be traced. That is the whole
reason the rock is an SDF and not a bitmask, and it is what `narrowest_along()`
does.

The probe count is high because it has to be. At 48 probes the worst gap between
directions is about 16 degrees, which over the length of a node is a quarter of a
metre sideways - wider than the bore - so a probe would walk out of the side of
the hole you drilled before it reached open air and report rock. Whether your
crystal came loose then depended on how nearly your aim lined up with one of the
directions. At 256 the gap is around 7 degrees and a straight bore is found from
anywhere. The cost is paid back by `ESCAPE_CHECK_INTERVAL` - the test runs at
most every 0.15 s, and a crystal that comes loose a tenth of a second late is a
crystal that came loose.

`ESCAPE_CLEARANCE` **must stay under `CARVE_RADIUS`** or a straight hole can
never free anything and you have to sweep the beam around to widen one, which is
a different game and a slower one. `DrillSettings.invariant_failures()` says so
when a slider breaks it. The HUD's `opening` reading is the widest tube found so
far, in metres, so it climbs toward the clearance and the crystal comes loose
when it gets there.

**The layer change is the state change.** An embedded crystal is on the `ore`
layer, where the beam can see it and refuse to cut it; a freed one moves to
`loose_crystal`, which is the only layer the suit's collector watches. An
embedded crystal therefore cannot be picked up by flying at it - not because
something checks a flag, but because the two are not on speaking terms until the
rock lets go. A freed crystal's own mask drops to the hull alone, so it cannot
wedge in the rubble it was just cut out of and read as the release rule being
broken.

## The spray is its own thing

This is the second half of what the playtest found. With chunks, one chunk death
was one thrown object, so **how fast rock vanished and how violently it flew were
the same number** - and the playtest pushed both to their limits at once, which
is the shape of a knob that is doing two jobs.

A field has nothing discrete to throw. So fragments are spawned at a **rate**,
sized however you like, and hurled however hard you like, none of which is tied
to how fast the hole deepens. `DEBRIS_KNOCK` defaults to 18 - past 15, which is
where the old slider's ceiling was and where the playtest left it, so the answer
was "at least this and possibly more".

### Arrivals are a Poisson process, and the wait is the fragment

Fragments do not come off on a schedule, so the gap to the next one is drawn from
an **exponential distribution** with mean `1 / DEBRIS_SPAWN_RATE`. Evenly spaced
fragments read as a conveyor belt however fast they come; exponential ones clump
and thin out the way real spall does.

Then the useful part: **the gap that was waited is the fragment that arrives.**
A long gap is the drill having hung on to a piece rather than having thrown
nothing, so it comes off

- **bigger** - the edge lerps from `DEBRIS_SIZE_MIN` to `DEBRIS_SIZE_MAX`,
- **heavier** - mass lerps up by `DEBRIS_HEAVY_MASS_SCALE`,
- **slower** - which is the *same* knob: the impulse is identical for every
  fragment, so the same kick of rock coming apart moves more of it less. Grit
  leaves at 12 m/s and a slab at 3, and there is no second number that can
  disagree about which fragments are the big ones.
- **longer-lived** - by `DEBRIS_HEAVY_LIFETIME_SCALE`, so slabs are still in the
  room after the dust that came with them has gone. It tumbles more slowly too.

The gap is measured in **multiples of the average gap**, so it means the same
thing at any rate: a fragment is big because the drill hung on to it longer than
usual, not because the rate happens to be low. Exponential waits put about `e^-3`
of fragments - 5% - at the ceiling, which is what makes a slab an event rather
than the texture.

That is why the rate can be high. Raising it fills the room with dust and makes a
slab **rarer**, rather than making everything more numerous and all the same
size, which is what the old fixed-size emitter did.

Letting go of the trigger abandons the gap in progress. The process is memoryless
so keeping it would be defensible statistically and wrong in play - pausing and
re-triggering would bank the pause and hand you a boulder for it.

**Which way they go is the beam reflected off the rock.** That costs nothing,
because the field's gradient *is* the surface normal - six samples of central
differences, no mesh consulted, so the spray answers to the rock as it is this
frame rather than to the mesh a frame or two behind. Down a deep bore the face
points back along the barrel and the rock comes back at your visor; a wall taken
at a glance sheets it off sideways, the way a grinder throws. There is no switch
between "reflected" and "back at the laser" because the second is what the first
does in the straight-on case.

Fragments mask the player, so **the spray now hits you**, which it did not when
it flew away down the beam. Grit at 1.5 kg is nothing against a 90 kg suit; a
6 kg slab at 3 m/s is not. Holding station while your own drill pushes you off it
is either the good version of the zero-G problem or is a fight with the controls,
and `debris_knock` is the slider for it.

**Fragments do not collide with the ore layer.** They would pack into the bore
and read as the beam having stopped working.

## What is locked in

Nothing. Every number is a first guess or a playtest's first correction. What
follows is where each came from, so that moving one is an argument rather than a
shrug.

| Knob | Value | |
|---|---|---|
| `CARVE_RATE` | 0.55 m/s | How fast the surface recedes at the centre of the bore. About a second and a half through the 0.7 m to the crystal, plus a second or two widening. |
| `CARVE_RADIUS` | 0.22 m | How wide the hole is, as against how fast it deepens. The other half of the same question, and the one that decides whether a single straight bore frees a crystal. |
| `DRILL_RANGE` | 6 m | Short on purpose. The whole difficulty of mining in zero-G is holding station against your own drift, and a beam that reaches across the room lets you dodge that entirely. |
| `ESCAPE_CLEARANCE` | 0.16 m | Well under `CRYSTAL_RADIUS` of 0.34 - the crystal squeezes out of a hole far too small for it. Stage 1 was played with the old cone knob at its maximum, so forgiving is what was asked for; the physically honest 0.34 is a drag away and wants a wider bore with it. |
| `FIELD_RESOLUTION` / `VOXEL_SIZE` | 24 / 0.10 m | Three times finer than the 0.34 m chunks it replaced, which is what stops the grid from being the thing you feel. |
| `DEBRIS_SPAWN_RATE` | 30 /s | The **mean** of a Poisson process. High on purpose: most of what it throws is grit, so raising it thickens the dust rather than multiplying slabs. |
| `DEBRIS_HEFT_WAITS` | 3.0 | How long a gap earns a full-sized fragment, in mean gaps. Exponential waits put ~5% of fragments there. The dial for how often you see a slab. |
| `DEBRIS_KNOCK` | 18 N·s | What "the drill is powerful" is actually made of. The same for every fragment - speed varies because mass does. |
| `DEBRIS_MASS` / `HEAVY_MASS_SCALE` | 1.5 kg / 4.0 | Grit is light enough to be swatted aside by a 90 kg suit; a 6 kg slab at a quarter the speed is meant to be felt. |
| `DEBRIS_LIFETIME` / `HEAVY_LIFETIME_SCALE` | 1.8 s / 2.5 | The lightest fragment's life and the heaviest's multiplier. Mean life works out at 2.7 s, so about 80 are loose while cutting. |
| `DEBRIS_POOL_SIZE` | 96 | A cap on what is in the room, never on what you may drill: the oldest fragment is recycled when the pool runs dry. Above the ~80 the defaults imply, because Poisson arrivals clump. A draw call and a rigid body apiece, so it is the first thing to cut if the web build struggles. |
| `MUZZLE_OFFSET` | down and right | **The ray is not cast from here.** It comes off the camera, so the crosshair tells the truth about what will be hit; only the drawn beam starts at the muzzle. Matching the two would make the crosshair lie at exactly the range this prototype operates at. |

And the lighting, which is **not** this prototype's to answer and is turned up
until it stops being a variable. `power_and_lighting` owns that question and
settled it much darker; judging a crater wall against a lamp that is itself
failing would be judging two things at once.

| Knob | Value | |
|---|---|---|
| `HELMET_LAMP_ANGLE` / `ENERGY` | 52 deg / 1.5 | Wider than the power prototype's settled 45 so a whole node is in the cone at drilling range. Dimmer than its 3.5 because faceted rock lit head-on has every facet near full brightness at once, and 4.0 washed a node to white. |
| `AMBIENT_ENERGY` | 0.7 | Against the power prototype's 0.02. That number exists so its darkness is frightening; this one exists so you can find the next node without flying the room in a grid. It has a slider - it is the fastest way to tell rock that is unreadable from rock that is merely unlit. |
| `FOG_DEPTH_BEGIN` | 7 m | Past `DRILL_RANGE`, so nothing you are working on is losing contrast to the murk. The other prototypes start it at the visor because they are asking about the dark. |
| `FOG_LIGHT_COLOR` | `(0.09, 0.11, 0.15)` | Much lighter than the near-black elsewhere, which faded the far half of a 24 m room to a void you could not tell held three more nodes. |

## The panel

Eleven sliders, and `@export_range` in `drill_settings.gd` is the only thing that
decides what appears - `PrototypeTuningPanel` builds itself by introspection.
There is deliberately **no `*_TUNING_ENABLED` switch** and there cannot be one:
the shared panel has no way to be told to skip a property, so retiring an
answered question means deleting its `@export_range` and leaving the const in
`drill_knobs.gd` as the answer.

Two of the sliders reach into rock that already exists:

- **`escape_clearance`** applies to every node immediately, so a clearance
  loosened mid-flight frees the node you are already halfway through.
- **`debris_lifetime`** applies only to fragments thrown after it. A room that
  emptied itself the moment you touched a slider would hide the thing you were
  trying to look at. It is the *lightest* fragment's life; heft stretches it from
  there, which the pool invariant accounts for.

`invariant_failures()` catches three things a slider can break: a clip plane
inside the fog, a clearance wider than the bore (which makes a straight hole
useless), and a spawn rate and lifetime that together imply more fragments than
the pool holds - at which point the pool wins and both sliders quietly stop
meaning what they say.

## Layout

| Path | What it is |
|---|---|
| `drill_and_mining_prototype.gd` / `.tscn` | The root. Assembles everything, owns every setter the panel calls. |
| `drill_knobs.gd` | **Every number and every stage switch.** The source of truth; outranks `imported/drill_movement_knobs.gd`. |
| `voxel_field.gd` | One node's rock as an SDF. Generation, erosion, sampling, the raymarch, the gradient, the escape measurement, the dirty list. |
| `surface_net_mesher.gd` | One sub-chunk of field to one faceted triangle soup. Knows nothing about ore nodes. |
| `ore_node.gd` | A field, a crystal, and the meshes and shapes built off the first. Owns the release rule. |
| `drill_beam.gd` | The field walk, the erosion tick, the cylinder and the impact dot. |
| `ore_debris_pool.gd` | The loose rock: a fixed set of bodies, recycled oldest-first. Turns one heft into size, mass, speed and lifetime. |
| `drill_hud.gd`, `drill_settings.gd` | Readout, and the eleven sliders. |
| `verify_drill.gd` / `.tscn` | Headless checks: the field, the mesher, carving, the release rule, the crystal, the spray, the pool, heft. |
| `tools/capture_drill.gd` / `.tscn` | Screenshots a node under eight conditions. **Renders - do not pass `--headless`.** |
| `imported/` | The suit, its movement knobs and the chamber, copied. See its README. |

## Verifying it

```
godot --headless --path <root> --import
godot --headless --path <root> --script res://prototypes/tools/bootstrap_prototype_settings.gd
godot --headless --path <root> res://prototypes/tools/verify_prototype_settings.tscn
godot --headless --path <root> res://prototypes/drill_and_mining/verify_drill.tscn
godot --headless --path <root> res://prototypes/drill_and_mining/drill_and_mining_prototype.tscn --quit-after 400
```

Clean is: `(5 linked)` from the bootstrap - four means a registration point is
wrong - `0 failures` from both verifiers, and one `drill and mining: 4 nodes,
24^3 cells at 0.10 m each ...` line from the scene with nothing else.

Two groups of checks in `verify_drill.tscn` are load-bearing and the rest are
scaffolding. **`[mesh]`** proves a carved field still closes - an open mesh is
the failure mode that surface nets was chosen to make impossible, so it is the
one worth asserting. **`[release]`** proves a straight bore actually frees a
crystal, which is the rule the whole prototype turns on and which has already
been broken twice by knob changes alone: once by a clearance wider than the bore,
once by too few probes.

The verifier drives `OreNode.run_pending_work()` directly rather than waiting on
frames, which is why it can carve a node to the crystal and check the result in
the same tick.

## Looking at it

Headless has no renderer, so none of the above can tell you the rock looks like
rock. `capture_drill.tscn` can, and it **must not** be given `--headless`:

```
godot --path <root> res://prototypes/drill_and_mining/tools/capture_drill.tscn
```

It writes eight PNGs to `tools/_shots/`. They are **a bisection, not a gallery**:
"too dark" has several candidate causes that look identical in one screenshot -
the fog, the lamp's reach, the shadows, and the material - so each pass removes
exactly one and the first shot that brightens names the cause. `05_albedo_only`
is the decisive one: the rock lit by flat white ambient and nothing else, so if
the rock is wrong *there*, no amount of lighting will fix it. Both rendering bugs
above were found this way in about a minute.

**`08_bored` and `09_bored_standoff` matter most.** They carve the node first. An
uncarved node is a ball, and a ball says nothing about whether a crater wall
reads as cut rock - which is the whole question the mesher was chosen to answer.

## What none of that checks

**The things that decide whether this stage passes.** A screenshot settles what
the rock looks like standing still; it settles nothing about how any of it feels:

- Whether 0.55 m/s and a 0.22 m bore is the drill the playtest was asking for.
  The rate and the spray are separate knobs now specifically so this can be
  answered as two questions.
- Whether the remesh budget is visible. The mesh lagging the field by a frame or
  two under sustained fire is a deliberate trade, and whether it reads as the
  rock resisting or as the drill stuttering is a playtest question.
- Whether an unshaded additive cylinder reads as a cutting beam or as an orange
  stick. The beam only exists while the trigger is down, so no capture pass has
  photographed it.
- Whether 30 fragments a second at knock 18 is the violence that was asked for,
  or is now visual noise - and whether the spray coming back at you is the good
  version of the zero-G problem or is a fight with the controls.
- Whether a slab every 20th fragment is often enough to notice or so rare it
  reads as a glitch. `DEBRIS_HEFT_WAITS` is that dial and it has no slider yet,
  which it should get if the first playtest is inconclusive.
- Whether a crystal drifting loose lands as a payoff, and whether flying into it
  to collect it is satisfying or fiddly. `COLLECT_REQUIRES_KEY` switches that to
  a keypress if touch collects things you were only lining up.
- Frame rate, on GL Compatibility, with the web preset in mind. Four fields,
  their sub-chunk meshes and shapes, and up to 64 loose bodies.

## What it deliberately does not have

- **Power draw.** The drill costs nothing to run.
- **Lighting as a mechanic.** The helmet lamp is on, at a fixed range, so the
  room is visible. That is all.
- **Sound.** A drill is going to live or die on this and it is not here yet.
- **The creature.**
- **Anywhere to take a crystal.** Collecting it increments a counter and that is
  the end of the loop. Hauling is the object carrying prototype's domain and
  pulling it in now would muddy the one question this stage is asking.
- **Destructible tunnel walls**, or destructible anything outside an ore node.
- **Ore fragments as separate collectibles.** Loose rock is spectacle; it
  despawns and is worth nothing.
