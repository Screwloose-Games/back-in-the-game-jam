# core_loop

Everything at once: a kilometre of tunnel, a life support cube you have to drag
with you, a drill that eats the same battery your lamp does, eight crystals, and
something that hunts by sound.

```
godot --path <root> res://prototypes/core_loop/core_loop_prototype.tscn
```

WASD + space/ctrl to thrust, mouse to look, Q/E roll, **shift sprint**, R
stabilise, **left mouse drill**, F grip, T tether, **C crank**, TAB reset, escape
to free the mouse for the tuning panel.

The five prototypes before this one each answered a question on its own. This one
asks the only question none of them can: **do they add up to a loop worth
playing?** The drill is only interesting if running it is dangerous, and the
creature is only interesting if you have a reason to stand still.

---

## The loop

1. **Find rock.** Eight ore nodes, spread from the antechamber down to the core
   chamber 170 m below.
2. **Bring the cube.** Your suit battery is thirty-three seconds of lamp. The cube
   holds six of them, and the only way to get charge out of it is a tether clipped
   on - holding it in your hands does nothing. Cranking is the only way to put
   charge back in.
3. **Cut the crystal out.** About eighteen seconds of held trigger per node, and
   the drill is spending your battery three times as fast as the lamp alone.
4. **Fly into the crystal** to collect it.
5. **Deal with what the noise brought.**

## The creature

It is blind. It knows nothing but sound, and every noise carries a distance:

| What you are doing | Heard from |
|---|---|
| Drilling | 60 m |
| Cranking | 60 m |
| Sprinting | 20 m |
| Thrusters or stabilisers | 12 m |
| Coasting | nothing at all |

Drilling and cranking are the only two loud enough to wake it, at 8% per second
of doing them - so most single crystals are safe and a long session is not. It
wakes **one or two tunnels away**, measured along the navmesh rather than through
the rock, and never within 25 m of you.

Then it walks to the noise. Not to you - to the **place the sound came from**. It
will keep updating that as long as you keep making sounds it can hear from where
it is standing.

Get within 18 m of it and make any noise at all and it stops hunting and starts
**chasing**, which is the state where it genuinely knows where you are. Touching
it does the same. The chase lasts six seconds and any noise inside that radius
refreshes it.

**So the escape has two halves and needs both.** Sprint until you are outside the
trigger radius, then stop thrusting and be silent until the timer runs out.
Distance alone does not save you while you are still making noise. Silence alone
does not save you while it is standing on top of you. After twenty-five seconds of
hearing nothing it gives up and leaves.

The top right of the screen tells you which state it is in, how far off it is, and
how long you have. **That readout is a debug tool and it is a spoiler** - it
exists so the numbers can be tuned, not because the game should ever have it.

## Where it cannot follow you

The creature is 3.9 m across and holds 3.2 m off every wall, so it physically
cannot enter anything under 6.4 m wide. Three routes are 4 m:

- **the_squeeze** - 170 m, the fast way from the west side to the bottom
- **spur_ante_north** and **spur_west_low** - dead ends with a crystal in each

Everything else is 8 m or 10 m and it can hunt you down all of it. Two of the
eight crystals are in those refuges: safe rock, longer flight, less of it.

## Questions worth answering

**On the noise.** Does drilling feel like something you are spending, or like
something you are risking? When it turns up, can you tell whether it heard the
drill or heard you leaving? Is 8% a second too generous, or does it arrive so
often that mining stops being worth starting?

**On the escape.** The first time it chases you, do you work out that you have to
go quiet - or do you just fly? Is six seconds long enough to be frightening and
short enough to be survivable? Does sprinting away feel like escaping or like
losing a race?

**On the refuges.** Does ducking into a 4 m tunnel read as safety, or does it just
read as a corridor? Is a crystal that is safe to mine worth the extra flight?

**On the power.** Is the cube something you plan around or something you resent?
Does the tether's 10 m leash cost you anything real while you are drilling? When
the lamp starts to flicker, do you crank, or do you run for it?

**On the map.** How long before you are properly lost? Do the coloured junction
beacons work as landmarks, or do they blur together?

## Tuning it while you play

Press escape and use the panel in the bottom left. Twelve sliders, and they are
the twelve this prototype does not know the answer to: the whole monster block,
the drill's power draw, how far noise carries, and the speed ratio that decides
whether you can outrun it at all.

**SAVE** writes what you stopped on to `core_loop_settings.tres`, which is
committed, so the values turn up in the diff as numbers somebody can read.
**RESET** goes back to `core_loop_knobs.gd`.

Everything else is a const in that file and is one `@export_range` away from being
a slider. The panel has room for about fourteen rows before it runs off the top of
a 720p window, so adding one means taking one out.

## Three numbers that were changed rather than inherited

`core_loop_knobs.gd` copies the drill's values from `drill_and_mining` rather than
referencing them, so that prototype can lock its own without changing this one.
Three of them had to move, and the reason is measured:

**At the inherited `CARVE_RATE` 0.55, `CARVE_RADIUS` 0.22 and `ESCAPE_CLEARANCE`
0.16, a crystal cannot be freed by the beam at all.** The verifier held the
trigger on one for sixty seconds, took 11% of the rock off, and never moved the
escape opening off zero.

That is not a bug over there. `drill_and_mining`'s own release check passes, but
it frees its crystal by calling `carve()` forty times at each of eight points
stepping out from the crystal. The beam delivers a four-hundredth of that per
frame and its hit point recedes with the surface, so the erosion spreads along the
bore instead of accumulating - and the last few centimetres beside the crystal
never open, because the crystal itself blocks the shot. **That prototype has never
had to free a crystal with the beam.**

`CARVE_RADIUS` is the lever, because the erosion taper is `(1 - d/radius)`
squared: at 0.22 a point 0.16 out gets 7% of the rate, at 0.35 it gets 43%. At
1.00 / 0.35 / 0.10 one hardness-1.0 node takes **18 seconds** of held trigger with
the crosshair sweeping.

## Known limitations

**The creature cannot reach the core chamber.** `core_descent` bakes as a navmesh
island, so the deepest and richest rock is safe to work - a real hole in the loop,
and the one thing here most worth fixing next.

It is the steepest diagonal in the network, and a world-axis lattice crossing a
surface at that angle emits a staircase whose quads meet four-to-an-edge at the
inside corners. Godot links polygons in pairs and drops the rest, reporting *"more
than 2 edges tried to occupy the same map rasterization space"*. Ruled out by
experiment, so nobody repeats them: widening the route 8 m to 10 m, halving the
fill cell 1.5 m to 1.0 m (worse), doubling the mesh `cell_size`, adding
intermediate waypoints, removing every chamber sphere, and detaching the squeeze
from the deep hub. The fix belongs in `WallNavmeshBaker` - a fill that also opened
diagonal neighbours, or a merge pass over coincident edges - and that file is the
chase prototype's.

`NAVMESH_ISLAND_ROUTES` records it, the route's spawn points are withheld so the
creature cannot wake somewhere it can never leave, and `verify_core_loop` asserts
the island is still there so that whoever fixes it is told to undo all three.

**The map is box-section CSG**, not the rounded rock of `tunnel_system`. It was
chosen for iteration speed - edit the table in `core_loop_knobs.gd`, press play,
no bake step and no generated files. Because `WallNavmeshBaker` works off physics
queries rather than geometry, swapping in `tunnel_system`'s baked network later is
a one-node change in the scene.

**Getting caught costs nothing** beyond the creature getting a proper look at you.
`CATCH_IS_LETHAL` is the knob.

**Nothing is delivered anywhere.** Collecting a crystal increments a counter. The
cube is a battery, not a base.

## Checking it still works

```
godot --headless --path <root> res://prototypes/core_loop/verify_core_loop.tscn
```

136 checks: that the CSG built collision at all, that the refuge routes are
genuinely impassable and everything else genuinely is not, that the navmesh covers
what it should and connects where it must, that every state edge of the monster
fires in order, and that drilling removes rock and costs charge out of the suit
battery and stops dead on a flat one.

Two of those print numbers rather than just passing - how long a crystal takes and
how far the creature wakes - because those are the ones worth watching drift.

Headless cannot check anything you can see. The map, the lamp, the tether rope and
whether the creature reads at all still need a person in the editor.
