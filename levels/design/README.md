# Level blockouts

**One scene per biome, each edited independently.** Each is the shape of that
biome, annotated, as a graph that keeps its 3D coordinates. None of them is
finished geometry and none tries to be.

| Scene | Biome | Size |
|---|---|---|
| `level_mine_blockout.tscn` | The mines, plus the central cavern | 30 spaces, 54 tunnels, 2,853 m |
| `level_ravine_blockout.tscn` | The ravine | 19 spaces, 24 tunnels, 1,592 m |
| `level_hive_blockout.tscn` | The hive | 54 spaces, 113 tunnels, 4,426 m |

**Only the mines carry the central cavern**, and only because they were built
before that idea was in question. The ravine and the hive assume nothing about how
the biomes join: each has `link_*` dead-end stubs tagged `unbuilt` marking where a
connection would land. Stitching them into one scene is a separate job.

(`level_core_loop_blockout.tscn` is the small placeholder map the core loop
prototype actually plays. It is not in the repo - `import_core_loop_layout.gd`
regenerates it - and it is kept only so the real biomes can be measured against
something that has been played. Every tool takes `-- --level=res://...`.)

## What is in the mine blockout

| | |
|---|---|
| **The mines** | Two levels of surveyed workings. Upper level `a_*`, lower level `b_*`. |
| **Central cavern** | `cavern_ceiling` / `upper` / `lower` / `floor`, a 150 m vertical column at the origin joined by 30 m-wide shafts. Both mine levels open onto it. |
| **Handovers** | `link_ravine` and `link_hive` are stub dead ends marking where the mines pass to another biome, tagged `unbuilt`. |

**The cavern is here only because this biome was built before that idea was in
question.** The ravine and the hive assume nothing about how the biomes join, and
if the cavern goes, it comes out of this file rather than out of all three.

### Reading a mine node name

`a_c3_n` = level **a** (upper), cross-cut column **c3**, drift row **n** (north).
Rows are `n` / `m` / `s`; columns run `c1` (far from the cavern) to `c4` (nearest).

### How the mines are shaped

- **Drifts** run east-west toward the cavern, 9 m and square. Three of them.
- **Cross-cuts** ("strip mines") run north-south between the drifts, 7 m and
  square, crossing every drift. Three are cut to 4.5 m and are refuges.
- **x and z are exact; y is not.** The workings were surveyed, so they line up in
  plan, but they follow the seam in section and sag eastward and southward by
  around 20 m. That is what stops the biome reading as one flat floor, and it is
  most of why it is disorienting despite being the legible biome.
- **Natural tunnels** (tagged `natural`, curved, orange) cut diagonally across the
  grid, ignoring it entirely. **They get denser toward the cavern** - one out at
  c1-c2, two across c2-c3, three across c3-c4 - so the closer you get to the
  middle the less the survey grid helps you.
- **Winzes** are vertical shafts joining the two levels at three junctions:
  `winze_deep` (by the entrance), `winze_north`, and `winze_south` (5 m, the only
  way to change level while being chased).
- Two natural tunnels also fall between levels **without** being winzes
  (`nat_drop_south`, `nat_drop_mid`). They are not on the survey, and taking one
  puts you a level down and two columns from where you think you are.
- `fork_south` and `fork_deep` are natural cavities where a tunnel splits: one
  branch into the cavern, one branch **around** it to another biome. That is how
  you leave the mines without ever crossing the middle of the map.

Rooms and junctions are nodes, tunnels are edges. That is a real graph, so the
creature AI and the noise system can walk it, and it is also a real scene, so it
is authored by dragging things in Godot's 3D viewport.

## How the ravine is shaped

One chasm, **12 m across and 48 m floor to roof**, running 440 m north to south
and falling 60 m as it goes. It is a chain of nine stations rather than one space,
so where you are along it is something the graph can answer.

The stations drift up to 13 m either side of the axis. Measured on the carved
rock, that is enough: **you can see the next station 58 m away and never the one
after it**, and end to end is blocked after 24 m. Relatively straight, and never
straight enough to see across.

Off its sides, winding tunnels run out to `knot_*` junctions where two or three
meet, on to `pocket_*` rooms, and back into the chasm further along. Their widths
sit deliberately either side of the 6.4 m the creature needs, so which of them is
a refuge and which is a trap is the question the side network exists to ask.

## How the hive is shaped

Seven layers over 150 m. Each is a hub with a ring of cells joined by bores
**26 m across and 5 m floor to roof** - so a layer is one flat cavity you cross in
any direction, not a ring of tunnels.

No layer sits squarely on the one below: every one is offset, turned, and a
different size and squash. Measured on the carved rock, there is **no sightline
between any two layers at all**, while layer 4 is **91 m clear across its wide
axis**. That is the pancake, and it is why this is the most disorienting biome -
in the mines you are lost about where, here you are lost about which layer, and
every layer looks like the answer.

Risers between layers are spread round the rim rather than stacked, so leaving a
layer is a choice of several doors and none is obvious. The `long_*` tunnels skip
two to four layers; coming up one puts you somewhere that looks like where you
started and is 60 m from it.

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
| `MineSpace` | a graph node | `kind` says whether it is a room, a junction, or a dead-end pocket. `radius` 0 means a bare corner with no chamber - a decision point that is not a place. |
| `MineTunnel` | a graph edge | Names its two ends. It does **not** store their coordinates, so dragging a room drags every tunnel attached to it and the two can never disagree. `height` 0 means square; set it and the bore is `width` across by `height` tall. |
| `MineBend` | a corner | A `Marker3D` child of a tunnel. Deliberately not a graph node: a corner you fly round is not a route choice. Child order is the order the tunnel runs through them. |

`length_metres` on a tunnel is read-only and always derived. Tunnel length is
what decides whether the creature can hear you, so a hand-typed length that had
drifted from the geometry would quietly corrupt every sound answer.

**`width` is the load-bearing number; `height` is shape only.** Creature fit and
the width colour mode both read `width` and ignore `height` - a creature that fits
through the width of a 26 x 5 hive layer is not helped by it being 26 wide. Height
exists because the ravine is a tall slot and a hive layer is a flat one, and
neither reads as itself with a square bore.

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
  behind. The cavern spheres are 20-25 m across and will take the first click.
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
- Rough it in with the gizmo, then type exact numbers in the Inspector when a
  length matters.
- **Validate** reports duplicate names, half-wired tunnels, and any space with no
  route from the entrance.

Annotate with `notes` (free text) and `tags`. Tags drive colour: set colours for
named tags on the level root, and any tag without one gets a stable colour from
its own name, so colour coding works before anything is configured.

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
respawn at the entrance, escape to release the mouse.

Knobs on the root node:

- **`level_scene`** is which blockout gets walked. Point it at any design scene
  whose root is a `MineLevel`; nothing in the scene is wired to a particular one.
- **`view_distance_metres`** is how far you can see. The mines were laid out
  assuming you only ever see a fraction of one drift, so **20 m is the number to
  *judge* the layout at**. A few hundred is the number to *survey* it at and
  check the shape came out the way the plan says.
- **`show_design_overlay`** draws the annotated graph - labels, colour coding,
  the lot - on top of the carved rock.

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

Tunnels tagged `natural` get a **round** bore and everything else gets a
**square** one (`round_profile_tags` on the builder). The mines were cut by
machine and the naturals were not, and from the inside that is most of what tells
you which one you are in.

**This is a blockout, not shipping geometry.** The full carve is 246 brushes,
about 300 ms and 23k triangles. Fine for walking the level, not fine for a web
build - baking to static meshes is the way out when that matters.

## Tools

Run from the project root:

```
godot --headless --path . --script res://tools/level_design/test_level_graph.gd
godot --headless --path . --script res://tools/level_design/verify_walkthrough.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd -- --mode=sound
godot --headless --path . --script res://tools/level_design/export_layout_snippet.gd
godot --headless --path . --script res://tools/level_design/report_sound_reach.gd
```

Every tool except the test takes `-- --level=res://...` and defaults to the mine
blockout. Outputs are named after the level they came from, so running one across
all three biomes does not overwrite anything.

`render_level_maps.gd` also takes `--mode=` and `--tags=`:

```
# just the upper mine level, in context
... render_level_maps.gd -- --tags=mines_a,cavern,entrance,natural,biome_link
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
- `verify_walkthrough.gd` proves the carve is flyable without a human at the
  mouse: it drops a suit-sized sphere at the middle of every tunnel and the
  centre of every space and fails on anything that comes back solid. That is the
  failure worth catching - a level that looks carved in the viewport but has a
  plug of rock across one drift. Re-run it after moving anything.
- `build_mine_blockout.gd` is the mines and the cavern **as data** - grid
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
  | `layer_stacks` | offset flat layers of hub-and-ring, joined by risers | the hive |

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
