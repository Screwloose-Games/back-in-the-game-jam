# Creature Navigation

How the alien works out a way to get somewhere, given what it believes about the cave.
It derives every bit of its topology from terrain — no hand-placed nodes, portals or
tunnel markers — and it decides what fits by sweeping the creature's actual collision
shapes rather than by casting rays.

Spec: [`documentation/design/alien/navigation.md`](../../../documentation/design/alien/navigation.md).
Section numbers below refer to it.

```
        terrain (physics colliders)
                  │
            NavigationProbe        the only file allowed to query the world
                  │
           NavGraphBuilder         §12 candidates → §12.2 decimation → §13.2 edges
                  │
              NavGraph             §15 sparse topology + AStar3D, in seconds
             ╱        ╲
      RoutePlanner   RouteFollower §16 attachment, §17 route, §18-19 consumption
                  │
          CreatureNavigation       the facade: replan triggers, locomotion, signals
```

**Two facades, and the split is per-level versus per-creature.** `NavigationSource` goes in
the level and owns the probe binding, the bake, the patcher and `world_graph`.
`CreatureNavigation` goes on the creature and owns the route, the belief, the inspection
chain and the local planner; point its `source` at the level's and it stops baking. Leave
`source` null and it bakes for itself, which is exactly the phases 1–7 behaviour and is what
every test, the sandbox and both runtime verifiers still do.

## Scope: §41 phases 1–9

All nine phases are implemented. In dependency order:

| Phases | What | Where |
|---|---|---|
| 1–2 | clearance sampling, the candidate lattice, decimation, the sparse `AStar3D` graph, shape-cast edge validation, endpoint attachment, monotonic waypoint following, locomotion-aware smoothing | `graph/`, `route/` |
| 3–6 | surface crawl, tunnel swim, wiggle, leap, and the local planner that chooses between them | `locomotion/` |
| 7 | runtime graph patching after mining | `graph/nav_graph_patcher.gd` |
| 8–9 | the believed graph, and the inspection chain that updates it | `knowledge/` |
| 35 | imperfect route selection | `route/nav_route_chooser.gd` |
| 39 | the two overlays | `debug/` |

**Not** implemented, and deliberately not stubbed into something that appears to work: the
behaviour system that would choose goals (§33) and answer §30's inspection requests, and
the perception wiring that would feed `observe_geometry_batch`. Both are other modules'
jobs; navigation exposes the seams and calls neither.

**`use_knowledge` defaults to `false`.** With it off, the planning graph IS the world
graph and the alien is omniscient about geometry — which is how phases 1–7 behaved, and
why turning phase 8 on is a decision rather than a side effect. Every test and both
runtime suites run with it off; `tests/test_knowledge.gd` runs it both ways.

## Running the suites

```sh
GODOT=/path/to/Godot   # 4.7.x

# A new class_name does not resolve until the project is re-imported, and the same run
# generates the .uid sidecars the static suite checks for.
$GODOT --headless --path . --import

$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
$GODOT --headless --path . --script res://gameplay/creature/navigation/tools/verify_navigation_static.gd
$GODOT --headless --path .         res://gameplay/creature/navigation/tools/verify_navigation_runtime.tscn
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable
script prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml`
greps the output for that reason.

**The runtime suite must be run as its `.tscn`.** A node added during
`SceneTree._initialize()` never receives `_ready()`, so `--script` on
`verify_navigation_runtime.gd` runs nothing, prints nothing and exits 0.

## Looking at the overlay

Drive it by hand:

```sh
$GODOT --path . res://gameplay/creature/navigation/sandbox/navigation_sandbox.tscn
```

or render the six canonical shots to `user://` (**not** `--headless` — there is no
framebuffer to read back in that mode):

```sh
$GODOT --path . res://gameplay/creature/navigation/tools/capture_sandbox.tscn
```

§39 calls the overlay part of the implementation rather than optional polish, and it is
right to: every interesting navigation failure passes the unit suite. A graph that
connects across a crevice, an endpoint attached through a wall, a route that never
smooths — each produces a creature that heads plausibly toward roughly the right place.

**The shot that matters is `04_slot_impassable`.** Chamber B's graph above, chamber C's
graph below, and nothing whatsoever between them. If a line crosses that 1 m opening,
Invariant 5 is broken, Scenarios C and G are broken, and nothing in `tests/` will have
told you — the alien will simply have started working better. The same check by hand is
key `2`: the route to chamber C must come back PARTIAL and stop at the wall.

The second thing is the tunnel pair, `02` and `03`. **Read them as a comparison, not
individually.** Green edges must cross the 6 m tunnel, and *no* green may cross the 2 m
one. Both tunnels also carry amber edges and that is correct rather than a smell — a
6 × 6 opening has corner pockets a metre from two walls at once, so a node lands in one
and every edge reaching it is a squeeze. What would be wrong is green through the tight
tunnel, which means the normal body is being validated against a passage it does not
fit. The runtime suite asserts both halves numerically, because the amber makes the
picture alone ambiguous.

Two defects were found by looking at these and by nothing else: the sandbox camera left
at its default rotation, facing away from the entire cave while the panel cheerfully
reported a thousand edges; and the first pair of tunnel vantages, which looked along the
divider and stacked the two openings on top of each other so the amber cluster appeared
to be crossing the wide tunnel.

## Six deliberate deviations from the spec

**1. Clearance is sampled sparsely, not built as a field.** §4 asks for a 0.24 m
occupancy grid feeding a 3D distance transform. A 30 m cave is ~2M cells and GDScript
cannot walk that inside §32's 10 ms by any route. Clearance is instead measured only at
the candidate lattice points, by bisection on a growing sphere in `NavigationProbe`
(~8 queries per open point). §5.1 licenses this outright — the field "does not need
voxel-perfect precision because exact traversal feasibility will later be validated by
collision shape casts". The two consumers that want a continuous field, medial tunnel
centering (§9) and local candidate ranking (§21), are phase 3–4 and want it *locally
around the body* rather than baked over the cave.

**2. `Creature*` / `Nav*` rather than the spec's `Alien*`.** Godot's `class_name` table
is flat and project-wide, so a collision is a parse failure across the whole project.
This matches the two shipped sibling modules, and §37 calls its own list "recommended"
structure. Names this module reserves project-wide: `CreatureNavigation`,
`NavigationProbe`, `NavigationConfig`, `NavigationDebugDraw`, `NavigationDebugPanel`,
`NavigationSandbox`, `NavigationSandboxGeometry`, `ClearanceProfile`, `NavLocomotion`,
`NavInspectionRequest`, `NavNode`, `NavEdge`, `NavGraph`, `NavAStar`, `NavGraphBuilder`,
`NavRoute`, `NavRouteSegment`, `RoutePlanner`, `RouteFollower`.

**3. The bake is frame-budgeted; the A\* query is synchronous.** §31 permits async path
computation, but §15 also notes the graph is small enough for search cost to be
insignificant, and it is — the whole sandbox cave bakes in 24 ms and a route across it
is microseconds. Only `NavGraphBuilder` spends a per-frame budget.

**4. `max_neighbors` defaults to 12, not §13.1's six.** §13.1 offers six as "a simple
initial implementation" and insists the count stay configurable. Six is not enough here:
the node at the mouth of the 6 m tunnel has ten neighbours nearer than the node 6 m
straight down it, so nearest-first selection spends the whole budget before reaching the
one edge carrying the chamber-to-chamber connection at normal body size. The route
survived by detouring through a low-clearance corner and squeezing twice.

| `max_neighbors` | 6 | 8 | 10 | **12** | 16 | 24 |
|---|---|---|---|---|---|---|
| route cost (s) | 15.87 | 14.82 | 14.82 | **3.82** | 3.82 | 3.82 |
| bake (ms) | 18 | 18 | 19 | **19** | 23 | 28 |

§13.1's own suggested remedy — directional coverage instead of raw distance — was
implemented and measured, and changed nothing: all eleven candidates already lie in
distinct directions, so a sector filter has nothing to deduplicate. It was removed
rather than shipped as complexity with no effect. It remains the right answer for
graphs denser than this one.

**5. `can_skip_to` implements two of §19's four modes.** `WIGGLE` and `TUNNEL_SWIM` are
checkable with swept shapes today. `SURFACE_CRAWL` needs the phase 3 surface sampler and
`LEAP` needs the phase 6 planner, and both **refuse** rather than falling back to
permissive — a yes there is an alien drifting across open space, which Invariant 3
forbids and which no behavioural test would catch. §19's other tunnel-swim requirements
("navigable enclosed volume", "suitable medial route") are phase 4 and are not checked;
that is no more permissive than the baked `NORMAL_VOLUME` edges already are, because
§13.3 puts the crawl-versus-swim choice in the local planner rather than in the graph.

**6. A completed inspection learns a connected section, not §30's "nearby" data.** A ball
is the wrong unit. `NavKnowledgeGraph._observe_one` plants a suspected opening every
`node_separation` of free space the alien has no belief about, and each one is a §29 stop —
so a `relearn_radius` ball resolves the first 6 m of a 20 m tunnel and the alien stops
again a few metres in, six times, for one passage it is already standing in. One
continuous section is one thing to investigate. `learn_connected_region` therefore floods
outward from the seed ball through **world graph edges**, and it is the edges that make
this safe: §13.2 validates them with swept shapes, so following one says the body can
actually get from here to there at this size, where clustering the suspicion *points* by
distance would join two of them a metre apart through a wall.

Three things keep it from being omniscience by another name. It stops dead at anything
already believed — including `STALE`, because `age()` turns every memory `STALE` after a
few minutes and a flood that crossed it would hand over the whole cave on any late-run
inspection. What it learns beyond the seed ball is `PARTIALLY_EXPLORED`, not `KNOWN`:
routable at remembered cost, which is the honest record of having looked down a passage
rather than walked it. And it is bounded by `relearn_connected_radius` and
`relearn_max_nodes`, which set `NavKnowledgeUpdate.truncated` when they bite, so mining
into an unexplored cave system costs a second inspection further in rather than one glance
that reveals everything. `tests/test_connected_relearn.gd` is all of this.

## Rules the code enforces on itself

`tools/verify_navigation_static.gd` fails the build on each of these, because every one
of them would otherwise pass all 62 unit tests while destroying the property the tests
exist to protect.

| Rule | Why |
|---|---|
| Only `navigation_probe.gd` may name a physics or voxel query | The seam is what lets every other file be tested with no physics server **and no voxel extension** — `addons/zylann.voxel` is a GDExtension absent from the CI image |
| Only `creature_navigation.gd` calls `get_world_3d` | Same seam, from the other end |
| `graph/` never names a probe, a builder or the facade | The graph must not know where it came from. That is the entire mechanism behind Invariant 9: a believed graph and a real one are the same type |
| `route/` never names the builder | Planning must never trigger a bake, or a stale graph hides behind a frame spike instead of reporting a partial route |
| Nothing outside `tools/` reads a wall clock | `Time.get_ticks_msec()` ignores `get_tree().paused` and `Engine.time_scale`, and cannot be driven from a test |
| Nothing names `NavigationServer3D` / `NavigationAgent3D` / `NavigationRegion3D` | This module replaces Godot's navigation rather than wrapping it; a stray agent means two systems quietly disagreeing |
| The overlay sets `vertex_color_use_as_albedo` and is unshaded | Godot infers neither. Without them the overlay renders flat white and the wiggle-versus-normal edge colouring — §39's most useful signal — silently disappears |
| Every `.gd` has its `.uid` sidecar | A missing one is regenerated with a fresh id, and scenes referencing the script by uid then point at nothing |
| A default `NavigationConfig` satisfies its own invariants | |

`tests/test_navigation_invariants.gd` covers §42 — including a property sweep asserting
navigation declares no remembered player state, because a field named
`last_known_position` would make the alien omniscient in a way no behavioural test
catches. The creature would simply start working better.

## Known limits

**Concave trimesh interiors, and the flood that works around them.** `clearance_at` and
`shape_fits` are overlap tests, and a concave trimesh collider — which is what CSG and voxel
meshing both generate — has no interior to overlap. A point deep inside rock, far from any
triangle, measures at the clearance ceiling.

This README used to call that bounded, on the grounds that a phantom node inside rock cannot
connect to the real graph. That was wrong, and the reason is §12.2's ordering: decimation
sorts candidates by clearance **descending**, so a rock point measuring at the ceiling is
kept *first* and evicts every genuine candidate within `node_separation` of it. Measured on
`prototypes/creature_navigation`'s CSG cave: the sweep produced 2 949 nodes from 16 027
samples, 2 645 of them buried.

`NavGraphBuilder.begin_flood` stops asking. Instead of "is this point rock?" — which
`NavigationProbe.is_solid` genuinely cannot answer for a trimesh under Jolt, pinned by
`tools/verify_navigation_csg.tscn` — it asks "is this point reachable through air?", and
floods the §12.1 lattice outward from seeds the caller knows are open. Same lattice, same
candidate test, same decimation, same edge validation; only the enumeration differs, and
`tests/test_graph_flood.gd` asserts that a flood and a sweep of one connected pocket produce
identical graphs. The same cave floods to 145 nodes from 1 332 samples, none of them buried.

**A flood trusts exactly one thing, and it is the seed.** It cannot check: on a trimesh, two
cells buried in stone measure as open and a swept probe between them finds nothing in the
way. So `_passage_open` reads the clearance of the cell it is stepping *from* — already
validated, therefore genuinely in air — and never of the cell it is stepping *to*. Both
mistakes were made and both fill the rock: trusting the destination's clearance, and seeding
a dig AABB's corners, which for a sphere brush lie outside anything it carved.

`NavigationProbe.is_solid` therefore has no caller on the shipping path. It and the CSG
verifier are kept as the record of *why* the flood exists.

**A body displaced along its route does not skip ahead.** `RouteFollower` advances on
*arrival*, never by re-picking the nearest anchor, because §18 and §40.1 forbid the
latter. A body teleported down the route keeps targeting the anchor it was heading for
until smoothing clears a shortcut or §31 replans. A landing leap is handled — §31's
"locomotion transition requires reconsideration" forces a replan on the tick a flight
ends — so what remains is teleportation, which nothing in the game does.

## Getting stuck, and the four things that stop it

Every wedge this module has shipped had the same shape: a pose no mode could plan from,
and no way out of it, so the alien held a COMPLETE route and did not move again for the
rest of the run. Four mechanisms exist against that, and it is worth knowing which is
which when an alien is behaving oddly.

| Mechanism | Where | Against |
|---|---|---|
| **Adhesion** | `NavAvoidance.adhesion`, applied by both `SurfaceCrawlController` and `TunnelSwimController` | §8.1's "maintaining body contact". The module's definition of contact is "within tentacle reach" and nothing else closes the gap, so a body nudged outward drifts to the reach limit and then past it |
| **Two-sided recovery** | `NavLocalPlanner._back_off` and `_reacquire` | Too close to cast from, and too far to see anything. `is_slipped` is Invariant 3 as a predicate: the only legal unsupported state is airborne |
| **The escape fan** | `SurfaceCrawlController.steer` | The ±60° candidate arc, which contains nothing when the way out is behind. One retry per tick, at 360°, casting every candidate and ignoring `crawl_minimum_score` — a body with no legal move should take a bad move over no move |
| **The watchdog** | `NavProgressMonitor`, ticked by the facade | Everything above failing anyway. Displacement under a window, excluding deliberate stillness; on a trip it resets the mode, forces a replan and raises a §30 inspection |

`NavMotionCommand.recovering` and `NavProgressMonitor.trips` are both on the demo HUD, and
a trip count that climbs steadily is the difference between an alien having a hard time and
a bug the watchdog is papering over.

**An alien that stops on purpose, repeatedly, is the fifth shape and none of the four catch
it.** §29 has the body hold still for `mismatch_pause_time + inspection_timeout +
relearn_time` — 4.9 s at the defaults — and the watchdog deliberately excludes that
stillness, so an inspection raised on a loop reads as a creature frozen most of the time
with a zero wedge count. Every raiser is therefore required to be *edge*-triggered:
`NavInspector.report`'s dedupe rate-limits by place and time, which is a storm brake and
not a conclusion. `CreatureNavigation._report_stale_route` is the worked example — an
unreachable goal is discovered once and re-asked only when the goal or the terrain revision
changes. The HUD prints the reason beside the state (`inspecting (stale_route)`), because
the hold-still replaces the stalled command that caused it and `abort` reads `none` one
frame later.

## Wiring one up

```gdscript
var navigation := CreatureNavigation.new()
navigation.config = preload("res://.../my_alien_navigation.tres")
add_child(navigation)

navigation.graph_baked.connect(_on_graph_baked)
navigation.route_changed.connect(_on_route_changed)
navigation.inspection_requested.connect(behaviour.investigate)   # §30, phase 9

navigation.bake(cave_bounds)          # frame-budgeted; graph_baked fires when done
navigation.set_goal(suspected_position)   # §33: behaviour says where, navigation says how
```

Each tick, hand it where the body is. It replans on §31's triggers — goal change, the
target drifting past `target_move_threshold`, or the pursuit timer:

```gdscript
navigation.advance(delta, body.global_position)
var head_for: Vector3 = navigation.follower.current_anchor()
var segment: NavRouteSegment = navigation.follower.current_segment()
if segment != null and segment.requires_squeeze():
	body.compress()
```

**`current_anchor()` is not a position the body must pass through** (§2.2, Invariant 1).
Decimation keeps the *most open* candidate in each neighbourhood, so in a chamber the
anchor sits near the middle of the empty space while the alien would normally crawl a
wall six metres away. Steering at anchors produces an alien that visits the centre of
every room it crosses. Consuming them is the local planner's job, in phase 3.

## When Spatial Memory lands

`CreatureNavigation.graph` is an assignable field, and that is the whole of §26–§27's
split. Phases 1–2 bake it from real terrain, so the alien is temporarily omniscient
about geometry; phase 8 assigns a *believed* `NavGraph` there instead and not one line
of `graph/` or `route/` changes. `spatial_memory.md` §21 is explicit that Spatial Memory
must not itself contain an `AStar3D` — it owns remembered occupancy, and the navigation
graph is a derived cache of it. The static verifier's `graph/` and `route/` rules exist
to keep that seam usable.

## Putting it in the real level

`NavigationSource`. One node, in the level, holding the bake.

```gdscript
var source := NavigationSource.new()
source.config = preload("res://.../my_alien_navigation.tres")
source.air_seeds = PackedVector3Array([room_a, room_b])   # or add Marker3D children
add_child(source)
source.bake(level_bounds)

navigation.source = source        # every creature; they share the one graph
```

Terrain changed? `source.notify_terrain_changed(brush_bounds)`. The region **must be centred
on the change** — when a patch finds no existing node inside it, that centre is the only seed
there is.

**Do not whole-level bake a streaming terrain.** An unloaded chunk has no collider, and no
collider is not rock — it is a vacuum. Every cell in it measures at the clearance ceiling,
the free-ball early accept fires unconditionally, and the flood fills the unloaded volume
with maximum-clearance candidates that then sort first in decimation. Leave `bake_bounds` at
zero and call `notify_terrain_changed(block_aabb)` once per chunk as it becomes resident: the
graph grows with the streamed world, through machinery that is already additive-only
(Invariant 6) and already frame-budgeted (`patch_queries_per_frame`).

## Not included

`prototypes/creature_navigation/creature_nav_source_demo_prototype.tscn` is all of the above
against a runtime-modified concave CSG cave, so the seams are exercised. What is not wired is
`prototypes/voxel_cavern`, which still drives its alien with `WallNavmeshBaker` plus one of
Godot's own agents — it cannot express body-size gating and it is stale the moment the player
mines. It is the remaining customer.
