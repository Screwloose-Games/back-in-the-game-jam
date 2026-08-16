# prefab_player

The player: a six-degrees-of-freedom suit in zero gravity, first person. Drop it
into a level and it flies, grabs, tethers, breathes, lights and mines, with no
per-placement wiring.

```
prefab_player (Node3D)
└── PlayerBody (CharacterBody3D)   layer 2 "player", masks hull|debris|carryable|creature
    │                              motion_mode = FLOATING, group "player"
    ├── Collider
    │   └── HullShape              SphereShape3D r = 0.4
    ├── Rig                        yawed 180°, dropped 1.32 m
    │   └── sk_player_character
    ├── Head                       the eye; everything view-relative hangs here
    │   ├── HeadCamera             fov/near/far from PlayerSettings
    │   ├── AudioListener3D        one per player, so it hears from this head
    │   ├── HelmetLamp
    │   ├── GrabRay                masks layer 4 "carryable"
    │   └── HandSocket             where a held tool or ore seats
    ├── TetherAnchor               harness point, written from settings on ready
    ├── TetherRopeView             top_level; the rope is drawn in world space
    ├── Input                      publishes every control; nothing else reads Input
    ├── Locomotion                 thrust, tumble, stabilisers; owns angular_velocity
    ├── CollisionResponse          owns move_and_slide, then resolves what it hit
    ├── Grab                       two-hand grip springs
    ├── Tether                     rope simulation and taut-only spring
    ├── Hands                      the one hand slot
    ├── PowerClient                draws from the shared box
    ├── Oxygen                     this player's personal air
    ├── Lamp                       beam energy and reach, from charge
    ├── MiningTool                 the laser
    ├── Warmup                     draws the laser and rope once, behind the loading screen
    │   └── ShaderWarmup           holds them visible for a few frames, then puts them back
    ├── NoiseEmitter               what the creature can hear
    ├── View                       lens and fog
    ├── Visibility                 what you see of your own suit
    ├── Respawn                    where Tab returns you to
    └── HudBinding
        ├── HudState               the contract the HUD binds to
        └── prefab_hud_04          instanced from an @export
```

## Drop it in and it works

Nothing here takes a `NodePath` into a level. `PowerClient` finds the shared
power and oxygen box by looking for the `life_support_box` group at `_ready()`,
and re-binds if a box enters the level after the player does — the same trick
`AlienNavAgent` uses to find its navigation baker. That is what satisfies
`prefab_works_standalone`.

Everything else is a sibling lookup by unique name (`%Input`, `%Locomotion`), so
a component contracts on the node names in this scene and nothing outside it.

## The components are ordered, and the order is load-bearing

Physics runs in `process_physics_priority` order, not tree order:

| Priority | Component | Why there |
|---|---|---|
| −100 | `Input` | Publishes before anything reads. |
| −80 | `Locomotion` | Sets this frame's heading, which the links aim their springs at. |
| −40 | `Grab` | Grip springs push both bodies. |
| −30 | `Tether` | Independent of the grip; both push the same two bodies. |
| 100 | `CollisionResponse` | Moves the body last, after every link has had its say. |

`CollisionResponse` owns the `move_and_slide` call. That looks odd until you need
the bounce: restitution has to be computed from the velocity *before* the move,
and `move_and_slide` is the one thing that destroys it.

## Everything tunable is in one resource

`player_settings.tres` (`player_settings.gd`), grouped by capability. It replaced
five near-duplicate `*_knobs.gd` files in `prototypes/`, which had already drifted
apart. Three constants disagreed and the `object_carrying` values won, because
that was the newest prototype and the only one tuned with a load in hand:

| | elsewhere | object_carrying | shipped |
|---|---|---|---|
| `thrust_acceleration` | 8.0 | 10 | **10.0** |
| `max_speed` | 2.0 | 4.0 | **4.0** |
| `angular_drag` | 1.0 | 2.0 | **2.0** |

Worth confirming on the first playtest. It is a feel decision, not a correctness
one.

`invariant_failures()` catches the cross-field rules a slider can break —
`camera_far` behind the fog, a lamp reaching past the clip plane, a rope drawn
fatter than it behaves. `PlayerView` reports them on load.

The maths lives in `systems/player/core/` and takes these values as plain
arguments, so it is unit-tested without a scene. See that directory's README.

## Seeing yourself, and seeing the other player

Multiplayer is networked, so each machine draws exactly one camera. That makes
self-visibility a local question rather than a per-peer one: `PlayerVisibility`
puts the local player's own meshes on the `own_body` render layer and gives the
local camera a cull mask that drops it. A remote peer's prefab has
`is_local_player = false`, leaves its meshes on `world`, and is drawn in full.
No layer coordination between machines, and no player index to collide.

```
                       local camera cull mask
world         (1)      drawn   ← the asteroid, an ally's torso, everything else
own_body      (11)     culled  ← your own head and visor
own_viewmodel (12)     drawn   ← your arms; switched off on a remote instance
own_tool      (13)     drawn   ← the laser in your own hands
peer_suit     (14)     drawn   ← an ally's head, visor and laser
```

`own_tool` and `peer_suit` are lighting layers rather than visibility ones: the
meshes are drawn like anything else, but a helmet lamp drops the suit it is
mounted on from its `shadow_caster_mask`. A lamp sits *inside* the visor and a
hand's width from the laser, so with the full mask its own suit throws a shadow
across everything the beam is pointed at — the laser's shadow over the cut, and,
for an ally, the visor blacking the beam out entirely so you see no light coming
off their helmet at all. Each lamp drops only its own suit, so an ally you light
still casts a shadow and so do you in theirs.

Two lamp masks are needed rather than one because a lamp cannot ask for "the mesh
I am parented to" — only for a layer. `PlayerVisibility` puts your own head and
visor on `own_body` and an ally's on `peer_suit`; `PlayerLamp` picks the matching
mask from `is_local_player`. With more than two players in a session, one ally's
lamp would also skip another ally's visor shadow; the level spawns two.

Use `shadow_caster_mask` and not `light_cull_mask` for this: `light_cull_mask`
stops the object being *lit* while it goes on blocking the light, which is the
opposite of what is wanted.

Three modes, on `PlayerVisibility.self_view`:

| | |
|---|---|
| `HIDE_WHOLE_MODEL` | None of your own suit is drawn, the held tool included. |
| `HIDE_LISTED_PARTS` | Default. Only the meshes named in `parts_hidden_from_self`. |
| `SHOW_EVERYTHING` | Draw it all, as a remote peer sees you. |

`set_first_person(false)` shows the whole suit whatever `self_view` says, for a
third-person or spectator camera. `parts_only_visible_to_self` is the other
direction — first-person arms or a tool's near model, drawn for you alone.

Culling works per `MeshInstance3D`, and the model has three:
`player_character_body`, `player_character_head` and `player_character_helmet`.
The camera sits inside the last two — `Rig` is dropped 1.32 m so the eye lands at
the helmet's centre — so both are in `parts_hidden_from_self` and the body is not.
The lists are matched by node name, not by path, so a re-import does not break
them; `tests/test_player_visibility.gd` is what catches a name drifting apart from
the glTF, because a mesh that matches nothing simply stays drawn.

**The head is a separate mesh so that it can be culled on its own, and that
leaves the body open at the collar.** Nothing of the suit is in frame at the
shipped `camera_fov` of 67° — the nearest rim vertex sits 36.12° below the view
axis at the worst frame of `idle_float`, measured across every frame of every
clip — but a wider lens sees through the neck into the world.
`PlayerSettings.CAMERA_FOV_NECK_SEAM_LIMIT` is that ceiling, and
`invariant_failures()` reports crossing it.

Layers are written in code, not saved on the meshes, because the meshes live
inside an instanced glTF scene: overriding their properties in the `.tscn` needs
editable children and those overrides do not survive a re-import.

`HelmetLamp` is a shadow-casting `SpotLight3D` parented inside the head and visor,
which is exactly the case the two lamp masks above exist for. Culling a mesh from
the camera does *not* reliably stop it casting, so neither lamp may be left on the
default mask: an ally's lamp on the full mask is swallowed by their own visor and
throws no light into the level at all.

## Collision layers

`PlayerBody` is on layer 2 (`player`) and masks 29 — hull, debris, carryable and
creature. It **does** collide with the creature, unlike `prefab_alien`, which
masks only the hull; if that turns out to shove players around unhelpfully, the
mask is the knob.

`GrabRay` masks layer 4 (`carryable`) alone, so anything it reports is fair game
and needs no filtering by type.

## Three deliberate deviations

- **No limb colliders.** The GDD asks for a collider "with limbs to make complex
  collisions more likely, spinning the player". The suit is one 0.4 m sphere,
  because every number in the Collision group was tuned against that sphere and
  adding shapes is a retune, not an addition. The `Collider` node exists so they
  drop in without restructuring anything else. Impact spin already works — a
  glancing hit tumbles you today; limbs would only make glancing hits commoner.

- **The rig is yawed 180°.** `sk_player_character.gltf.spec.yaml` records the art
  as facing `+Z` against this project's `-Z`, knowingly and inherited. The fix
  belongs on the `Rig` node, not in the mesh — reversing the art would silently
  turn the character around in every scene that already places it.

- **The root wraps a body rather than a model container.** Same reading as
  `prefab_alien`: `prefabs/README.md`'s wrap-don't-inherit rule is about static
  props, and a character needs a physics body.

## The mining beam

`MiningTool` casts along the aim; `prefab_mining_laser.tscn`
(`MiningLaserBeam`) draws what that cast found — an unshaded cylinder from the
model's `muzzle_point` to the hit, and an `OmniLight3D` sitting on the hit. The
beam is drawn from the muzzle but aimed by the head, because a second cast from
the muzzle would stop short of whatever you are actually pointing at. Colour,
brightness, reach and thickness are the `mining_*` fields in the Mining group.
The light casts no shadows, and the mesh casts none either — the lamp is a hand's
width from the visor and would throw the beam's own shadow over the cut.

`MiningTool`'s node header carries `node_paths=PackedStringArray("tool_model")`.
Without it Godot leaves a `Node`-typed `@export` null however good the
`NodePath` beside it looks, silently — which is what kept `tool_model` null, and
`_apply_tool_visibility` a no-op, before the beam needed it. Any hand-edited
`.tscn` that assigns a `Node`-typed export needs the same declaration.

## Not here yet

- **The shared power and oxygen box.** `PowerClient` is the client half. The box
  is its own prefab, and it needs to join the `life_support_box` group.
- **Ore, and what mining does to it.** `MiningTool` emits `mining(target, at,
  damage)` and calls `take_mining_damage` on anything that has it. Nothing does,
  so the beam draws and drains power today without breaking anything down.
- **The network seam.** `_spawn_peer` in `levels/asteroid_level/asteroid_level.gd`
  is the one place a peer differs from you — `is_local_player`, `Input.enabled`,
  `HeadCamera.current` — and it is driven by a local flag today, not by
  multiplayer authority. `common/network/` has the WebRTC transport, unwired.
