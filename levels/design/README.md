# Level blockouts

**`level_asteroid_blockout.tscn` is the design of record.** It is the shape of the
level, annotated, as a graph that keeps its 3D coordinates. It is not finished
geometry and does not try to be.

(`level_mine_blockout.tscn` is the older map the core loop prototype actually
plays, kept for reference. Every tool takes `-- --level=res://...` to point at it.)

## What is in the asteroid blockout so far

Three biomes hang off one central vertical cavern. Only the **mines** are built.

| | |
|---|---|
| **Central cavern** | `cavern_ceiling` / `upper` / `lower` / `floor`, a 150 m vertical column at the origin joined by 30 m-wide shafts. Both mine levels open onto it. |
| **The mines** | Two levels of surveyed workings, west of the cavern. Upper level `a_*`, lower level `b_*`. |
| **The ravine, the hive** | Not built. `link_ravine` and `link_hive` are stub dead ends marking where the mines hand over, tagged `unbuilt`. |

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

## Opening it

1. Project > Project Settings > Plugins, tick **Mine Level Designer**. (It is
   already on in `project.godot`; a running editor needs a restart to notice.)
2. Open `res://levels/design/level_mine_blockout.tscn`.
3. The **Mine Level** dock appears on the right.

The diagram you see is drawn at runtime and is never saved. Everything under
`DesignVisuals` is rebuilt from the authored nodes each time something moves, so
you cannot damage the design by deleting it.

## The three things in the scene

| Node | Is | Notes |
|---|---|---|
| `MineSpace` | a graph node | `kind` says whether it is a room, a junction, or a dead-end pocket. `radius` 0 means a bare corner with no chamber - a decision point that is not a place. |
| `MineTunnel` | a graph edge | Names its two ends. It does **not** store their coordinates, so dragging a room drags every tunnel attached to it and the two can never disagree. |
| `MineBend` | a corner | A `Marker3D` child of a tunnel. Deliberately not a graph node: a corner you fly round is not a route choice. Child order is the order the tunnel runs through them. |

`length_metres` on a tunnel is read-only and always derived. Tunnel length is
what decides whether the creature can hear you, so a hand-typed length that had
drifted from the geometry would quietly corrupt every sound answer.

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

`level_walkthrough.tscn` carves the blockout out of solid rock and drops a zero-G
suit in at the entrance. Open it and press play.

WASD + space/ctrl to thrust, mouse to look, Q/E to roll, shift to stabilise, R to
respawn at the entrance, escape to release the mouse.

Two knobs on the root node:

- **`view_distance_metres`** (20 m) is how far you can see. The mines were laid
  out assuming you only ever see a fraction of one drift, so 20 m is the number
  to *judge* the layout at. Wind it up to a few hundred to *survey* it and check
  the shape came out the way the plan says.
- **`draw_when_running`** on the blockout node overlays the annotated graph -
  labels, colour coding, the lot - on top of the carved rock.

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

Every tool except the test takes `-- --level=res://...` and defaults to the
asteroid blockout. Outputs are named after the level they came from.

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
- `build_asteroid_blockout.gd` is the scaffold that laid out the cavern and the
  mines from a spec at the top of the file - grid columns, rows, per-node depths,
  widths, and the natural tunnels with their corners. **Change the spec and
  re-run with `-- --force` while the layout is still being roughed out**; once you
  start moving things in the editor, stop, because it overwrites. It refuses to
  run over an existing scene without `--force` for that reason.
- `import_core_loop_layout.gd` is the equivalent one-off for
  `level_mine_blockout.tscn`, seeded from the core loop prototype.

## Reading it as data

`LevelGraph` (`level_graph.gd`) is the plain graph with no scene or editor
dependency - `MineLevel.build_graph()` produces one. It answers reachability,
creature fit at any threshold, and sound propagation. That is the thing to
consume from gameplay code, not the nodes.
