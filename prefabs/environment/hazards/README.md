# Hazards

Three hand-placed objects that turn set dressing into a reason to route around a
tunnel, from [§2 of the environmental storytelling
doc](../../../documentation/design/environmental-storytelling.md). All three are
**placeholder geometry** — Godot primitives, no glTF — so the silhouettes are stand-ins
and the behaviour is not.

| Prefab | What it is | How it goes off |
|---|---|---|
| `prefab_gas_pod.tscn` | A pressurised bubble welded to a wall | Cut it, touch it, or linger inside its proximity ring. Damage and a tumble inside `blast_radius`, plus a very loud noise. |
| `prefab_arc_hazard.tscn` | A burst cube's cable, still live | Nothing. It arcs on its own now and then, and holds while you are inside the field, draining suit charge the whole time. |
| `prefab_blockage.tscn` | Collapsed rock sealing an optional route | Mine it open. Loud, slow and expensive — see below. |

## Where the numbers live

**Damage and drain rates are on `PlayerSettings`**, in the `Hazards` group, validated by
its `invariant_failures()`. One tuning surface, and no per-prefab copy of a figure to
drift. A hazard reads the rate off the settings resource of whoever it is billing:

```gdscript
health.take_damage(health.settings.hazard_gas_pod_damage * damage_scale * share, ...)
```

**Everything a placement owns is on the prefab**: geometry, radius, timing, toughness,
loudness — plus a `damage_scale` / `drain_scale` multiplier, so one cable can be nastier
than another without a second source of truth for the base figure.

## Hazards never write player state

A hazard calls a public method on a player component and nothing else. `HazardDamage`
(`systems/hazards/hazard_damage.gd`) is the only file that knows the player prefab's node
names, using the same group-then-named-child lookup `LifeSupportCube.tethered_players()`
already uses:

```gdscript
HazardDamage.players(get_tree())      # every body in group "player"
HazardDamage.health_of(body)          # -> PlayerHealth,       .take_damage()
HazardDamage.power_of(body)           # -> PlayerPowerClient,  .spend()
HazardDamage.shove(body, from, force) # -> PlayerLocomotion.apply_external_impulse()
```

Nothing here touches `body.velocity` or `angular_velocity`. `PlayerLocomotion` owns the
tumble, which is why the shove goes through it — and why the impulse is applied *at* the
blast's position, so the lever arm tumbles the suit away from wherever the blast was
rather than spinning it about nothing.

## Layer 10, `hazard`

Gas pods and blockages sit on layer 10 with an empty mask; `PlayerBody` masks it (its
`collision_mask` is 541 rather than 29 for exactly this).

**Not layer 1 `hull`, and the reason is the navigation bake.** `NavigationSource.bake()`
runs once, in `AsteroidLevel._start_creature()`, against `WORLD_MASK = 1`, and nothing
re-bakes. A blockage on layer 1 would be baked as permanently solid, so mining it open
would never restore the graph edge and the level would carry a route the creature can
watch the player use and never follow. On layer 10 the bake ignores hazards entirely,
which is also the right answer for a gas pod — a prop is not a nav obstacle.

The tradeoff, recorded rather than hidden: **the creature can squeeze past a plug the
player cannot.** That is the better of the two failures.

The mining beam finds them regardless — `PlayerMiningTool.query_beam_hit()` passes no
mask, so it hits every layer. It does *not* hit areas, though, which is why a gas pod is
a `StaticBody3D` with a separate `Area3D` for the strike sensor rather than an Area alone.

The tether rope masks layer 1 only, so rope passes through hazards.

## Noise

Each prefab declares `signal world_noise(at: Vector3, loudness: float)` and joins
`HazardDamage.NOISE_GROUP`. `AsteroidLevel._wire_hazard_noise()` connects them straight
into `CreaturePerception.receive_noise()` — **not** through `PlayerNoiseRelay`.

Two reasons, both load-bearing, both written out in that function:

1. The relay clamps loudness to 1.0 and `mining_noise_strength` already sits at that
   ceiling, so a detonation routed through it could not out-shout the beam that set it
   off. `CreatureHearing` clamps only the *received* strength, so a raw `2.5` handed in
   directly genuinely carries farther. That is why `noise_loudness` defaults above 1.0.
2. The relay attributes every channel to a player, while `NoiseEvent` documents
   `source_player` as null for world noises. A pod billed to the player who lit it could
   become a hunt target through the Director's arbitration.

The relay also *holds* a channel and re-announces it on an interval, which would make one
explosion audible every half second for the rest of the run.

**The arc is deliberately silent to the creature.** §2 never says it is loud, and a
permanently-audible hazard would flood the creature's evidence ring. It is *not* silent
to the player — see below.

## Three ways a gas pod goes

| Trigger | Warning | Callable off? |
|---|---|---|
| **Cut** past `pod_health` | `cut_fuse_seconds` (0.35 s) | No. A cut commits. |
| **Contact** with the bubble | none | n/a — immediate |
| **Proximity** for `proximity_fuse_seconds` (2 s) | the pod swells, throbs faster and hisses | Yes — leave the ring and it resets |

A pod's size and reach are **central settings**, not prefab numbers:
`PlayerSettings.hazard_gas_pod_diameter` (0.9 m) and
`PlayerSettings.hazard_gas_pod_trigger_range` (1.0 m). The prefab points its `settings`
export at `player_settings.tres`, so a pod is sized and armed from the same resource the
suit is tuned with. Per placement there is only `trigger_range_scale`, the same
central-figure-times-a-scale shape the damage and drain numbers use.

`hazard_gas_pod_trigger_range` is measured from the pod's centre, so the band you can
occupy *without* already touching it is that minus `gas_pod_contact_distance()` — half the
bubble plus the suit's 0.4 m hull, 0.85 m at the shipped figures. Going under that is a
silent way to lose the entire warning, because the contact trigger fires first and the
countdown never gets a turn. **`invariant_failures()` checks it**, and there is a test for
it, because that bug shipped once already.

Flying straight at one still detonates it on contact; the countdown is for someone who
**stops** next to one — which is exactly the player who parked to mine the ore beside it.

### How the size is applied

The dome mesh is authored **one metre across** and the `Shell` node is *scaled* by the
diameter rather than the mesh being rebuilt: every pod then shares one mesh, and the base
scale composes with the swell the countdown animates. Collision spheres cannot be sized
that way — Godot warns, and it does not work — so those are resized instead, which is why
all three are marked `resource_local_to_scene = true`. Without that flag a `.tscn`
sub-resource is **shared across every instance of the scene**, and one pod's
`trigger_range_scale` would silently overwrite every other pod's ring.

### One of two leaving is not the all-clear

`any_trigger_in_proximity` is derived from the occupant list, never from whichever signal
fired last. `body_entered` appends and `body_exited` erases; the flag is
`not _occupants.is_empty()` afterwards. With two suits inside, one leaving changes nothing
— which is the case a naive boolean gets wrong, and gets wrong silently.

The list is filtered for freed instances on every change, so a player who disconnects or
dies inside the ring cannot leave a pod armed forever.

## Pods live on walls

A pod is a hemisphere whose flat base sits at its own origin and domes along **+Y**, so
placing one is a matter of putting its origin on the rock with +Y along the surface normal.
`GasPod.surface_transform()` builds exactly that, and `nearest_surface()` finds the rock
with the same both-ends Fibonacci-sphere probe `MineralDeposit` uses — the trimesh is
backface-blind, so a pod already inside rock can only see the face it is behind from the
far side.

Both are **static**, which is the point: the inspector's *Snap to Nearest Wall* button and
a headless placement pass share one copy of the maths. The pods currently in the asteroid
level and the sandbox were positioned by that pass rather than by hand.

## Why the arc tells the player it has them

An arc costs about 3 HP and 15.5% of the battery for a straight crossing. The health
tick is small on purpose, and small enough that none of the normal feedback fires: the
damage overlay only flashes past `flash_min_severity`, and the visor draws nothing
above 75% health. Left alone, an arc is a hazard you cannot feel.

So `ArcHazard` calls `PlayerHealth.electrify()` every frame it bills. That latch lapses
on its own after `ELECTRIFIED_HOLD`, so nothing has to remember to switch it off — not
a hazard that gets freed, and not a player who dies inside one. It drives two things:
the `Electrified` HUD overlay, and a looping helmet cue on `PlayerSfx`.

The cue is `assets/vo/vo_electrified_loop.wav`, imported with `edit/loop_mode=1` so it
loops seamlessly. It routes to **SFX**, not Dialogue, despite the `vo_` prefix: the
Dialogue bus is the ELEVATOR SYSTEM's, and this is the suit you are inside. It has its
own `AudioStreamPlayer` rather than sharing the helmet channel, because a loop has to
be able to overlap the one-shots.

The idle cadence matters for the same reason. At `idle_interval_s = 1.5 ± 0.8` with a
`0.5 s` burst the bolt is lit roughly a quarter of the time; at the original `4 ± 2`
with a `0.35 s` burst it was lit 9% of the time, and a hazard nobody can see is one
nobody can price.

**A blockage needs no noise of its own while it is being cut.**
`PlayerBeamNoiseEmitter` already reports the cut at the beam endpoint at full
`mining_noise_strength`, so mining one open is already the loudest sustained thing in the
game. The one `world_noise` it emits is the collapse.

## Why a blockage is expensive without any code saying so

At the shipped mining figures, `blockage_health = 25.0` is 25 seconds of held beam and
200 charge against a `suit_capacity` of 100. You physically cannot finish one on a single
battery: you are tethered, or you are making trips. A mineral chunk, for scale, is 5.

## Placement

Hand-placed under `AsteroidLevel/Hazards/MineBlockout`, mirroring how `Minerals` is
organised. Nothing at `mine_mouth` and nothing in `drift_a_m_1` — §5 is explicit that the
car must read as absolute safety and that the first tunnel is where the player is still
learning what a wall is.

**Blockages go on optional routes only.** Both current placements were checked against the
tunnel table in `documentation/design/level_full_blockout_annotations.md`: `pocket` keeps
three routes and level B keeps `winze_deep` and `nat_drop_part2`, so neither can strand a
run.

There is no scatter tool. `MineralZoneRule` weights placements by the region tags
(`entrance`, `drift`, `cavern`, `refuge`) and is the obvious upgrade path if the list
outgrows hand placement.

## Placeholder marking

Each root carries `metadata/placeholder = true`. There is no model container to pair with,
so `tools/placeholder-art/audit_placeholders.py` lists them under "prefabs instancing no
container" — which is honest output, and that bucket never fails a build. Roots are
already the **final** node type (`StaticBody3D`, `Node3D`) so real art can be dropped in
without a new file and a new `uid`.

The arc's cue is `Cube_Operating_Loop.wav` borrowed from the power cube — a stand-in hum,
not a considered choice. All three reuse shipped audio, so no new asset touches the audio
validator.
