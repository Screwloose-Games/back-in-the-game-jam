# systems/player

The player's maths, with no nodes in it. Everything here is a `RefCounted` of
static functions over plain data, so the flight model, the springs and the oxygen
budget can be exercised headlessly before any scene exists.

The nodes that use these live beside the prefab, in
`prefabs/character/player/components/`. This directory knows nothing about them.

## What is here

| File | `class_name` | What it answers |
|---|---|---|
| `core/player_flight.gd` | `PlayerFlight` | Thrust, tumble, stabilisers, speed caps, and how a manoeuvre is shared with a held load. |
| `core/player_contact.gd` | `PlayerContact` | What a wall does to you: restitution, friction, scrape, and the spin a graze imparts. |
| `core/player_spring.gd` | `PlayerSpring` | Two-body springs for the grip and the tether, plus the rotation maths the wrist spring needs. |
| `core/player_tether_rope.gd` | `PlayerTetherRope` | The rope as a chain of Verlet points whose segments refuse to stretch. |
| `core/player_oxygen_model.gd` | `PlayerOxygenModel` | The oxygen budget: regenerate on a powered tether, drain otherwise, and pay for thrust once you cut loose. |
| `core/player_noise.gd` | `PlayerNoise` | How loud the player is, and how far it carries. |
| `core/player_render_layers.gd` | `PlayerRenderLayers` | Which render layers a suit sits on, and the local camera's cull mask. |

## Springs are a frequency and a damping ratio

Every spring is specified as a natural frequency in hertz and a damping ratio
where 1.0 is critical. The stiffness is derived per link from the two masses
(`PlayerSpring.stiffness`), which is what keeps "a 2.2 Hz wobble, nearly
critically damped" meaningful on its own and means changing either mass does not
force a retune. What the masses do change is *which end moves*, and that is the
whole difference between hauling a load and being moored to one.

## The rope is the one stateful thing

`PlayerTetherRope` keeps its own points between steps, so it is instanced rather
than called statically. Pass a null `space_state` to `step()` to run the
constraint solver with no physics world — that is how `tests/test_player_tether_rope.gd`
exercises it, and it is the reason the collision passes are guarded rather than
assumed.

Its ends are **pinned to the anchors every step and never simulated**. A rope
hauled past its length therefore reports a length longer than it has, and that
excess is the strain `PlayerTether` acts on. The rope does not decide when it
goes taut or when it parts; it only reports its shape.

## Tests

`tests/test_player_flight.gd`, `test_player_contact.gd`, `test_player_spring.gd`,
`test_player_tether_rope.gd`, `test_player_oxygen.gd`, `test_player_noise.gd`,
`test_player_render_layers.gd`.

```
D:\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/run_tests.tscn
```

Name the scene or the main menu boots instead.

## Rules this directory keeps

Per `systems/README.md`: one concern, a pure core, tests in `res://tests/`, and
**no dependency on `prototypes/`**. The numbers these functions operate on come
from `PlayerSettings` (`prefabs/character/player/player_settings.gd`), passed in
as arguments — nothing here reads a settings resource or a knobs file, which is
what lets the same functions serve the player, a test, and eventually anything
else that flies in vacuum.
