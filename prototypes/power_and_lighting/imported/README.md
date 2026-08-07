# Imported

Files copied from other prototypes so this one stays uncoupled. **Nothing here is
this prototype's own material** - everything that is being tested lives one
directory up.

| File | Copied from | Renamed class |
|---|---|---|
| `carrier_suit.gd`, `carrier_suit.tscn` | `object_carrying/carrier_player.gd`, `.tscn` | `CarrierPlayer` -> `CarrierSuit` |
| `movement_knobs.gd` | `object_carrying/carry_knobs.gd` | `CarryKnobs` -> `MovementKnobs` |
| `carry_tether_rope.gd` | `object_carrying/tether_rope.gd` | `TetherRope` -> `CarryTetherRope` |
| `test_chamber_generator.gd` | `object_carrying/chamber_generator.gd` | `ChamberGenerator` -> `TestChamberGenerator` |
| `materials/*.tres` | `object_carrying/materials/` | - |

The suit covers both halves of what was borrowed: `carrier_player.gd` is the
navigation prototype's `zero_g_player.gd` plus the grip and the tether, and
`carry_knobs.gd` says in its own header that its Movement region matches the
navigation prototype's exactly.

## The renames are the only edit

`class_name` is a global registry in GDScript. A verbatim copy of
`carrier_player.gd` refuses to load - "Class 'CarrierPlayer' hides a global script
class" - while the original is still in the project, so each borrowed class has to
be given a distinct name. That rename, the matching filenames, and the `res://`
paths that point at them are the whole diff against the source.

Two things that have to be redone by hand on any re-copy:

- **Do not bring the `.uid` sidecars across.** A duplicated `uid://` makes Godot
  resolve the original file instead of the copy. Let the editor regenerate them.
- **Strip `uid="uid://..."` from `.tscn`/`.tres` headers and `ext_resource`
  lines** for the same reason.

## Do not tune anything here

`movement_knobs.gd` still carries a Draw Distance region and the
`CARRY_OBJECT_LIGHT_*` constants, because it was copied whole. **They are not the
source of truth in this prototype.** `../power_knobs.gd` owns every optical and
power value and pushes it onto the scene after the suit spawns, so anything set
here is overwritten before the first frame. Change the numbers up there.

What `movement_knobs.gd` does still own: movement, the grip, the tether, and the
chamber.

## Not linted

`prototypes/*/imported/` is excluded from `gdlint` and `gdformat` in both
`.pre-commit-config.yaml` and `.github/workflows/gdlint-on-pull-request.yml`,
alongside `addons/`. Borrowed code has to stay refreshable from its source, and
`carrier_suit.gd` is 1096 lines against a 1000-line cap - a limit its original
already fails. Fix a problem in the source prototype and re-copy; do not fix it
here.
