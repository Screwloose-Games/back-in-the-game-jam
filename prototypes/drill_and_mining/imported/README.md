# Imported

Files copied from other prototypes so this one stays uncoupled. **Nothing here is
this prototype's own material** - everything that is being tested lives one
directory up.

| File | Copied from | Renamed class |
|---|---|---|
| `drill_suit.gd`, `drill_suit.tscn` | `navigation/zero_g_player.gd`, `.tscn` | `ZeroGPlayer` -> `DrillSuit` |
| `drill_movement_knobs.gd` | `navigation/prototype_knobs.gd` | `PrototypeKnobs` -> `DrillMovementKnobs` |
| `drill_chamber_generator.gd` | `object_carrying/chamber_generator.gd` | `ChamberGenerator` -> `DrillChamberGenerator` |

The navigation prototype's player was taken rather than the object carrying
prototype's, which is that same file plus a grip and a tether. Neither is wanted
here, and taking them would have dragged `TetherRope`, `TetherRopeMesh` and
`CarryKnobs` across as well - four more renames for two features this stage
deliberately does not have.

What did come with it, and is worth knowing about: `_shove_debris`, the two-body
momentum exchange the suit already does against any `RigidBody3D` it hits. That
is what happens when a chunk of rock you just cut loose comes back and hits you,
and none of it had to be written.

## Why the renames are necessary

`class_name` is a global registry in GDScript. A verbatim copy refuses to load -
"Class 'X' hides a global script class" - while the original is still in the
project, so each borrowed class has to be given a distinct name.

**`MovementKnobs`, `CarrierSuit` and `TestChamberGenerator` were already taken**
by `power_and_lighting/imported/`, which borrowed the same lineage first. That is
why the names here are prefixed rather than reusing the obvious ones.

Two things that have to be redone by hand on any re-copy:

- **Do not bring the `.uid` sidecars across.** A duplicated `uid://` makes Godot
  resolve the original file instead of the copy. Let the editor regenerate them.
- **Strip `uid="uid://..."` from `.tscn`/`.tres` headers and `ext_resource`
  lines** for the same reason.

## The three edits beyond the renames

Unlike the power prototype's copy, this one is not verbatim. Each departure is
here because leaving it would have cost more than the divergence does:

1. **`drill_suit.gd` has no settings resource.** The original reads seven flight
   values off a `NavigationSettings`. Retyping that to `DrillSettings` would put
   seven flight-feel sliders on a panel that is supposed to be about drilling,
   and flight feel is a question the navigation prototype already answered - so
   `var settings`, `bind_settings()` and `_apply_settings()` are gone and every
   `settings.foo` reads `DrillMovementKnobs.FOO`. `power_and_lighting`'s
   `carrier_suit.gd` did exactly this and for the same reason.
2. **`drill_suit.gd` gained three small methods** - `set_camera_far()`,
   `set_lamp_range()` and `get_head_camera()`. The first two are the two values
   that belong to the scene rather than to the suit, pushed in by the prototype
   root; the third is where the beam attaches.
3. **`drill_chamber_generator.gd` lost the carryable.** `_spawn_carry_object()`,
   `reset_carry_object()` and the module lamp are all gone - nothing is carried
   in this prototype - and its dimensions now come from `../drill_knobs.gd`
   rather than from `CarryKnobs`, because that file was not copied.

## This directory IS linted

**Unlike what `power_and_lighting/imported/README.md` says.** That claim is not
true of the current configuration: `.pre-commit-config.yaml` and
`.github/workflows/gdlint-on-pull-request.yml` both exclude `addons/` and nothing
else. It was presumably written for a `carrier_suit.gd` that is 1096 lines
against a 1000-line cap.

Nothing here is close to that limit, and both originals already pass, so it costs
nothing - but run `gdformat` and `gdlint` on these files like any others.
