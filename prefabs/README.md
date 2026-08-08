# Prefabs

Contains scenes that are reusable and are expected to be instanced within other
scenes.

A prefab scene is a model container plus the scripts, collision, areas and
components that make it a working game object. The contract level design relies
on: **a prefab works as-is when dropped into a level**, with no per-placement
wiring.

`unity-prefab-organization-spec.md` is the Unity-flavoured version of the
organisation rules below, kept for reference. This file is the one that applies
here — same domain-first idea, Godot file naming.

## Naming

Godot files, so the repo-wide convention applies: lowercase, underscores between
words, `[prefix]_[asset_name]_[descriptor]_[variant]`.

```text
prefab_{object}.tscn
prefab_{object}_{variation}.tscn
```

```text
# Prefer
prefab_rain_barrel.tscn
prefab_office_building_small.tscn

# Avoid
rain_barrel_prefab.tscn      # prefix goes first
prefab_RainBarrel.tscn       # no PascalCase
prefab_rain-barrel.tscn      # no hyphens
prefab_rain_barrel.scn       # .tscn, text format
```

Do not confuse a prefab scene with the **model container scene** it instances.
The container reuses its mesh's full stem — `sm_rain_barrel.tscn` beside
`sm_rain_barrel.gltf` in `assets/art/{category}/{object}/` — and stays there. The
prefab lives here, under `prefabs/`.

## Every model needs a prefab

Only prefabs should be used in levels. A model container scene is a raw mesh with no gameplay behaviour, and is not a valid game object. A prefab wraps the container and adds the
components that make it a working object.

## Rules

1. **Organize prefabs by domain first.** Directory structure answers "what is
   this object used for?", not "what nodes does this scene contain?". A rubble
   chunk belongs under `environment/props/` whether it is a bare
   `MeshInstance3D`, has a `StaticBody3D`, or is a full `RigidBody3D` tumbling
   in zero-g.

2. **Categories mirror `assets/art/`.** The category names under `prefabs/` are
   the same ones used under `assets/art/{category}/{object}/`, so an object's art
   and its prefab are findable from either side.

```text
assets/art/environment/rain_barrel/sm_rain_barrel.gltf
assets/art/environment/rain_barrel/sm_rain_barrel.tscn   ← model container
prefabs/environment/prefab_rain_barrel.tscn              ← prefab
```

3. **Use subdirectories when a category grows.** Split by subdomain, not by
   implementation:

```text
environment/
  ship/
  asteroid/
  crystals/
  props/
  backdrop/
```

4. **Prefer descriptive names.** The name identifies what the object represents
   and, where useful, its variation. Do not encode implementation details:

```text
# Prefer
prefab_rock_large.tscn

# Avoid
prefab_rock_large_with_collider.tscn
prefab_rock_large_no_rigidbody.tscn
```

5. **Gameplay-significant variants may be named explicitly.** When two rocks are
   genuinely different gameplay objects rather than different configurations of
   one, the distinction belongs in the name:

```text
prefab_rock_static.tscn
prefab_rock_physics.tscn
prefab_rock_destructible.tscn
```

This is appropriate when designers deliberately choose among them as different
concepts.

6. **Keep raw assets out of `prefabs/`.** Meshes, textures, materials,
   animations, audio and their `.import` sidecars stay in their own asset
   directories. `prefabs/` holds `.tscn` files, and scripts that exist only to
   serve one prefab.

## Example structure

The 3D assets on the art list, placed. `#` marks the ones the list has as
optional.

```text
prefabs/
│
├── environment/
│   ├── ship/
│   │   ├── prefab_ship_exterior.tscn
│   │   ├── prefab_ship_cockpit.tscn
│   │   ├── prefab_ship_airlock_eva.tscn
│   │   └── prefab_ship_crew_seat.tscn
│   │
│   ├── asteroid/
│   │   ├── prefab_asteroid_exterior.tscn
│   │   └── prefab_asteroid_tunnel.tscn
│   │
│   ├── crystals/
│   │   ├── prefab_crystal_a_small.tscn
│   │   ├── prefab_crystal_a_medium.tscn
│   │   ├── prefab_crystal_a_large.tscn
│   │   ├── prefab_crystal_b_small.tscn
│   │   ├── prefab_crystal_b_medium.tscn
│   │   ├── prefab_crystal_b_large.tscn
│   │   └── prefab_crystal_heart.tscn
│   │
│   ├── props/
│   │   ├── prefab_rubble01.tscn
│   │   ├── prefab_rubble02.tscn
│   │   ├── …
│   │   ├── prefab_rubble10.tscn
│   │   ├── prefab_gas_vent.tscn                  # optional
│   │   ├── prefab_rock_formation_unstable.tscn   # optional
│   │   └── prefab_cave_fungus.tscn               # optional
│   │
│   └── backdrop/
│       ├── prefab_starfield.tscn
│       └── prefab_asteroid_field_distant.tscn
│
├── characters/
│   ├── prefab_player.tscn
│   │
│   └── creatures/
│       ├── prefab_creature_stalker.tscn
│       └── prefab_critter_ambient.tscn           # optional
│
└── gameplay/
    ├── prefab_mining_laser.tscn
    ├── prefab_tank_power_oxygen.tscn
    ├── prefab_tether_cable.tscn
    ├── prefab_flare.tscn
    ├── prefab_canister_resource.tscn             # optional
    ├── prefab_derelict_part.tscn                 # optional
    └── prefab_remains_skull.tscn                 # optional
```

2D assets — HUD, menu art, VFX textures, marketing — are not prefabs and do not
appear here.

`_a` and `_b` stand in for the two crystal colours until art names them; once
named, use the colour (`prefab_crystal_azure_small.tscn`). `environment/props/`
mirrors `assets/art/environment/props/`, where the ten rubble meshes already
live.

Nothing here is pre-created. Add a category directory when you have a prefab to
put in it.

## Placement decision

```text
What is this prefab?

Floating rubble chunk
→ environment/props/

Mineable crystal
→ environment/crystals/

Cockpit, airlock, crew seat
→ environment/ship/

Distant asteroid field backdrop
→ environment/backdrop/

Stalking creature
→ characters/creatures/

Digging laser the player carries
→ gameplay/

Tether cable
→ gameplay/
```

When an object could plausibly fit several directories, classify it by its
**primary gameplay role**. The mineable crystals carry mining behaviour but read
as part of the asteroid, so they stay under `environment/`; the tether and the
power-oxygen tank are equipment the player operates, so they are `gameplay/`
even though they are visually props. The distinction is semantic, not which
nodes are attached.

## See also

- `documentation/pipeline/PIPELINE.md` — the authoritative pipeline, including
  the step that creates a prefab scene and the naming patterns it enforces.
- `assets/art/` — models, textures, and the model container scenes prefabs
  instance.
- `levels/` and `test/levels/` — where prefabs get placed.
