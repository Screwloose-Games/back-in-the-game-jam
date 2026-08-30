# systems/minerals

Scoring for mined ore: what a mineral type is worth, and the running tally of what a
player has collected.

`MineralType` (`Resource`) is the configurable piece — `id`, `display_name`, `value`,
`chunk_material` — so tuning the value of a mineral is an inspector edit on a `.tres`,
never a code change. Three are defined under `types/`: common (1), uncommon (2), rare (4).

`MineralLedger` is the pure core: `add(type)`, `count_for(type)`, `total_score()`. No
`SceneTree`, no signals — the scene-facing shell that owns one and republishes changes as
an event is `PlayerMineralCollector` (`prefabs/character/player/components/`).

Tests: `tests/test_mineral_ledger.gd`.

## Placing ore in a level

`MineralScatter` (`prefabs/environment/minerals/`) is a `@tool` node that dresses cave
walls with `MineralDeposit`s, one pass per biome. It reads the level's `MineLevel`
graph for chambers and bores, samples a point inside one, rays outward, and seats a
deposit where that ray meets the rock -- so a placement is always on real geometry with
a real surface normal, never on an analytic guess.

`MineralZoneRule` (`.tres`) is the per-biome knob: which node it covers, how many
deposits, the chamber/tunnel split, chunks each, a weighted list of `MineralType`, and
tag multipliers so the rooms the design notes call out get more than a plain junction.
The asteroid level's three live in `levels/asteroid_level/mineral_zones/`.

**Deposits the tool made join the `mineral_scatter` group, and it will not touch
anything else.** That is what makes the buttons safe: hand-placed ore is invisible to
all four of them.

| Button | Does |
|---|---|
| Generate | Drops the untouched deposits, then tops each zone back up to its count. |
| Re-snap All | Re-buries every managed deposit's chunks against the rock as it stands. |
| Clear Unedited | Removes only deposits still exactly where they were generated. |
| Clear All | Removes every managed deposit, as one undoable step. |

"Adjusted" means the deposit's transform no longer matches the `_scatter_transform`
metadata written when it was placed, compared exactly -- so nudging one in the viewport
is enough to protect it, and deleting that metadata protects it permanently.

Check the result without opening the editor:

```
godot --headless --path . --script res://tools/level_design/verify_mineral_scatter.gd
```

It reports, per biome, how many sites survive the fit filters and how many sample rays
reach rock, and it fails on the two things that are always bugs: a ray starting inside
rock, or a deposit seated on something that is not the rock. It also re-reads the level
file and checks every placed deposit is seated and spaced.
