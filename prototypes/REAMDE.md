# Prototypes

This directory contains prototypes for various components and features of the project. Each prototype is designed to demonstrate specific functionality or to serve as a proof of concept for new ideas.

These are not expected to have production code, reusable components, or be fully functional.

## Knobs, and keeping what you tuned

Each prototype keeps its tunable numbers in one `*_knobs.gd` — `class_name XKnobs
extends RefCounted`, nothing but documented `const`s. **That file is still where a
default lives.** Edit it and re-run to change the starting point for everybody.

The handful of numbers worth arguing about *while playing* also have a slider, in
the panel at the bottom left of the screen. Press **ESC** to free the mouse and
reach it.

- **SAVE** writes the values you stopped on to that prototype's settings `.tres`,
  which is committed — so they survive the next run and show up in the diff as
  numbers a person can read.
- **RESET** puts every slider back to the knobs const.

```
prototypes/
  prototype_settings.tres              every prototype's settings, in one place
  shared/
    prototype_settings.gd              base Resource: reset, save, invariants
    prototype_settings_index.gd        the index above
    prototype_tuning_panel.gd          the panel, built by introspection
  navigation/navigation_settings.gd + .tres
  object_carrying/carry_settings.gd + .tres
  tunnel_system/tunnel_settings.gd + .tres
  tentacle_crawler_chaser/chase_settings.gd + .tres
```

**To give another knob a slider**, add one line to that prototype's
`*_settings.gd`:

```gdscript
@export_range(TunnelKnobs.VIEW_DISTANCE_MIN, TunnelKnobs.VIEW_DISTANCE_MAX, 1.0, "suffix:m")
var view_distance: float = TunnelKnobs.FOG_DEPTH_END
```

The panel builds itself from whatever it finds, so there is no panel code to
write. The `@export_range` is also the opt-in: a number without one is skipped,
with a warning naming it. Then apply it wherever the const was being read, and
add it to the prototype's `_apply_settings()` if it lives on a node.

Notes:

- **`res://` is only writable from the editor.** SAVE says so in the panel rather
  than failing quietly. Prototypes are editor-only, so this is a guard rail.
- **Do not leave a settings `.tres` selected in the inspector while playtesting.**
  The editor holds its own copy and can write stale values back over what you
  saved. If you did, use *Project → Reload Current Project*.
- **Deleting a `.tres` is safe.** The prototype falls back to the knobs consts
  with a warning. `prototypes/tools/bootstrap_prototype_settings.gd` recreates any
  that are missing and never touches one that exists.

```
godot --headless --path <root> \
  --script res://prototypes/tools/bootstrap_prototype_settings.gd   # create missing
godot --headless --path <root> \
  res://prototypes/tools/verify_prototype_settings.tscn             # check them
```

`prototypes/tentacle_crawler/` is deliberately outside all of this — its own
`CLAUDE.md` requires it to stay self-contained and not depend on the host project.
