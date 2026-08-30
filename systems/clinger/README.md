# systems/clinger

The clinger's pure core: its phases, the arithmetic behind every transition between them,
and the tangent-plane maths a body crawling on walls runs on. No node, no `SceneTree`, no
physics query — so the whole transition table can be driven by a test that never builds a
scene.

| | |
|---|---|
| `clinger_state.gd` | `ClingerState` — the `Phase` enum and the guards: what wakes it, when it may leap, how far one press peels it, what a per-second rate costs over a frame. |
| `clinger_surface.gd` | `ClingerSurface` — projecting a heading into the surface it is holding, building a basis from a normal, slewing between two without shearing, and the fourteen-ray fan directions. |

The node half is `prefabs/character/clinger/`, which owns the transform and every physics
query. Nothing here reaches back the other way.

## Two things that are easy to get wrong here

**`basis_from` must be right-handed.** Forward and up can both be correct in a basis whose
determinant is `-1`, and the only symptom is a single-sided mesh rendering its own
interior — which reads as an art bug, in a file nobody would open looking for one.
`SurfaceCrawlController._basis_from` in `gameplay/creature/navigation/` writes the mirrored
order and is right to: that module only ever reads the two vectors back out and never
applies the basis as a transform. This one is applied, so the order differs deliberately.
`test_clinger_surface.gd` pins it.

**Every degenerate input has to return a direction rather than a NaN.** Two exactly
opposed vectors have no unique rotation axis; a heading parallel to the surface normal has
no tangent. Normalising either zero returns NaN, and a NaN in an orientation never
recovers — it poisons every frame after it and the creature simply disappears. Each such
case has a named fallback and a test.

## Why this is not `gameplay/creature/`

`documentation/design/environmental-storytelling.md` §4 is explicit: the clinger is not
built on that module. Its five-state HFSM, suspicion board, hotspot field and A* navigator
are written around the stalker fantasy and would be dead weight on a thing whose entire
life is wake, crawl, latch. The maths in `clinger_surface.gd` is deliberately a rewrite of
`SurfaceCrawlController`'s rather than an import — `verify_navigation_static.gd` also fails
the build for anything under that module naming a physics query outside
`navigation_probe.gd`, and the clinger needs its own.

## Tests

```
godot --headless --path . res://tests/run_tests.tscn
```

`tests/test_clinger_state.gd` and `tests/test_clinger_surface.gd`. The end-to-end suite is
`tests/verify_clinger.tscn`, which needs a real scene and lives with the prefab.
