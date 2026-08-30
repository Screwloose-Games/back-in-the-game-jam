# The clinger

`SURFACE FAUNA, MINOR`, which is what the company calls it in system text and is the
intro's established habit of reclassifying the alarming into the routine.

It sits dormant on rock until something makes a noise, crawls to it, leaps at any suit
inside `clinger_jump_range`, and rides the visor draining air, charge and health until the
player mashes it off. It cannot kill you. The mining beam kills it.

Specified in `documentation/design/environmental-storytelling.md` §4.

## What is here

| | |
|---|---|
| `prefab_clinger.tscn` | The prefab. A `CharacterBody3D` on layer 5 wrapping `assets/art/character/clinger/sm_clinger.tscn`. Drop it in a level; it needs no per-placement wiring. |
| `clinger.gd` | `Clinger` — the phase machine, the crawl, the leap, `take_mining_damage`, death. **The only thing that writes the body's transform.** |
| `clinger_legs.gd` | `ClingerLegs` — poses the eight legs. Curled when dormant, flat when crawling, thrown across a visor when attached. |
| `components/clinger_ears.gd` | `ClingerEars` — binds the player noise emitters and holds what each last said. |
| `components/clinger_grip.gd` | `ClingerGrip` — everything that happens while it is on a face: the drains, the press count, the peel. |

The arithmetic all of it runs on is in `systems/clinger/`, where it can be tested without
a scene. Every tunable number is in the **Clinger** group on
`prefabs/character/player/player_settings.gd`; this directory carries geometry, timing and
one per-placement flag (`starts_dormant`), which is the split `GasPod` and `ArcHazard`
already use.

## The five things that are load-bearing

**It is never on physics layer 1.** `NavigationSource.bake()` runs once against
`WORLD_MASK = 1` in `AsteroidLevel._start_creature()` and nothing re-bakes, so a clinger on
`hull` freezes into the stalker's graph as permanent solid rock — that then walks away.
Layer 5, `creature`, and cleared to nothing while attached or dead.

**Place it before it enters the tree.** The crawl owns the transform and writes its own
`_position` back over the node every frame, so assigning `global_position` after
`add_child` fails silently and the creature walks back where it was. A placement authored
into a level scene is fine — `_ready` reads the pose it arrived with. At runtime, use
`teleport()`. Same contract, and the same reason, as `CrawlerBody.teleport()`.

**The collider has to be narrower than the lift.** The body holds its origin
`ClingerSurface.SURFACE_LIFT + BODY_HALF_THICKNESS` off the rock. A wider shape starts
every leap already embedded in the wall it is pushing off, `move_and_collide` reports a hit
on the launch frame, and it lands again immediately — a creature that twitches and never
attacks, with nothing in the log. `_ready` warns rather than trusting the `.tscn`, because
an editor save drops scene comments.

**It never reparents anything and never touches `HeadCamera`.** While attached it reads
`ClingerGrip.anchor_transform()` off the player's `Head` and drives its own body from it,
at `process_physics_priority = 120` — after `PlayerCollisionResponse` (100), which owns
`move_and_slide`, and `PlayerHealth` (110). That keeps it a level-owned node with its own
lifetime, so a respawn that teleports the suit, or a player freed outright, costs one field
write instead of tree surgery.

**Attached, it is off every collision layer, and that is deliberate.** It stops the suit
colliding with a shape sitting inside its own 0.4 m hull, and it stops the mining ray
finding it. `PlayerMiningTool.query_beam_hit()` passes no mask and excludes only the player
body, so a live shape 30 cm from the visor would be the first thing the beam hit every
time — and burning one off your own face would be strictly better than mashing, which
deletes the struggle outright. The beam is the answer while it crawls; mashing is the
answer while it is on you.

## What it hears, and what it says

It reads the same stream the stalker does — `PlayerNoiseEmitter` and
`PlayerBeamNoiseEmitter`, duck-typed on `noise_emitted` — and **holds** what each last
reported, because an emitter only re-announces on a level change. A held drill announces
once and then goes silent, so a listener that treats the signal as a stream hears nothing.
`ClingerEars` binds through `SceneTree.node_added` as well as the group, because a level
spawns its player long after a placed creature has readied.

It is deliberately deaf to `world_noise`; one that listened to that group would spend the
run hunting its own leap.

It **emits** `world_noise` and joins `HazardDamage.NOISE_GROUP`, so
`AsteroidLevel._wire_hazard_noise()` pipes a leap, every struggle press and its death
straight into the stalker's perception with no new code. That is §4's best line made
mechanical: thrashing is loud, so a player who panics escapes fast and arrives somewhere
worse, and a player who stays calm loses more air and stays invisible.

## Struggling

Any already-bound action counts as one press — no new binding, and no QTE overlay, meter or
prompt, which §4 rejects as the most gamey object available. `PlayerInput` reads it
**above** its own `enabled` guard, because whatever takes the suit away also makes every
branch below unreachable and mashing has to stay readable exactly then.

The clinger does not lock the input. Thrust still works while you are wearing one; that is
the design, and it also sidesteps a real trap — `PlayerInput.enabled`'s setter is
`value and not locked`, so anything still holding `locked` when `PlayerLife._revive()` runs
swallows the revive in silence and the player spectates for the rest of the session. The
grip releases on both `PlayerLife.died` and `PlayerRespawn.respawned` regardless, and
`tests/verify_clinger.gd` pins it.

## Checking it

```
godot --headless --path . res://tests/run_tests.tscn        # the pure suites
godot --headless --path . res://tests/verify_clinger.tscn   # end to end, in a real scene
godot --path . res://levels/hazard_sandbox/hazard_sandbox.tscn
```

The runtime suite must be run as a **scene**. A node added during
`SceneTree._initialize()` never receives `_ready()`, so `--script` runs nothing, prints
nothing and exits 0 — which looks exactly like a pass.

In the sandbox it is on the ceiling, dormant, and `starts_dormant` is the switch to flip
while iterating.
