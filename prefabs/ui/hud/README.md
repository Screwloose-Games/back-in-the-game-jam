# prefabs/ui/hud/

The in-world readouts: power, oxygen, tether, minimap and suit status, plus the
widgets that draw them.

Three HUD layouts are being compared (`prefabs/ui/hud/prefab_hud_02..04.tscn`).
They exist to be A/B'd, not to all ship. Everything in here is shared by all three;
the scenes carry only node structure, anchors, and which Figma texture each widget
holds.

`HUDInterface_01` was dropped — the designer renamed it "Don't Use - Test Variant".

## Names come from Figma

Every component is named for the layer it came out of, so a conversation about
`MINIMAP` or `POWER_LINES` means the same thing in both places:

| Figma | Node in a layout | Widget scene | Script |
|---|---|---|---|
| `BORDER` | `Border` | — | `hud_border.gd` |
| `POWER_BG` + `POWER_LINES` | `Power` | `widgets/power_indicator.tscn` | `hud_power.gd` |
| `OXYGEN` | `Oxygen` | `widgets/oxygen_ring.tscn` / `widgets/oxygen_bar.tscn` | `hud_oxygen_ring.gd` / `hud_oxygen_bar.gd` |
| `TETHERED_METER` | `TetheredMeter` | `widgets/tethered_indicator.tscn` | `hud_tethered_meter.gd` |
| `MINIMAP` | `Minimap` | `widgets/minimap.tscn` | `hud_minimap.gd` |
| `STATUS` | `Status` | `widgets/status_face.tscn` | `hud_status.gd` |
| `RETICLE` | `Reticle` | — | `hud_reticle.gd` |
| `Screw_01` | drawn by `Border` | — | — |

## One widget, one scene

Each widget that reports something is its own scene under `widgets/`, and the three
layouts instance it rather than re-attaching the script. Open one on its own and it
draws — every widget script is `@tool`, so what you see in the editor is what the
game draws. The layouts then override only what differs between them: where the
widget sits, and which Figma texture or wording it carries.

`Border` and `Reticle` are the exceptions and stay script-attached. They are pure
chrome, they bind to no state, and neither has anything to preview that the layout
it lives in does not already show.

Oxygen is two scenes rather than one because it is two drawings: HUD 02's
horizontal bar and HUD 03/04's ring. They share the `show_fraction` contract, so a
layout swaps one for the other by swapping which scene it instances.

`hud_oxygen_bar.gd` is the worked example of what a widget script should look like,
and the conventions it sets are worth copying:

- **The reported value is an `@export_range`, not a private var.** That is what makes
  `@tool` mean anything — you drag `fraction` and the editor draws that level. To stop
  a preview leaking into the `.tscn` and from there into every layout that instances
  it, `_validate_property()` clears `PROPERTY_USAGE_STORAGE` on it: inspector row and
  live slider, but Godot never writes the value. The runtime value stays the only one
  that ships.
- **Textures are `@export`s defaulting to `HudArt.*`**, as `hud_power.gd` already did,
  and `design_extent()` derives from the art rather than restating its size. A Figma
  re-export that changes the PNG cannot leave a constant stale behind it.
- **Setters guard the no-op** (`if is_equal_approx(next, fraction): return`) before
  assigning, so a repeated value costs no redraw. Writing to the property inside its
  own setter is direct member access, not recursion.
- **`bind()` is idempotent and seeds.** A second `connect()` to the same `Callable` is
  an error rather than a no-op, and seeding means binding alone is enough.
- **`_get_configuration_warnings()` catches the silent failures** — above all a
  missing lines texture, which still draws a frame and so looks exactly like a working
  HUD reading full.

**The bar no longer pulses at low oxygen and the ring still does.** The alarm was cut
from `hud_oxygen_bar.gd`; `hud_oxygen_ring.gd` keeps `ALARM_FRACTION`/`_RATE`/`_DEPTH`
and its `_process`. So HUD 02 and HUD 03/04 currently differ in more than layout, which
undercuts the A/B comparison the three variants exist for. Deciding it either way —
dropping the ring's pulse too, or giving the bar something back — is an open decision,
not an oversight. Low supply is still reported in every variant through
`HudState.status_for()` and the status face.

## What it is not

- **Not a menu system.** Pause, options and title screens live in `common/ui/`.
- **Not the source of the numbers.** `HudState` is a mailbox. Deciding what counts
  as a contact, how fast oxygen drains, or when the suit is in trouble belongs to
  whatever fills it in. `HudDemoDriver` fills it with invented values so the
  layouts can be judged before those systems exist; it is scaffolding.
- **Not on the GlobalSignalBus, and should not move there.** That bus carries level
  and menu lifecycle — one event per scene change. This is per-frame gameplay
  telemetry with a different lifetime, and a HUD signal on the global bus would
  outlive the thing it reports on.

## The art

Exported from Figma, one PNG per named component, filed under the component it
belongs to:

```
assets/art/ui/hud/
├── border/    ui_hud_screw
├── minimap/   ui_hud_minimap_background, _lines01..04, _reflection, ui_hud_enemy_dot
├── oxygen/    ui_hud_oxygen_ring, _border, _lines
├── power/     ui_hud_power_bg_02/03/04, ui_hud_power_lines, _lines_03
├── reticle/   ui_hud_reticle_02/03/04
└── status/    ui_hud_status_green, _yellow, _red
```

The filenames repeat the group, matching how `assets/art/` already does it for 3D
(`elevator_car/t_elevator_car_basecolor.png`) — a file that names itself is still
findable once it has been dragged somewhere else.

`hud_art.gd` is the only file that names them, and it also holds where each one
sits, as a **centre** in design coordinates — Figma grows an export's bounding box
to cover strokes and glow, symmetrically, so a node stated at 333.75x270.85 arrives
as a 339x276 PNG. Anchoring by centre absorbs that; anchoring by corner would put
every asset out by half its bleed.

Two things are still drawn rather than blitted, and both for a reason:

- **`BORDER`**, because Figma states it at 1836x1024 and the repo's art gate blocks
  any PNG over 1024 in either dimension. Which is the right answer anyway: the
  border is the one element that must meet all four screen edges, and
  `stretch/aspect="expand"` hands the game a canvas wider than 1280x720 on anything
  that is not 16:9.
- **`TETHERED_METER`**, because its content changes every metre.

### Re-exporting

The Figma MCP's `download_assets` composites every **PNG** it returns onto a
`#1E1E1E` preview backdrop — the alpha comes back uniformly opaque and the art is
unusable as an overlay. Its **SVG** export has no matte. So:

```
# 1. download_assets(nodeId, defaultFormat: "svg") for each component
# 2. rasterise, preserving alpha, into that component's directory:
godot --headless --path . --script res://tools/figma-export/svg_to_png.gd \
    -- <svg_dir> assets/art/ui/hud/<group>
```

The converter writes `<name>.png` for every `<name>.svg` it finds, so name the SVGs
as they should land and point it at one group at a time.

`tools/figma-export/svg_to_png.gd` strips the preview backdrop and renders through
the same ThorVG that Godot's own SVG importer uses.

One thing to keep true in the Figma file: **the `HUDInterface_*` frames must have no
background fill.** A frame fill is exported *into* every child asset, which is how
22 assets first came back matted onto white.

## How a widget binds

Widgets connect themselves; nothing above them knows their method names. This is
the connect-then-seed order `prototypes/power_and_lighting/power_hud.gd` uses on
the suit bar, moved down a level:

```gdscript
func bind(state: HudState) -> void:
    state.power_changed.connect(show_fraction)
```

`HudVariant.bind()` walks its `HudWidget` descendants, calls `bind()` on each, then
calls `state.announce_all()`. That last call is why swapping a variant mid-run
shows the truth immediately rather than a HUD full of defaults — which looks
exactly like a HUD that works.

A variant with no status face simply has no `Status` node. Nothing branches on
which variant it is.

## Four things that will bite

**Nothing here runs `_process` except the oxygen ring's alarm and the demo driver.**
Widgets redraw when the value they report changes, per the rule `power_bar.gd` sets
out. Note that *defining* `_process` is what registers a node for processing — a
`_process` that early-returns on its first line is still a per-frame script call, so
gate it with `set_process()` instead, or do not define it.

**`_get_minimum_size()` is wrong for these widgets, however standard it looks.**
`Control.set_size()` clamps to `get_combined_minimum_size()` whether or not the parent
is a container, and `Chrome` is a plain `Control`. The layouts deliberately place
widgets *smaller* than their design size — `prefab_hud_02.tscn` gives the 711x71 oxygen
bar a 474x47 rect — because `scale_factor()` exists precisely so a design-space widget
draws at any size. Returning `design_extent()` as a minimum would force the node back
to 711x71, fight the offsets in the scene, and rewrite the layout on the next save.
**For this family the design extent is a coordinate system, not a floor.** The same
goes for `custom_minimum_size`.

**`const X := PackedFloat32Array([...])` is not a constant expression.** It parses,
it lints, and it fails at load with `Assigned value for constant ... isn't a
constant expression` — sometimes only in the scene that touches it. Write
`const X: PackedFloat32Array = [...]` instead.

**PixelPurl has a 16px em**, so it is only crisp at multiples of 16. The mockup's
40px and 60px convert to 26.7 and 40 canvas units, neither of which qualifies;
`HudMetrics.font_size` snaps to 32 and 48. That runs 20% larger than the design, so
the `TetheredMeter` boxes are wider than Figma's stated 255px — otherwise
"TETHERED 33m" clips to "TETHERED".

## Running it

```
godot --headless --path . --import                       # new class_names need this first
godot --headless --path . res://tests/run_tests.tscn
godot --path . res://prefabs/ui/hud/hud_preview.tscn     # name the scene, or the main menu boots
```

In the preview: `2`-`4` swap variant, `B` cycles the backdrop between dark, lit
rock and worst-case bright, `A` hands the meters back to the demo driver after you
have moved a slider, `H` hides the panel.
