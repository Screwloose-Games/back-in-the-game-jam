# Prefabs

Contains scenes that are reusable and are expected to be instanced within other
scenes.

A prefab scene is a model container plus the scripts, collision, areas and
components that make it a working game object. The contract level design relies
on: **a prefab works as-is when dropped into a level**, with no per-placement
wiring.

The organisation rules below started as a Unity-flavoured spec; this is the Godot
version and the one that applies here — same domain-first idea, this repo's file
naming.

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
├── character/
│   ├── prefab_player.tscn
│   │
│   ├── alien/                                    # exists
│   │   └── prefab_alien.tscn
│   │
│   └── creatures/
│       ├── prefab_creature_stalker.tscn
│       └── prefab_critter_ambient.tscn           # optional
│
├── gameplay/
│   ├── prefab_mining_laser.tscn
│   ├── prefab_tank_power_oxygen.tscn
│   ├── prefab_tether_cable.tscn
│   ├── prefab_flare.tscn
│   ├── prefab_canister_resource.tscn             # optional
│   ├── prefab_derelict_part.tscn                 # optional
│   └── prefab_remains_skull.tscn                 # optional
│
└── ui/
    └── hud/                                      # exists
        ├── prefab_hud_02.tscn
        ├── prefab_hud_03.tscn
        └── prefab_hud_04.tscn
```

2D **assets** — HUD art, menu art, VFX textures, marketing — are not prefabs and
do not appear here; they live under `assets/art/`, same as the 3D art.

A screen-space **scene** is a different thing, and `ui/` is where it goes. A HUD
that drops into a level and works with no per-placement wiring meets the same
contract every other prefab does, so it is one — the rule is about raw assets, not
about which axis a scene draws on. The test is the contract, not the dimension:
if it needs wiring at each placement it is not a prefab wherever it lives.

`_a` and `_b` stand in for the two crystal colours until art names them; once
named, use the colour (`prefab_crystal_azure_small.tscn`).

Four of these exist today:

- `environment/props/` — `prefab_rubble01.tscn` … `prefab_rubble10.tscn`,
  mirroring `assets/art/environment/props/`.
- `environment/elevator/` — `prefab_elevator_car.tscn` and
  `prefab_wall_switch.tscn`. A subdomain rather than two loose entries under
  `environment/`, per rule 3: the switch has no meaning apart from the car it
  drives.
- `environment/hazards/` — `prefab_gas_pod.tscn`, `prefab_arc_hazard.tscn` and
  `prefab_blockage.tscn`. A subdomain rather than three loose entries under
  `environment/`, per rule 3: they share a contract (a `world_noise` signal and the
  `world_noise_emitter` group) that nothing else has. Their geometry is Godot
  primitives rather than glTF, so they carry `metadata/placeholder = true` with no
  model container to pair with — see `environment/hazards/README.md`.
- `character/clinger/` — `prefab_clinger.tscn`, plus the scripts that exist only to
  serve it. A subdomain rather than a loose entry under `character/`, per rule 3:
  the phase machine, the ears, the grip and the leg poser are one object's parts and
  have no meaning apart from it. Its art mirrors it exactly at
  `assets/art/character/clinger/`, which is what rule 2 asks for. The arithmetic
  underneath is a system rather than a prefab script, and lives in
  `systems/clinger/`.
- `gameplay/` — `prefab_mining_laser.tscn`, the digging laser the placement
  decision below already routed here.
- `ui/hud/` — the three HUD layouts being compared, plus `hud_preview.tscn`, which
  is the harness that swaps between them rather than a prefab itself. Their
  state lives beside them in `ui/hud/` and each widget is its own scene under
  `ui/hud/widgets/`; the three layouts instance those and carry node structure,
  anchors and per-variant exports only. Node names match the Figma layer names, so
  `Minimap`, `Status` and `Reticle` mean the same thing in both places.

Every other directory above is still notional — add one when you have a prefab to
put in it.

The three non-rubble prefabs are bare wrappers too, and for the same reason: the
art is final, the behaviour is not. The car still needs a `StaticBody3D` and an
`AnimationPlayer` for the door slide (the leaves are separate nodes in the glTF
precisely so it can have one), and the switch still needs whatever drives it. They
carry no `metadata/placeholder` line, because the art they wrap is not a stand-in.

## Placeholder prefabs

A prefab wrapping placeholder art says so, on its own root:

```gdscript
[node name="prefab_rubble01" type="Node3D"]
metadata/placeholder = true

[node name="sm_rubble01" parent="." instance=ExtResource("1_106aa")]
```

The container it instances carries the same line. The duplication is deliberate:
integration owns the container and programming owns the prefab, so each marks its
own file. `tools/placeholder-art/audit_placeholders.py` lists every marked scene
and reports any prefab and container that disagree.

The rubble prefabs are bare wrappers today — no collision, no physics body, no
script — which does not yet satisfy `prefab_works_standalone`. They exist so level
design has a stable file and a stable `uid` to place against while the behaviour
is written.

**Wrap the container; do not inherit from it.** The root is a plain `Node3D` with
the container as a child, because Godot cannot change the root node type of an
inherited scene. A rubble chunk that later becomes a `RigidBody3D` would otherwise
have to be deleted and rebuilt — new file, new `uid`, and every level that placed
it rebound by hand. `tools/placeholder-art/make_prefab_scenes.gd` scaffolds them
this way and never overwrites one that has grown past it.

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
→ character/creatures/

Small creature that crawls, leaps and latches
→ character/clinger/

Digging laser the player carries
→ gameplay/

Gas pod, arcing cable, collapsed rock
→ environment/hazards/

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
- `tools/placeholder-art/` — the prefab scaffolder and the placeholder audit.
