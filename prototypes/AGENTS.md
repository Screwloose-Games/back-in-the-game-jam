# Prototypes

## Every new prototype gets a settings resource and a tuning panel

Tunable numbers go in a `<name>_knobs.gd` (`class_name XKnobs extends RefCounted`,
documented `const`s only). **That file stays the only place a default is written
down.** On top of it, the numbers worth arguing about *while playing* get a
slider, a **RESET** and a **SAVE**, so a value found in a playtest survives the
run instead of being transcribed by hand or lost.

Do not hand-build a tuning panel. `PrototypeTuningPanel` builds itself from
whatever the settings resource exports.

### Wiring one up

1. **`<name>_settings.gd`** — `extends PrototypeSettings`, a `const SAVE_PATH`,
   and `settings_path()` returning it. One `@export_range` per live-tunable knob,
   defaulted from the const and bounded by the knobs' own `*_MIN`/`*_MAX` where
   they exist (cross-class consts are legal in the annotation — verified):

   ```gdscript
   @export_range(TunnelKnobs.VIEW_DISTANCE_MIN, TunnelKnobs.VIEW_DISTANCE_MAX, 1.0, "suffix:m")
   var view_distance: float = TunnelKnobs.FOG_DEPTH_END
   ```

   `@export_range` is the opt-in: a number without one is skipped and warned
   about, which is how a value lives in the resource without becoming a slider.
   Type floats explicitly (`: float`) — a knob written without a decimal point
   would infer `int` and make the slider step in whole units.

2. **Panel node** — a `PanelContainer` named `Tuning` under the HUD, script
   `res://prototypes/shared/prototype_tuning_panel.gd`. Copy the anchor block
   from any existing prototype's `.tscn`.

3. **Prototype root** — `@export var settings: XSettings`, assigned in the
   `.tscn`, plus:

   ```gdscript
   if settings == null:                      # fresh clone, or someone deleted it
       settings = XSettings.new()            # a bare instance IS the knobs consts
       push_warning("No <name>_settings.tres wired; running on <name>_knobs.gd defaults.")
   settings.changed.connect(_apply_settings)
   _apply_settings()                         # same call the signal makes
   ```

   `_apply_settings()` pushes every tunable onto the scene and **must not write
   back to `settings`**, or it re-enters `changed`. Values read at the point of
   use each frame need no push at all.

4. **Register it** in four places, or it is invisible to the tooling:
   `SETTINGS_SCRIPTS` in `tools/bootstrap_prototype_settings.gd` and in
   `tools/verify_prototype_settings.gd`, `INDEX_PROPERTIES` in the former, and an
   `@export` on `shared/prototype_settings_index.gd`.

5. **Generate and check** — a new `class_name` does not resolve until the project
   is reimported:

   ```
   godot --headless --path <root> --import
   godot --headless --path <root> --script res://prototypes/tools/bootstrap_prototype_settings.gd
   godot --headless --path <root> res://prototypes/tools/verify_prototype_settings.tscn
   ```

   The bootstrap creates only missing `.tres` and never overwrites a tuned one.
   Commit the `.tres`, the `.gd`, and the `.gd.uid` sidecar together.

### Rules that are not style preferences

- **Every control is `FOCUS_NONE`**, handled by the base class. A focused Button
  eats `ui_accept` (space = thrust up) and a focused HSlider eats `ui_left`/
  `ui_right` (A/D). It reads as broken flight controls, not as a UI bug. This is
  also why there is no SpinBox for an unranged number — its LineEdit would
  swallow every key.
- **Cross-knob rules belong in `invariant_failures()`**, overridden on the
  settings resource, not as a startup warning against the consts — a slider can
  break them at runtime. Call `super.invariant_failures()` and append.
- **Never `reset()` by caching defaults.** The base makes a fresh instance of the
  script, so the const is the default and nothing can drift.
- **A multiplier knob scales the tuned value, not the const.** Otherwise the
  slider silently stops applying whenever the multiplier is engaged.

`prototypes/tentacle_crawler/` is exempt from all of this — its own `CLAUDE.md`
requires it to stay self-contained and not depend on the host project.

See `README.md` for the playtester-facing version.
