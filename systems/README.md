# systems/

Gameplay modules that belong to the game rather than to any one scene.

A directory here is a self-contained system: it knows nothing about which level it is in,
depends on no prototype, and can be dropped into a scene and wired through exports. That is
the line between `systems/` and `prototypes/` — a prototype is an experiment that answers a
question and is allowed to be scruffy; a system is the answer, kept.

| | |
|---|---|
| [`clinger/`](clinger/README.md) | The clinger's pure core: its phases, the guards between them, and the tangent-plane maths a body crawling on walls runs on |
| [`interaction/`](interaction/README.md) | One key, one focused thing, two verbs: what a player can address, and whether the press was a tap or a hold |
| [`hud/`](hud/README.md) | The in-world readouts — power, oxygen, tether, radar, suit status — and the widgets that draw them |
| [`navigation/`](navigation/README.md) | Voxel-derived pathfinding for the alien: bake navigable data out of meshes, and route a body through it |
| [`radar/`](radar/README.md) | The suit's proximity radar: an expanding pulse, and the things it can find |

## What a system owes you

- **One directory, one concern**, with a README that says what it is for and what it is not.
- **A pure core.** Anything that can be written as a function over plain data should be, and
  should live where it can be tested without a `SceneTree`. Nodes are the thin scene-facing
  shell on top, not where the work happens.
- **Tests in `res://tests/`.** That path is fixed by the godot-ai plugin's discovery, so it
  is where suites go; run them with `godot --headless --path . res://tests/run_tests.tscn`
  or with the `test_run` MCP tool while the editor is open.
- **No dependency on `prototypes/`.** Traffic goes the other way: a prototype may use a
  system, never the reverse.
