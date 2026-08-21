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
