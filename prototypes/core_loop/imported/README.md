# Imported

Files copied from other prototypes so this one stays uncoupled. **Nothing here is
this prototype's own material** - everything that is being tested lives one
directory up.

| File | Copied from | Renamed class |
|---|---|---|
| `core_loop_suit.gd`, `.tscn` | `object_carrying/carrier_player.gd`, `.tscn` | `CarrierPlayer` -> `CoreLoopSuit` |
| `core_loop_drill_beam.gd` | `drill_and_mining/drill_beam.gd` | `DrillBeam` -> `CoreLoopDrillBeam` |
| `core_loop_power_system.gd` | `power_and_lighting/power_system.gd` | `PowerSystem` -> `CoreLoopPowerSystem` |

**Three files, and that is the whole of it.** Everything else this prototype
borrows is referenced where it lives: `OreNode`, `VoxelField`,
`SurfaceNetMesher`, `OreDebrisPool`, `PowerStore`, `LampPowerResponse`,
`CubePowerGauge`, `PowerBar`, `TetherRope`, `TetherRopeMesh`, `CarryKnobs`,
`WallNavmeshBaker`, `ChaseTarget`, `ChaseTargetFollower`, `CreatureContact`, and
`crawler.tscn`. Copying those too would have been about five thousand lines of
rename before a line of new code got written, and this prototype is the place the
others are supposed to meet - coupling to them is the point of it existing.

A file is copied here only when it had to CHANGE. That is the rule; if something
below stops being true, the file should go back to being a reference.

## Why each one had to change

**`core_loop_suit.gd`** wanted three things no single donor had. It needed grip
and tether (`object_carrying` has them, `navigation` does not), sprint
(`navigation` has it, `object_carrying` dropped it) and somewhere to hang a drill
and a crystal collector. It also drops the `CarrySettings` resource, because
retyping it would put six grip-and-tether sliders on a panel with twelve rows of
room and a monster to tune.

**`core_loop_drill_beam.gd`** gained a power draw. `drill_and_mining`'s README
says outright that the drill costs nothing to run, and what it should cost is most
of why this prototype exists.

**`core_loop_power_system.gd`** is the smallest and dullest of the three:
`bind()` is statically typed to that prototype's `CarrierSuit`, and nothing else
about it needed touching.

## `power_and_lighting/imported/carrier_suit.gd` does not load

Worth knowing, because it is the obvious donor for the suit and it is broken.

It references `CarryTetherRopeMesh`, which exists nowhere in the repository -
`tether_rope.gd` was copied into that directory as `carry_tether_rope.gd` and
`tether_rope_mesh.gd` was not. The file fails to parse, and
`power_and_lighting_prototype.gd` preloads its scene, so that prototype does not
run at all on this branch. It is not caused by anything here and nothing here
fixes it.

This is why the suit above came from `object_carrying/carrier_player.gd`, the
working original, rather than from the copy that already had a few of the edits.

## Rules that have to be redone by hand on any re-copy

- **Do not bring the `.uid` sidecars across.** A duplicated `uid://` makes Godot
  resolve the original file instead of the copy.
- **Strip `uid="uid://..."` from `.tscn`/`.tres` headers and `ext_resource`
  lines** for the same reason.
- `class_name` is a global registry, so a verbatim copy refuses to load - "Class
  'X' hides a global script class" - while the original is still in the project.
  `CarrierSuit`, `MovementKnobs`, `TestChamberGenerator`, `DrillSuit`,
  `DrillMovementKnobs` and `DrillChamberGenerator` are already taken.

## This directory IS linted

`gdformat` and `gdlint` run on these files like any others - `.pre-commit-config.yaml`
and the CI workflow exclude `addons/` and nothing else.

**`core_loop_suit.gd` sits nine lines under the 1000-line cap.** It arrived at
998 only after its design docstring was cut down to a pointer at
`carrier_player.gd`, which is where the grip and the tether are explained
properly. Anything added to it has to come out of something else.
