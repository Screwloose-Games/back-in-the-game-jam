# Mine level blockout

`level_mine_blockout.tscn` is the level design: the shape of the mine, annotated,
as a graph that keeps its 3D coordinates. It is not finished geometry and does
not try to be.

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

## Tools

Run from the project root:

```
godot --headless --path . --script res://tools/level_design/test_level_graph.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd
godot --headless --path . --script res://tools/level_design/render_level_maps.gd -- --mode=sound
godot --headless --path . --script res://tools/level_design/export_layout_snippet.gd
```

- `render_level_maps.gd` writes a plan and elevation SVG to
  `documentation/design/images/`, named for the colour mode, for the design doc.
- `export_layout_snippet.gd` writes a `ROUTES`/`CHAMBERS` table to
  `documentation/design/mine_blockout_layout.gd.txt`, in the shape
  `prototypes/core_loop/core_loop_knobs.gd` uses. Diff it and take across what
  changed; it deliberately never rewrites that file, whose comments carry design
  reasoning a generator would delete.
- `import_core_loop_layout.gd` is the one-off that seeded this scene from the
  core loop prototype. **The scene has been the source of truth since.** It
  refuses to run over an existing file without `-- --force`.

## Reading it as data

`LevelGraph` (`level_graph.gd`) is the plain graph with no scene or editor
dependency - `MineLevel.build_graph()` produces one. It answers reachability,
creature fit at any threshold, and sound propagation. That is the thing to
consume from gameplay code, not the nodes.
