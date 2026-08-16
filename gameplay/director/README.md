# Encounter Director

The system that decides what should happen for this to remain a good horror encounter —
and the only one permitted to know the truth, precisely because it is the only one
forbidden from acting on it.

> What should happen for this to remain a good horror encounter?

Spec: [`documentation/design/alien/director.md`](../../documentation/design/alien/director.md).

## What is here, and what is not

**Only the two value types.** `EncounterDirective` goes down to Behavior; `EncounterReport`
comes back up. That is the entire coupling, and `director.md` is explicit that it is "a pure
function of two structs, so it tests without a scene, a body, or a baked graph".

**`EncounterDirector` is not built.** No menace, no lull, no phase derivation, no target
arbitration, no kill grace, no `EncounterTrack`, no `DirectorConfig`. Those are a second
module the size of Behavior's, and nothing in the game paces an encounter yet.

The types ship ahead of their producer on purpose. Every `fsm.md` transition guard reads a
directive field — `permit_hunt`, `escalation_bias`, `force_disengage` — so writing the HFSM
without them would mean writing every guard twice. With `EncounterDirective.neutral()` the
creature runs correctly and unpaced, and the day the Director lands nothing in Behavior
changes.

```
        EncounterDirector          (not built)
              │        ▲
    directive │        │ report
              ▼        │
         CreatureBehavior
              │
        HFSM + trees
```

## `neutral()`, and the one field worth arguing about

```gdscript
var directive := EncounterDirective.neutral()
```

`QUIET`, zero menace and lull, no target, zero biases — and **`permit_hunt = true`** with
**`lethality = LETHAL`**.

Both defaults are deliberate. A neutral directive must not be a silent difficulty setting:
an alien that cannot hunt because nobody wired a Director reads as a broken HFSM rather than
as a design decision, and it would be found by someone debugging the wrong file. Likewise
first-encounter grace is a *pacing* judgement that needs session history to make — a
creature with no Director has none, so it does not get to be merciful by accident.

## Reading the report

Two fields carry traps that only show up downstream.

**`route_distance` is `INF`, not `0.0`, when there is no route.**
`RouteFollower.distance_remaining` returns `0.0` for no route, and the menace proximity term
is `w_proximity × (1 − clamp(route_distance / menace_range))`. Passing the raw value through
would report maximum proximity pressure from an alien idling at a nest, forever, with
nothing in the log. `EncounterReport.NO_ROUTE_DISTANCE` is the sentinel.

**`target_reachable` defaults to `true`.** `CreatureNavigation.route` is null before the
first replan and after every `clear_goal()`, and "the creature has not been given anywhere
to go" is not the same claim as "the creature cannot reach you". A false here fires the
Director's `−w_stall` term against an alien that is behaving perfectly.

**`attack_window_open` and `lurking_at_crevice` are hardcoded `false`** until the `HUNTING`
tree exists, which silently zeroes `w_attack` and `w_lurk`. That is a stub, not tuning.

## Names this module reserves project-wide

`EncounterDirective`, `EncounterReport`. Godot's `class_name` table is flat and
project-wide, so a second declaration is a hard parse error at project scan that takes the
whole project down — the same hazard `suspicion.md` documents for `SuspicionEvidence`.
`CrawlerCameraDirector` in `prototypes/tentacle_crawler/` is unrelated and does not collide.

`EncounterReport.state` is typed `CreatureState.State`, from
`gameplay/creature/behavior/creature_state.gd`. `director.md`'s snippet writes
`state: CreatureState`, naming the class rather than the enum; the enum is what is meant.

## Running the suite

```sh
GODOT=/path/to/Godot   # 4.7.x

$GODOT --headless --path . --import
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json \
  -gdir=res://gameplay/director/tests -gexit
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable script
prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml` greps the
output for that reason.
