# creature_navigation

Click a wall; watch the alien work out how to get there.

The creature can squeeze, mode transition and leap.

```
godot --path <repo root> res://prototypes/creature_navigation/creature_nav_demo_prototype.tscn
```

## Two scenes

| | |
|---|---|
| `creature_nav_demo_prototype.tscn` | **The tour.** Everything the module does, on a hand-tabled cave of convex boxes. Read on. |
| `creature_nav_source_demo_prototype.tscn` | **The component.** `NavigationSource`, baking a graph from an arbitrary concave mesh that changes at runtime — see [below](#creature_nav_source_demo). |

## Controls

| | |
|---|---|
| **RMB** or **T** | send the creature to whatever you are pointing at |
| **LMB** | mine (`F3` toggles brush size) |
| WASD / Space / Ctrl | thrust · **Q/E** roll · **Shift** sprint |
| Esc | release the mouse (both then pick under the cursor) |
| 1–5 | send the creature to each room |
| F1 / F2 | world-graph overlay · locomotion + leap overlay |
| F3 / F4 | mining brush size · believed graph vs world graph |
| R | rebake |

## What to try, in order

1. **`1` — the Gallery.** `SURFACE_CRAWL` → `TUNNEL_SWIM` → `SURFACE_CRAWL` as it centres
   itself in the 6 m bore and comes out the far side. (Scenario A)
2. **`2` — the Warren.** It stops at the 2 m tunnel and *visibly shrinks* before entering,
   crosses slowly, then expands. The label reads `squeeze 60%` while it compresses.
   (Scenario B)
3. **`3` — the Vent Loft.** The route comes back **PARTIAL** and the creature stops at the
   1 m slot rather than grinding into it. Fly through yourself to prove the opening is
   real. Nothing anywhere flags that slot as player-only — it is simply narrower than the
   alien's compressed body. (Scenarios C and G, Invariant 5)
4. **`4` — the Gallery ceiling.** It leaps rather than crawling round the walls. Now drag
   **`leap_bias`** up in the tuning panel until it stops leaping: that flip point is
   §11.4's "roughly 10 m of crawling saved". Push it far enough and the panel warns you by
   name that §43's Scenario D no longer holds. (Scenarios D and E)
5. **Mine, then press `F4`.** With `use_knowledge` on, the world graph gains the new
   passage immediately and the believed graph does not. The alien has to *find out*.
   (Scenario F, Invariant 8)

## The map

Four rooms, three tunnel sizes, one table in `creature_nav_demo_map.gd`.

```
                                    Vent Loft   (player-only, above the Gallery)
                                         ║ 1 m slot
   Dock ═══ 6 m swim tunnel ═══════ Gallery
     ║                                   ║
     ║ 2 m wiggle tunnel                 ║ 6 m back run (L-shaped)
     ║                                   ║
   Warren ══════════════════════════════╝
```

The three bores are chosen against the shipped `ClearanceProfile`: the normal body needs
**2.5 m**, the squeezed body **1.5 m**, and the player's hull **0.8 m**.

## Two things that are not obvious

**Every tunnel's cross-section is centred on even world coordinates.** §12.1's candidate
lattice snaps to world-space multiples of `candidate_spacing` (2 m), so a passage whose
centre line misses the lattice contains no candidate and **does not exist** to the graph.
Moving a tunnel by one metre is how you delete it.

**Visuals are CSG; collision is convex boxes.** Both are generated from the same table, so
they cannot drift. `NavigationProbe.is_solid` is exact for convex colliders and impossible
for concave ones — measured, not assumed, and pinned by
`gameplay/creature/navigation/tools/verify_navigation_csg.tscn`. A CSG collider is a
concave trimesh, so a point deep inside rock measures as wide-open and the bake scatters
phantom nodes through the walls. The scene below is the one that does *not* dodge that.

## What it deliberately does not have

No behaviour system, so nothing answers §30's inspection request — the inspector's own
timeout resolves it after four seconds, which is why an inspection completes at all. No
perception, so `observe_geometry_batch` is wired and never called; knowledge changes only
by inspection. No AI goal selection: you are the behaviour layer, and where you point is
the goal.

Technical detail lives in the script docstrings, and the numbers live in
`creature_nav_demo_knobs.gd` and the navigation module's `LocomotionProfile`.

---

# creature_nav_source_demo

**What we drop into the real level.** The answer is `NavigationSource`, a `Node3D` in
`gameplay/creature/navigation/`, and this scene is that node doing its job against an
arbitrary concave mesh that changes while the alien is using it.

```
godot --path <repo root> res://prototypes/creature_navigation/creature_nav_source_demo_prototype.tscn
```

The cave is one `CSGCombiner3D` with **`use_collision = true`** — curved, off-axis,
concave, and collided against as the trimesh the engine generates. Three chambers carved
from one block by spheres and cylinders; mining appends another sphere and Godot rebuilds
the whole thing.

## What it is demonstrating

**One bake, shared.** The creature's `CreatureNavigation` has `source` set and owns no
builder, no patcher and no graph — only a route and a belief. A second creature added to
this scene would share the graph rather than re-bake the cave.

**A graph with nothing in the rock.** Press `F1`. Then set `use_flood = false` on the
source, press `R`, and look again: the §12.1 lattice sweep fills the stone. That is not a
bug in the sweep, it is what an overlap test does to a mesh with no interior — a point deep
inside touches no triangle, so `shape_fits` says it fits and `clearance_at` returns the
ceiling, and §12.2 sorts by clearance *descending*, so those points are kept first and
evict the real ones. `NavigationSource` floods from air seeds instead, which never asks the
question. Measured on this cave: **145 nodes from 1 332 samples flooded, against 2 949
nodes from 16 027 samples swept.**

**Invariant 5 on a trimesh.** Chamber C sits behind a 1.2 m bore. The alien's squeezed body
needs 1.5 m, so no edge crosses it and key `3` returns a PARTIAL route — while chamber C is
*full* of nodes (15 of them), because the flood's 0.25 m passage probe crosses the bore
happily. Reachability is decided by §13.2's swept bodies, not by the sampler. Fly through
the bore yourself to prove the opening is real.

**Scenario F.** Mine anywhere. The source patches the shared graph within a second and the
creature re-plans; it never re-bakes anything.

## Two things that are not obvious

**The tight bore is axis-aligned and the wide one is not.** §12.1's lattice is snapped to
world multiples of `candidate_spacing`, and the flood steps between adjacent lattice cells
— so a 1.2 m tube running diagonally contains no two consecutive lattice points and the
flood cannot follow it. At 6 m the wide bore has room for the lattice at any angle. A
passage the alien is meant to *squeeze* through has to be built on the lattice.

**"Has the collider appeared yet?" cannot be asked with an overlap test.** CSG rebuilds its
trimesh during `_process` and hands it to Jolt on the step after, and a bake against a
collider that is not there yet does not error — it returns a graph full of nodes in solid
rock. The obvious poll, `shape_fits` at the dig centre, answers *yes* before the carve, after
the carve, and in an empty world, for the same reason the sweep fills the stone. This scene
polls with a six-ray fan instead. Counting frames, which is what the rest of the repo does,
is a measurement rather than a contract.
