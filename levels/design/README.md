# Level blockouts

**One scene per biome, each edited independently.** Each is the shape of that
biome, annotated, as a graph that keeps its 3D coordinates. None of them is
finished geometry and none tries to be.

**OUTDATED**
| Scene | Biome | Size |
|---|---|---|
| `level_mine_blockout.tscn` | The mines. Where the player starts | 16 spaces, 22 tunnels, 1,303 m |
| `level_ravine_blockout.tscn` | The ravine | 16 spaces, 23 tunnels, 1,406 m |
| `level_hive_blockout.tscn` | The hive | 115 spaces, 184 tunnels, 3,250 m |

**`level_full_blockout.tscn` is the three of them stitched together**, and is the
level the jam ships. Its root is a `MineLevel` like any other blockout, so it
walks in `level_walkthrough.tscn` and every tool takes it; `MineLevel` collects
spaces and tunnels from its whole subtree, so the biomes being instanced scenes
with `MineLevel` roots of their own costs nothing. Space and tunnel names are graph
ids and no two biomes collide, which is what makes one flat namespace work.

**Nothing in the composed scene uses "can edit children".** The tunnels joining
the biomes live under its own `Connectors/Spaces` and `Connectors/Tunnels` and
reach into the instances by NodePath, which a NodePath does perfectly well across
an instance boundary. The two places where a mine tunnel is split for a link are
`MineSpace.on_tunnel` stops rather than retargeted tunnels, so the biome files are
untouched and still say what they are on their own. Edit a biome and the composed
level follows.

The one thing that cannot be said from outside is repointing an instanced tunnel's
end. `link_east_5_east_6` was originally rerouted that way; it is now a connector
of its own, so `pocket_east_5` keeps its ravine link **and** gains the hive link -
one more edge than the hand-composed version had.

Each biome still ends at `link_*` dead-end stubs tagged `unbuilt` marking where a
connection would land, and the ones the composed level does not use are still
there.

(`level_core_loop_blockout.tscn` is the small placeholder map the core loop
prototype actually plays. It is not in the repo - `import_core_loop_layout.gd`
regenerates it - and it is kept only so the real biomes can be measured against
something that has been played. Every tool takes `-- --level=res://...`.)

## How the mines are shaped

**This is where the player starts, so it teaches the map before it uses it.** The
biome is a difficulty ramp running east, and every junction the player meets is
the simplest one they have not already learnt:

| Where | What they meet |
|---|---|
| The adit | One straight tunnel, 65 m due east, dead level. No choices at all. |
| `a_c1_m` | Still one tunnel. Nothing branches yet. |
| `a_c2_m` | The first branch: one cross-cut, perpendicular. A T. |
| `a_c3` | The second cross-cut closes a loop, so now there are + junctions. |
| Level `b` | The full two-by-three grid, reached only by a winze. |

**Two drifts, three cross-cuts, two levels, and that is the maximum** - reached
only on the lower level. The upper level never has more than five workings.

### Reading a mine node name

`a_c3_n` = level **a** (upper), cross-cut column **c3**, drift row **n** (north).
Rows are `m` (the one you arrive in) and `n`; columns run `c1` (nearest the
entrance) to `c3` (deepest).

- **Drifts** run east, 9 m and square. `a_c1_n` is deliberately never dug, which
  is what makes the first stretch a corridor rather than a junction.
- **x and z are exact; y is not.** The workings were surveyed, so they line up in
  plan, but they follow the seam in section. The two drift rows sit at different
  depths, so the biome is not one flat floor.
- **Natural tunnels** (tagged `natural`, curved, orange) ignore the grid. There
  are only three and **none is anywhere near the entrance** - the first one you
  can meet is at the far end of the upper level.
- **Winzes** join the levels at two junctions: `winze_deep` (7 m, followable) and
  `winze_north` (5 m, too narrow for the creature).
- `nat_drop` falls between levels **without** being a winze. It is not on the
  survey, and taking it puts you a level down and a column west of where you
  think you are.
- `fork_east` and `fork_deep` are natural cavities past the end of the workings,
  and are how you leave the biome.

Rooms and junctions are nodes, tunnels are edges. That is a real graph, so the
creature AI and the noise system can walk it, and it is also a real scene, so it
is authored by dragging things in Godot's 3D viewport.

## How the ravine is shaped

One chasm, **12 m across and 48 m floor to roof**, running 220 m north to south
and falling 30 m as it goes. It is a chain of six stations rather than one space,
so where you are along it is something the graph can answer.

The stations drift up to 10 m either side of the axis, at around 44 m spacing - so
the chasm is no more crooked per metre than a longer one would be. Measured on the
carved rock: **you can see the next station 48 m away and never the one after
it**, and end to end is blocked after 23 m.

**Every station has a tunnel off both walls.** Side tunnels clustered on one wall
at a time give the chasm a handedness, and a handedness is a landmark - you always
know which way you are facing. Both walls everywhere takes that away, and that is
what makes the biome disorienting rather than merely long.

Those twelve side tunnels wind out to `knot_*` junctions where several meet, on to
`pocket_*` rooms, and back into the chasm further along. Their widths sit
deliberately either side of the 6.4 m the creature needs, so which of them is a
refuge and which is a trap is the question the side network exists to ask.

## How the hive is shaped

**An anthill in section**, after `anthill_internal_sideprofile.jpg`. Eight strata
over about 110 m. A stratum is horizontal and nothing about it is flat: its
chambers sit on a noise-warped surface rather than at one depth, and each is a
different width and a different thickness, so crossing one opens into a room,
pinches to a squeeze, and opens again.

**A stratum is one continuous void with pillars in it**, not rooms joined by
corridors. Most bores are wide enough to merge with the chambers at either end, so
what blocks you is whatever rock the scatter left standing. Measured on the carved
rock across the widest axis of each of the eight, a sightline runs **7 to 30 m of
the 63 to 89 m** available before a pillar stops it. Never far enough to see out,
and how far varies enough between strata that it is not a cue to where you are.

**The strata are not separate floors.** Each is offset sideways from the one above
and warps independently of it, so two of them converge in one corner of the biome
and separate in another. Where they come close they are breached straight through
the floor - **31 of those, and 23 chamber pairs that intersect outright**, so one
cavity spans two strata with nothing to mark where one ended. Measured on the
carved rock, every stratum boundary has at least one breach that is a **clear line
into the stratum below**, 5 to 19 m of it.

That last part is a deliberate reversal. The previous hive guaranteed no sightline
between any two layers; this one does the opposite, because a glimpse of something
moving one stratum down through a hole in the floor is worse than never seeing it.
It is still the most disorienting biome, and for a stronger reason - in the mines
you are lost about where, here you are lost about which stratum, and the stack no
longer promises that there is a definite answer.

Five `hv_long_*` tunnels skip two or more strata; coming up one puts you somewhere
that looks like where you started and is a long way from it.

**It is generated, not typed.** `build_hive_blockout.gd` holds ranges and a
`seed`; `strata_layout.gd` turns those into the layout. Re-roll the seed rather
than moving chambers, and read the build's `N breaches between strata, M of them
where the two merge` line - a stack reporting no merges is a stack of pancakes
again, and it looks perfectly healthy in every other number.

## Opening it

1. Project > Project Settings > Plugins, tick **Mine Level Designer**. (It is
   already on in `project.godot`; a running editor needs a restart to notice.)
2. Open the biome you want, for example `res://levels/design/level_mine_blockout.tscn`.
3. The **Mine Level** dock appears on the right.

The diagram you see is drawn at runtime and is never saved. Everything under
`DesignVisuals` is rebuilt from the authored nodes each time something moves, so
you cannot damage the design by deleting it.

## The three things in the scene

| Node | Is | Notes |
|---|---|---|
| `MineSpace` | a graph node | `kind` says whether it is a room, a junction, or a dead-end pocket. `radius` 0 means a bare corner with no chamber - a decision point that is not a place. `vertical_scale` 1.0 is a sphere; below it the chamber is an oblate blob, `radius` across and `radius * vertical_scale` from centre to roof. |
| `MineTunnel` | a graph edge | Names its two ends. It does **not** store their coordinates, so dragging a room drags every tunnel attached to it and the two can never disagree. `height` 0 means square; set it and the bore is `width` across by `height` tall. |
| `MineBend` | a corner | A `Marker3D` child of a tunnel. Deliberately not a graph node: a corner you fly round is not a route choice. Child order is the order the tunnel runs through them. |

`length_metres` on a tunnel is read-only and always derived. Tunnel length is
what decides whether the creature can hear you, so a hand-typed length that had
drifted from the geometry would quietly corrupt every sound answer.

**`width` is the load-bearing number; `height` is shape only.** Creature fit and
the width colour mode both read `width` and ignore `height` - a creature that fits
through the width of a 20 x 3 hive bore is not helped by it being 20 wide. Height
exists because the ravine is a tall slot and a hive stratum is a flat one, and
neither reads as itself with a square bore.

**`vertical_scale` on a space is the same distinction, for chambers.** `radius`
stays the horizontal one and is still what the gizmo handle drags and what the
straight-line hearing model measures; `vertical_scale` only squashes the chamber
towards its own floor. It exists because a hive chamber has to be wide *and* flat,
and a sphere large enough to read as a room in a 6 m stratum domes through the
roof and floor either side of it. The mines and the ravine leave it at 1.0, where
it is exactly the sphere it always was.

## Selecting and moving things in the viewport

**This needs the plugin actually loaded.** Ticking it in `project.godot` is not
enough for an editor that is already open - toggle **Mine Level Designer** off and
on in Project Settings > Plugins, or restart Godot. Without it, spaces and tunnels
cannot be clicked at all and the Scene dock is the only way to select them.

With it loaded:

- **Click a room's sphere or a tunnel's tube** to select it, then move it with the
  normal `W` gizmo. Tunnels follow the rooms they join, so you only ever drag
  rooms and bends.
- **Overlapping volumes**: click again in the same spot to cycle to the next thing
  behind. A hive stratum's wide flat bores overlap a great deal and will take the
  first click off anything inside them.
- **Drag the orange handle** on a selected space to change its `radius`, or on a
  selected tunnel to change its `width`. Both are undoable.
- **Bends** are `Marker3D`s and were always clickable - drag them like any node.
- Moving a **tunnel node itself** does nothing, because its shape comes from its
  two ends. If you do it by accident you get a warning triangle in the Scene dock
  telling you to reset the transform.

The wireframe circles and centrelines are the gizmo. The solid transparent tubes
and spheres, and all the text, are the level's own drawing and are not clickable.

## Building with it

- **+ Room / + Junction / + Dead end** drop a space in front of the camera.
- **Connect selected** takes exactly two selected spaces and makes the tunnel.
  This is the main way to build - you should never type a NodePath.
- **Add bend** drops a corner at the midpoint of the selected tunnel, inserted at
  the right point in the run. Drag it like anything else.
- **Split tunnel** cuts the selected tunnel in two at a new junction in the
  middle, in one undoable step. Both halves keep the original's width, height,
  tags and colour, and the corners go to whichever half they fall in - so
  splitting a winding tunnel leaves its shape exactly where it was. **The new
  junction has no radius, so the carved geometry does not change**: a split is a
  statement about the graph, not about the shape of the level. Give it a radius
  afterwards if you want a chamber there.
- Rough it in with the gizmo, then type exact numbers in the Inspector when a
  length matters.
- **Validate** reports duplicate names, half-wired tunnels, and any space with no
  route from the entrance.

Annotate with `notes` (free text) and `tags`. Tags drive colour: set colours for
named tags on the level root, and any tag without one gets a stable colour from
its own name, so colour coding works before anything is configured.

**`notes` belongs to whoever is designing the level.** The generators do not
write it and nothing regenerates it, so a note on a space or a tunnel is a
message to the team and stays that way. Reasoning that belongs to the generator
lives in comments in the `build_*_blockout.gd` files instead, where it never
reaches the scene.

## Colour modes

`Uniform`, `Tag`, `Width`, `Depth`, `Creature passable`, `Sound`.

**Creature passable** compares each tunnel against `creature_min_width` on the
level root, seeded at 6.4 m. That threshold is one level-wide number, not a
per-tunnel flag - when the creature turns out to be a different size, move the
slider and the whole map recolours. That is the intended way to find out what a
change to the creature breaks.

## The sound preview

Loudness is **a radius in metres**: how far a source can still be heard. That is
the same unit `core_loop_noise.gd` already uses, so no conversion happens
anywhere. Drill and crank are 60 m, sprint 20 m, thrust 12 m.

Select a space or a tunnel, press **Use selection as noise origin**, pick a
source. The level recolours by how much of the noise survives the trip, and
tunnels split at the edge of what can hear it - a tunnel is not audible or not as
a unit, and where the creature happens to be along it is the whole question.

The dock prints two lines:

```
through tunnels:  6/15 spaces, 212/987 m
straight line:   11/15 spaces, 548/987 m
```

**The gap between them is a bug in the shipping prototype, not a display
option.** `core_loop_noise.gd` emits a noise event as a plain radius, so the
creature currently hears through solid rock. The second line is what the game
does today; the first is what it should do. This is open design question #5.

## Flying it

`level_walkthrough.tscn` carves a blockout out of solid rock and drops a zero-G
suit in at the entrance. Open it and press play.

WASD + space/ctrl to thrust, mouse to look, Q/E to roll, shift to stabilise, R to
respawn at the entrance, escape to release the mouse. **M** shows and hides the
map, **N** puts names on its spaces, **-** and **=** zoom it.

Knobs on the root node:

- **`level_scene`** is which blockout gets walked. Point it at any design scene
  whose root is a `MineLevel`; nothing in the scene is wired to a particular one.
- **`view_distance_metres`** is how far you can see. The mines were laid out
  assuming you only ever see a fraction of one drift, so **20 m is the number to
  *judge* the layout at**. A few hundred is the number to *survey* it at and
  check the shape came out the way the plan says.
- **`show_design_overlay`** draws the annotated graph - labels, colour coding,
  the lot - on top of the carved rock.
- **`show_minimap`** puts the plan view in the corner. On by default.

### The map

`level_minimap.gd` draws a plan of the level in the corner and your suit on it,
from the graph rather than from the carved rock - so it costs a few hundred 2D
draw calls and no second camera.

**Depth is a fade, not a cut.** Everything is drawn, but spaces and tunnels more
than 25 m above or below you dim towards a floor of 12%. The stratum you are in
reads solid and the ones it is stacked on read as ghosts, which is the only way a
flat plan says anything useful about the hive or the ravine. Colours are the
level's own `color_mode`, so the map agrees with the editor viewport rather than
inventing a second scheme.

The map shows the whole level from the first frame, visited or not: the question
it answers is whether the layout came out the way it was drawn, not what a player
would know.

It centres on the level while the whole level fits and follows the suit once you
zoom past that. The readout gives the space you are in - or how far you are from
the nearest one when you are mid-tunnel - the depth, and the metres across.

To start somewhere other than the entrance, change `entrance_space` on the
blockout. It is the spawn point, so it doubles as a teleport - which is how you
get to the far end without flying 2,800 m at 4 m/s.

The rock itself comes from `LevelGeometryBuilder`, which carves every span of
every tunnel as a pair of CSG brushes: a solid hull and a narrower bore that
hollows it out. All the hulls union, then all the bores subtract, so a bore can
never reach past its own hull and a junction needs no seams lined up. The
technique is `prototypes/core_loop/core_loop_tunnels.gd`; what is different is
that this one reads the `LevelGraph`, so the space you fly through and the graph
the sound model runs on are the same description.

Tunnels carrying any tag in `round_profile_tags` on the builder get a **round**
bore and everything else gets a **square** one. Today that is `natural`, `hive`,
`winding`, `warren` and `biome_link`. The mines were cut by machine and the
naturals were not, and from the inside that is most of what tells you which one
you are in. The ravine is split rather than listed whole: its side network was
worn out of the rock and rounds, while the chasm runs stay square, because the
flat floor and flat walls are what make the chasm read as a chasm.

**Overrun at a joint is mitred.** A span reaches past its own junction far enough
that its cross-section covers the corner and no further, which for a bore turning
through an angle is half its extent across the bend times the tangent of the half
angle - capped at the blunt half-width this used to always use, because a mitre
grows without bound as a joint approaches a hairpin. Measuring it on the widest
face instead overruns a tall slot by half its HEIGHT however gentle the bend is,
and the ravine's chasm runs then carved twelve-metre spurs of air out through the
wall at every station. `verify_walkthrough.gd` prints the worst offenders; a wide
run near the top of that list with a gentle bend is the bug coming back.

**This is a blockout, not shipping geometry.** The full carve is 246 brushes,
about 300 ms and 23k triangles. Fine for walking the level, not fine for a web
build - baking to static meshes is the way out when that matters.

## Tools

Run from the project root:

```
godot --headless --path . --script res://tools/level_design/test_level_graph.gd
godot --headless --path . --script res://tools/level_design/validate_level.gd
godot --headless --path . --script res://tools/level_design/verify_walkthrough.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd -- --mode=sound
godot --headless --path . --script res://tools/level_design/export_layout_snippet.gd
godot --headless --path . --script res://tools/level_design/report_sound_reach.gd
godot --headless --path . --script res://tools/level_design/report_annotations.gd
godot --headless --path . --script res://tools/level_design/export_level_model.gd
```

Every tool except the test takes `-- --level=res://...` and defaults to the mine
blockout. Outputs are named after the level they came from, so running one across
all three biomes does not overwrite anything.

`render_level_maps.gd` also takes `--mode=` and `--tags=`:

```
# just the upper mine level, in context
... render_level_maps.gd -- --tags=mines_a,entrance,natural,biome_link
```

**Use `--tags=` for anything with stacked levels.** Both mine levels sit on the
same survey grid, so in plan every lower junction lands exactly under an upper
one and the labels are unreadable. Real mine plans are drawn one level to a
sheet; this is how to do that. The elevation panel is fine unfiltered.

- `render_level_maps.gd` writes a plan and elevation SVG to
  `documentation/design/images/`, named for the colour mode, for the design doc.
- `export_layout_snippet.gd` writes a `ROUTES`/`CHAMBERS` table to
  `documentation/design/mine_blockout_layout.gd.txt`, in the shape
  `prototypes/core_loop/core_loop_knobs.gd` uses. Diff it and take across what
  changed; it deliberately never rewrites that file, whose comments carry design
  reasoning a generator would delete.
- `report_sound_reach.gd` writes the through-tunnel and straight-line numbers for
  every space and every noise source, as markdown for the design doc.
- `validate_level.gd` is the dock's **Validate** button from the command line:
  duplicate names, half-wired tunnels, and any space with no route from the
  entrance. Reachability is the one a composed level gets wrong, and nothing else
  in a headless run would notice a biome that is joined to nothing.
- `report_annotations.gd` writes the `notes` on every space and tunnel out as
  markdown, plus a full index of both keyed by world position, to
  `documentation/design/<level>_annotations.md`. **That document is how
  annotations reach anyone working outside Godot** - a `.gltf` carries geometry
  and nothing else, and once the CSG is resolved there are no names left in it at
  all. The document and the model are built from the same graph at the same scale
  about the same origin, so a coordinate in one is a coordinate in the other.
- `export_level_model.gd` bakes the carve to a single static mesh and writes it as
  glTF Separate to `assets/art/environment/level_blockout/`, following the
  static-mesh rules in `documentation/pipeline/pipeline.yaml` because the pipeline
  has no phase covering a level exported as a model. **Corners come out sharp** -
  CSG has no fillet operator and tessellation is the only knob it has. Dulling
  them is a Bevel modifier in Blender, and the recipe is in the annotations
  document.
- `verify_walkthrough.gd` proves the carve is flyable without a human at the
  mouse: it drops a suit-sized sphere at the middle of every tunnel and the
  centre of every space and fails on anything that comes back solid. That is the
  failure worth catching - a level that looks carved in the viewport but has a
  plug of rock across one drift. Re-run it after moving anything.
- `build_mine_blockout.gd` is the mines **as data** - grid
  columns, rows, per-node depths, widths, and the natural tunnels with their
  corners. No logic; `blockout_scaffold.gd` does the building.
  **Change the numbers and re-run with `-- --force` while the layout is still
  being roughed out**; once you start moving things in the editor, stop, because
  it overwrites. It refuses to run over an existing scene without `--force` for
  that reason.
- `build_ravine_blockout.gd` and `build_hive_blockout.gd` are the same thing for
  the other two biomes, writing their own scene files. Each is only data.
- `blockout_scaffold.gd` is the builder every biome file shares. It knows three
  shapes, and free-form spaces and tunnels that can say anything at all:

  | Spec key | Shape | Used by |
  |---|---|---|
  | `grids` | a rectangle of drifts crossed by cross-cuts | the mines |
  | `chains` | spaces in a line, each joined to the next | the ravine's chasm |
  | `strata` | staggered sheets of scattered blobs, breached into each other | the hive |

  `strata` is the one that is generated rather than laid out: the spec gives
  ranges and a seed and `strata_layout.gd` works out the chambers, which is why
  the hive file has no coordinates in it. That module returns plain records and
  never touches the scene tree, so a layout can be re-rolled and measured without
  a level being built.

  A free-form tunnel whose `bends` is a **number** rather than an array gets that
  many generated corners, straying `wander` metres from `seed`. That is how the
  ravine's side tunnels wind without anyone typing sixty coordinates, and the seed
  is in the spec so re-running produces the same level rather than a new one.

  A biome whose structure is a different *idea* again needs either a fourth shape
  or to be drawn in the viewport, and for something irregular the viewport is the
  better answer.
- `check_sightlines.gd` raycasts the carved rock between named spaces. Sightline
  is a design property in every biome and the one thing a coordinate table cannot
  tell you, so the claims in this file are measured rather than asserted:

  ```
  ... check_sightlines.gd -- --level=res://levels/design/level_ravine_blockout.tscn \
      --pairs=rv_north_end,rv_south_end;rv_s1,rv_s3
  ```
- `import_core_loop_layout.gd` is the equivalent one-off for the core loop
  prototype's placeholder map, writing `level_core_loop_blockout.tscn`. It is
  deliberately not named after any biome: it is a yardstick, not a design.

## Starting a new biome

1. Copy whichever of the three `build_*_blockout.gd` files is closest in shape,
   and rename it.
2. Change the numbers, and `output_path` and `level_name` in `SPEC` at the bottom.
3. Run it. Nothing is shared between biomes except `blockout_scaffold.gd`.
4. Point a walkthrough's `level_scene` at the result, or pass `--level=` to any
   tool.

To write somewhere else without editing the file, both are overridable:

```
... build_mine_blockout.gd -- --out=res://levels/design/level_trial.tscn --name=Trial
```

## Reading it as data

`LevelGraph` (`level_graph.gd`) is the plain graph with no scene or editor
dependency - `MineLevel.build_graph()` produces one. It answers reachability,
creature fit at any threshold, and sound propagation. That is the thing to
consume from gameplay code, not the nodes.
