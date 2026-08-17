# prefab_alien

The alien, as a gray sphere. Placeholder art around a real navigation agent.

```
prefab_alien (Node3D)               metadata/placeholder = true
└── AlienBody (CharacterBody3D)     layer 5 "creature", masks layer 1 "hull"
    ├── sm_alien_greybox            SphereMesh, radius = the profile's normal radius
    ├── CollisionShape3D            SphereShape3D, same radius
    ├── AlienNavAgent               plans, steers, and drives AlienBody
    └── Sfx                         three AudioStreamPlayer3D channels, all on SFX
        ├── MovementLoop            runs while the body is under way
        ├── Voice                   alerted, and the cry on a strike
        └── Attack                  the tentacles
```

## What it sounds like, and what does not drive it yet

`Sfx` (`alien_sfx.gd`) is the same one-player-per-channel shape as the player's.
The movement loop is self-driving — it follows `AlienNavAgent.actual_speed()`, and
"near" is the channel's `max_distance` rather than a radius test, so distance
decides who hears it.

`alert()` and `attack()` are the whole rest of the interface, and **nothing calls
them**. There is no perception layer and no attack: this prefab plans routes and
that is all. When that lands it calls these two, and `attack()` is deliberately
two channels so the voice and the tentacles land together without cutting each
other off.

`Alien_Movement_Near_Loop.wav` is imported with **Loop Mode: Forward**. The
importer enum is offset from `AudioStreamWAV.LoopMode` — `2` in the `.import`
file is `LOOP_FORWARD` (`1`) on the resource.

## Drop it in and it works

`AlienNavAgent.graph_source` is deliberately **left empty**. On `_ready()` the agent looks
for a `NavigationVolumeBaker` in the `alien_navigation_world` group, binds to its graph, and
re-binds whenever it bakes again. That is what lets this prefab satisfy the contract in
`prefabs/README.md` — it works as-is when dropped into a level, with no per-placement
wiring — while still planning against whatever cave it lands in.

Give it somewhere to go with `set_destination(point)` or `follow(node)`.

## Two deviations from prefabs/README.md, both deliberate

- **The root wraps a body, not a model container scene.** That rule is about static props
  inheriting from a `sm_*.tscn`; a character needs a physics body, and a `Node3D` root
  wrapping one is the closest honest reading of the same rule.
- **The mesh is built in this scene rather than in an `assets/art/` model container.** It is
  a `SphereMesh`, not art. When the real alien arrives, replace `sm_alien_greybox` with an
  instance of its model container and delete the `SphereMesh` — nothing else here changes,
  because the agent reads its dimensions from the profile resource and not from the mesh.

## The size is data, and it is derived

`alien_clearance_profile.tres` holds the only dimensions that matter:

| | | |
|---|---|---|
| `normal_radius_equivalent` | 0.85 m | 1.70 m across the body |
| `squeezed_radius_equivalent` | 0.35 m | 0.70 m compressed |
| `safety_margin` | 0.05 m | added to both in every clearance test |

A 1.00 m reduction in diameter between the two, which is the design spec's §6 figure. Those
numbers are not taste — they are derived from the bores in the prototype cave and from how
much the clearance field underestimates a passage. `AlienClearanceProfile`'s own docstring
carries the table and the arithmetic; read it before changing them, and re-run
`prototypes/alien_ai_pathfinding/tools/bake_probe.tscn` afterwards.

With `resize_body_to_profile` on (the default) the mesh and the collision shape follow
`normal_radius_equivalent` at runtime, so changing the profile visibly resizes the sphere
instead of leaving the art disagreeing with the navigation.

## Collision layers

`AlienBody` is on layer 5 (`creature`) and masks only layer 1 (`hull`). It deliberately does
**not** collide with the player: this prototype is about routing, and a creature that shoves
the player around would confuse the two.
