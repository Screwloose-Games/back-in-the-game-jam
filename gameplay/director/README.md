# Encounter Director

The system that decides what should happen for this to remain a good horror encounter —
and the only one permitted to know the truth, precisely because it is the only one
forbidden from acting on it.

> What should happen for this to remain a good horror encounter?

Spec: [`documentation/design/alien/director.md`](../../documentation/design/alien/director.md).

## The shape of it

```
        EncounterDirector          level-scoped, one per level
              │        ▲
    directive │        │ report          one struct down, one struct up, once per tick
              ▼        │
         CreatureBehavior
              │
        HFSM + trees
```

| File | What it is |
|---|---|
| `encounter_directive.gd` | What the Director asks of one creature, for one tick |
| `encounter_report.gd` | What Behavior tells it back |
| `director_config.gd` | Every tunable. The whole pacing dial |
| `encounter_track.gd` | One creature's menace, phase, target and timers |
| `encounter_pacing.gd` | Every judgement call, as pure statics over three values |
| `director_party.gd` | **The only file allowed to know where anybody actually is** |
| `encounter_director.gd` | The producer: integrate, derive, arbitrate, publish |

`EncounterPacing` is all static and touches no node, no clock and no signal, so
director.md's claim that the coupling is *"a pure function of two structs, so it tests
without a scene, a body, or a baked graph"* is literally true rather than aspirational.
`EncounterDirector` integrates the accumulators and emits the four signals; every decision
is next door and checkable by handing it three values.

## Wiring one up

```gdscript
var director := EncounterDirector.new()
director.config = DirectorConfig.new()
add_child(director)                       # ABOVE the creatures -- see "The tick" below

behavior.director = director              # that is the whole coupling
director.register(behavior, suspicion)    # optional; exchange() registers on sight

# Optional, one line each, and both inert until the level connects them:
player.respawned.connect(func() -> void: director.note_respawn(player))
```

`players` is explicit-wins with a `player_group` fallback of `&"player"` — which
`prefab_player.tscn` already puts `PlayerBody` in, so a level that wires nothing at all
still gets a roam anchor.

The Director subscribes to `CreatureBehavior.attack_landed` itself at registration, so the
one-near-miss-per-encounter latch needs no wiring.

## The tick, and why the Director has its own

```text
_physics_process(delta) -> advance(delta)     integrate, derive, arbitrate, publish
exchange(creature, report)                    file the report, hand back the directive
```

**`exchange()` accumulates nothing**, and that is the load-bearing half. It is called once
per creature per frame from `CreatureBehavior`'s step 4, so a Director that integrated
there would advance the *party-wide* lull once per creature — a level with two aliens would
get bored twice as fast, in tree order, with nothing in the log.

Deriving a delta from `report.time_in_state` is worse: that field resets to `0.0` on every
transition, so the difference is **negative on exactly the tick a hunt begins**, and menace
would silently fail to integrate on the one edge this module exists to price.

`Time.get_ticks_msec()` is banned here and correctly — it ignores `get_tree().paused` and
`Engine.time_scale`, and no test could drive it.

**Put the Director above the creatures in the scene.** Godot ticks in tree order, so the
directive a creature reads was then integrated this frame rather than last. It is a
freshness preference and never a correctness requirement — two report fields are already
deliberately one tick behind, for the reason below.

**`CreatureBehavior._mute_subsystems()` does not name the Director**, which was true by
omission and is now a property: `verify_director_static.gd` reads that function's body and
fails if `director` appears in it, and `verify_director_runtime.gd` asserts this clock
advances once per frame rather than zero or twice.

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

A track that has never been advanced publishes exactly this, so *"the day the Director lands
nothing in Behavior changes"* is true on frame one and asserted in
`test_director_invariants.gd`.

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

**`attack_window_open` and `lurking_at_tunnel_mouth` are one tick behind.** The report goes up
at step 4 of the tick contract — before the transition check and before the tree — so both
carry what the previous tick's `HuntingState.refresh` worked out. Recomputing them at report
time would mean running the reachability probe and the range test twice per tick to be 16 ms
fresher, against a menace curve priced in seconds. Both are `false` outright in any state but
`HUNTING`.

## Where the numbers came from

director.md names every config field and **assigns a value to none of them**. Its only
calibration is the worked encounter, so that trace is what the defaults were solved against:

```text
t+0    lull .6 after two quiet minutes   ->  lull_full_s 200          (120/200 = .6)
t+0    lull .6 -> roam +.6, bias +.3     ->  max_roam_bias 1.0, ratio 0.5
t+58   menace 1.00 -> PEAK               ->  27 s of typical chase fills the meter
t+58   RELIEF: roam -.8, bias -.4        ->  relief_roam_bias -.8, the SAME 1:2 ratio
t+79   cooldown expires -> QUIET         ->  cooldown_s 20, from entering RELIEF
```

`test_worked_encounter.gd` replays the whole trace and `test_director_config.gd` asserts the
derivations, so a change that moves them fails rather than quietly going stale.

The trace's own intermediate menace figures are **not** reproducible under any single linear
rate — 0 to .87 in 21 s is .041/s, then .87 to 1.00 in 6 s is .022/s, with strictly *more*
terms on in the second window. The calibration target is therefore the headline claim: a hunt
begun at t+31 sates at t+58, which is 27 seconds.

## Six things the spec leaves open, and what was decided

**`bias_span` is listed in two configs.** `BehaviorConfig.bias_span` (0.15) already ships
with `threshold_shift()`, and fsm.md applies it on the Behavior side. **`BehaviorConfig`
owns it and `DirectorConfig` does not declare it** — a second copy would be a dial that
looks live and does nothing, and the moment either was tuned they would disagree silently.
The Director's half of the same lever is the *magnitude* it emits, which is
`max_roam_bias × escalation_bias_ratio`. Asserted by property sweep.

**`cooldown_s` / `cooldown_separation_m` are named and never defined.** RELIEF ends when the
timer has run out **and** the creature is separated — both clauses, never either. A timer
alone lets a creature that never actually left re-arm the cycle on the player's doorstep; a
distance gate alone lets one that sprints away re-arm in three seconds, and the exhale has no
length. Reaching `UNALERTED` satisfies the distance clause outright, because Behavior's own
`RETREATING → UNALERTED` already gated on `retreat_separation_m` with `retreat_max_s` as a
backstop — and second-guessing it would be the Director *conducting* a retreat.

**`attack_pressure` has no observable.** The report carries `attack_window_open: bool`, so it
is priced `1.0 / 0.0`. That flag deliberately stays true across `attack_cooldown_s` — the
rate limit is a `BtCooldown` decorator *outside* the condition — so it already means
"sustained in-reach pressure", which is what a per-second rate wants.

**The pacing diagram draws three edges and there are four.** `BUILD → QUIET` is real:
Behavior lost the hunt on its own, nothing was ever forced, `disengage_reason` stays `NONE`,
and the encounter ends when the menace it built has drained. Behavior's own `&"lost"` reason
carries downstream.

**PEAK lasts exactly one tick.** Reaching it *is* the SATED order, which arms the cooldown,
which makes the next tick derive RELIEF. That is deliberate: a phase log containing PEAK is
the log saying the exit was earned, so swallowing it would make the two exits
indistinguishable in the one place a designer looks. A STALLED hunt never passes through it.

**The debug margin reads a collaborator field.** `get_best_player_candidate()` cannot answer
"who came second" when the best *is* the target, so `EncounterPacing.runner_up()` reaches
`suspicion.player_beliefs` — debug only, behind a null guard. Arbitration itself uses only
the three methods director.md names, so the spec's interface claim stays literally true.

## Rules the code enforces on itself

`tools/verify_director_static.gd` turns director.md's "Design invariants" into build
failures. The bans are on **verbs, not nouns** wherever a type name is legitimate —
`CreatureSuspicion` is a type the Director is granted three reads of.

| Check | What it forbids |
|---|---|
| `belief` | `submit_evidence`, `submit_disconfirmation`, `reduce_suspicion`, `clear_hotspot` |
| `navigation` | `set_goal`, `clear_goal`, `plan_route`, `CreatureNavigation`, `distance_remaining` |
| `perception` | `CreaturePerception` **and the noun itself** — the interface does not exist |
| `hfsm` | `reset_to`, `evaluate_transitions`, `consume_disengage`, `set_state`, `force_state` |
| `clock` | `Time.get_`, `OS.get_ticks`, `Engine.get_physics_frames`, `Engine.get_process_frames` |
| `truth` | `global_position`, `get_nodes_in_group` — **anywhere but `director_party.gd`** |
| `truth-keeper` | and `director_party.gd` may not name `EncounterDirective`, `menace`, `permit_hunt`… |

That last pair is the one worth understanding. *"The Director may know the truth, and may
only emit bias"* is a promise until something can check it, so every truth-read lives in one
file and the boundary is enforced from both sides: `verify_behavior_static.gd`'s
`WORLD_EXEMPT` names `director_party.gd` and nothing else under `gameplay/director`, and this
verifier forbids that same file from knowing what a directive is. **Truth goes in; a
`Vector3` and an `Array[Node3D]` come out.**

## Looking at it

```sh
GODOT=/path/to/Godot   # 4.7.x

$GODOT --path . res://gameplay/director/sandbox/director_sandbox.tscn
```

The whole cycle, with a player you can drive, mine with, and be killed by. `4` multiplies the
Director's clock (1× / 4× / 16×) so a 200-second lull is watchable; the **config is untouched**,
because a sandbox with tuned numbers proves only that *some* config works.
`3` fills the lull, `5` fills menace to the peak. Full key list in the class docstring.

`gameplay/creature/behavior/sandbox/encounter_sandbox.tscn` also has a Director attached now,
on the shipped cadence with no way to hurry it. Its arc used to end
`hunting -> retreating (lost)` — suspicion starvation, which is a fact about the creature's
memory rather than a decision about the scene. It now ends `(director)`, carrying `SATED` or
`STALLED`.

## Running the suites

```sh
$GODOT --headless --path . --import

$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json \
  -gdir=res://gameplay/director/tests -gexit

$GODOT --headless --path . --script res://gameplay/director/tools/verify_director_static.gd
$GODOT --headless --path .         res://gameplay/director/tools/verify_director_runtime.tscn
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable script
prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml` greps the
output for that reason.

**The runtime verifier must be the `.tscn`, never `--script`.** A node added during
`SceneTree._initialize()` never receives `_ready()`, so a bare script would run nothing,
print nothing and exit 0 — which looks exactly like a pass.

## Names this module reserves project-wide

`EncounterDirective`, `EncounterReport`, `DirectorConfig`, `EncounterTrack`,
`EncounterPacing`, `DirectorParty`, `EncounterDirector`, `DirectorDebugPanel`,
`DirectorSandbox`. Godot's `class_name` table is flat and project-wide, so a second
declaration is a hard parse error at project scan that takes the whole project down — the
same hazard `suspicion.md` documents for `SuspicionEvidence`. `CrawlerCameraDirector` in
`prototypes/tentacle_crawler/` is unrelated and does not collide.

`EncounterReport.state` is typed `CreatureState.State`, from
`gameplay/creature/behavior/creature_state.gd`. `director.md`'s snippet writes
`state: CreatureState`, naming the class rather than the enum; the enum is what is meant.

## Not included

**Spatial Memory**, so `roam_anchor` is the centroid of where players *actually are* rather
than of nests the creature remembers them near. That is what the spec asks for and it is
still only a weighting — `CreatureNestMemory.score` spends it on a list of nests the creature
already knows — but a remembered anchor would be the more honest version once that module
exists.

**Damage.** `attack_landed` still resolves nothing; `director_sandbox.gd` simulates a
knockback and a respawn so the GRACE → LETHAL latch is visible, and that lives in the scene
rather than in `gameplay/`.

**Multi-creature arbitration beyond one track each.** Lull, session history and the calm gate
are already party-wide and take the `max` across creatures, and two aliens each get their own
menace, phase, target and near-miss. What is untested is whether two of them hunting the same
player at once *reads* correctly, because nothing in the project spawns two.

**`.tres` config presets.** Every field has a working default.
