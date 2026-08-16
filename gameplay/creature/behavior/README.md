# Creature Behavior

The hinge. Everything upstream — Perception, Suspicion — describes the world; everything
downstream — Navigation, Movement — executes. This is the only system that turns belief
into action, and it answers exactly one question:

> Given what the creature currently believes, what should it do?

Spec: [`documentation/design/alien/fsm.md`](../../../documentation/design/alien/fsm.md),
with [`director.md`](../../../documentation/design/alien/director.md) authoritative for what
each `EncounterDirective` field means.

```
   CreatureSuspicion        EncounterDirective
        │  belief                │ pressure and permission
        ▼                        ▼
   ┌──────────────────────────────────┐
   │        CreatureBehavior          │
   │                                  │
   │   CreatureHfsm    persistent mode│
   │        │                         │
   │   BehaviorTree    moment-to-moment
   └────────────────┬─────────────────┘
                    │ goal
                    ▼
            CreatureNavigation
```

Two layers, and the split is load-bearing. The HFSM answers *what set of rules am I
operating under?*; the trees answer *what action makes sense right now?* **Only the HFSM
changes state.** A tree returns actions; having nothing useful to do is a fact the HFSM
reads, not a transition the tree performs.

## Scope

| | |
|---|---|
| **The tree framework** | `BtNode` and the six node types from fsm.md's table. Domain-free and enforced as such. |
| **The HFSM** | All four states, every transition guard, `min_dwell_s`, the `force_disengage` latch, hunt sustain. |
| **`UNALERTED`** | Real tree: nest choice, travel, dwell. |
| **`INVESTIGATING`** | Real tree: travel to the best unresolved location, search, re-aim. |
| **`HUNTING`, `RETREATING`** | **Guards only.** Both trees are one node that holds still. |

`HUNTING` needs an attack, a tunnel-mouth lurk and a target estimate; `RETREATING` needs nest
scoring with the distance term inverted and a loud/quiet split on `disengage_reason`. Neither
is stubbed into something that *appears* to work: `BtDoNothing` reports `RUNNING`, because a
state with nothing to do is a fact and not a success.

The Director itself is not built either — see [`gameplay/director/`](../../director/README.md).
`EncounterDirective.neutral()` is what a creature runs on without one.

## Running the suites

```sh
GODOT=/path/to/Godot   # 4.7.x

# A new class_name does not resolve until the project is re-imported, and the same run
# generates the .uid sidecars the static suite checks for.
$GODOT --headless --path . --import

$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json \
  -gdir=res://gameplay/creature/behavior/tests -gexit
$GODOT --headless --path . --script res://gameplay/creature/behavior/tools/verify_behavior_static.gd
$GODOT --headless --path .         res://gameplay/creature/behavior/tools/verify_behavior_runtime.tscn
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable script
prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml` greps the output
for that reason.

**The runtime suite must be run as its `.tscn`.** A node added during
`SceneTree._initialize()` never receives `_ready()`, so `--script` on
`verify_behavior_runtime.gd` runs nothing, prints nothing and exits 0.

## Looking at it

```sh
$GODOT --path . res://gameplay/creature/behavior/sandbox/behavior_sandbox.tscn
```

The sandbox instantiates the **suspicion** sandbox whole, which instantiates perception's in
turn — the room, the player, the creature and both overlays all come from underneath, and
this scene adds only navigation, the decision layer and a body that moves. Keys `1`–`5`,
`WASD`, `V`, `G`, `L`, `R`, `[`, `]`, `Tab` and `Y` belong to the two inner sandboxes; this
one adds:

| Key | |
|---|---|
| `6` | **Force `UNALERTED`.** The way back out of the two stub trees. |
| `7` | plant a nest where the player is standing |
| `8` | put the creature and its nests back the way they started |
| `B` | toggle the behavior panel and the goal marker |

The divider splits the room into two wings with a 3 m doorway, and there are two nests in
each — so a cross-wing choice has to route through the doorway and a same-wing one does not.
Watch it wander for a minute, then walk the player into the far wing and press `2` a few
times **from two or three spots several metres apart**, then walk away. Both halves of that
matter. One drill leaves the strongest hotspot around 0.17, under `investigate_threshold`, and
the alien correctly ignores it; a second takes it past 0.31 and it comes to look. And drilling
from one spot makes a hotspot a single `search_half_extent` sweep can clear, which resolves
tidily and never re-aims — spreading the noise makes a hotspot wider than one sweep, which is
the only situation where the second thing below is visible at all. Two things are worth
watching, and neither is checkable any other way:

- **The alien must leave a nest after its dwell and pick a different one.** The panel's
  action line should read `travel_to_nest` → `idle_at_nest` for `nest_dwell_s` →
  `travel_to_nest` to a *different* pad. If it settles in, `at_nest` has gone back to asking
  about proximity instead of intent — the dwell ends, the creature is still standing in the
  nest, so the idle branch wins again and re-arms its own timer. Nothing errors; the symptom
  is an alien you always know the location of. Watch four or five cycles rather than one:
  ping-ponging between the same two nests is the other failure, and it still looks like
  movement.
- **The goal marker must move as the creature searches a hotspot wider than one sweep.** The
  white spike is the best unresolved location and the amber bar is where navigation was
  actually sent; they are allowed to differ by up to `goal_refresh_m`, and that gap is the
  deadband rather than a bug. Each completed search should walk the bar to a new part of the
  region. **It is the bar moving that is the tell, not how the state ends** — a hotspot big
  enough legitimately outlasts `investigate_timeout_s` and exits on `(timeout)` having
  genuinely searched three or four places, which is correct. The failure is a bar that sits
  still: the alien arrives, searches, and searches that one point for the full timeout while
  the best unresolved location quietly walks off without it. That is `arrived_at_goal` having
  lost its first clause, and it reads as a bug in disconfirmation when it is a bug in the tree.

`HUNTING` and `RETREATING` hold perfectly still, because both trees are one `BtDoNothing`
that reports `RUNNING`. An alien that escalates has not hung — press `6`. And
`feedback_alertness` starts off: press `L` once to turn suspicion's own alertness write back
on and watch it fight Behavior's step 6 for the readout, which is what
[`perception/README.md`](../perception/README.md) means by "the last writer of the frame
wins".

## Six deliberate deviations from the spec

**1. The abort contract cannot be implemented as written, so goals are owned rather than
cleared.** fsm.md wants a `RUNNING` leaf that is not reached again aborted *"before any new
leaf ticks"*, and every action that calls `set_goal` to call `clear_goal` in `abort`. Both
cannot hold: a reactive tree does not know which leaf will run until it has ticked, so the
abort necessarily happens after — and the naive version has the outgoing leaf's clear wipe the
incoming leaf's freshly-set goal. The alien stops moving, holding a route to nowhere, and
nothing errors.

`BehaviorGoal` arbitrates by owner instead: `release` is a no-op unless the caller still holds
the goal. Ordering stops mattering and fsm.md's rule stays literally true in the action code.
It also owns the `goal_refresh_m` deadband in one place — `CreatureNavigation.set_goal` nulls
the route *and* resets the 2 s stuck watchdog, so an action re-issuing every frame disables the
only backstop against a wedged alien.

**2. Aborting is not the same as "no longer running".** A leaf that finished this tick was
still *reached*, and aborting it would make every completed action undo itself. `BehaviorTree`
tests for a stale `RUNNING` status rather than for identity alone. This was a real bug, caught
by `test_bt_abort.gd` before anything used the framework.

**3. `INVESTIGATING` needs two clauses to decide it has arrived.** After a search the best
unresolved location moves — that motion is the whole of suspicion.md's spatial resolution — but
the body has not, so `follower.is_finished` is still true and the search branch wins again. The
alien searches one spot until the timeout and the hotspot never resolves. `arrived_at_goal`
therefore requires that the committed goal *still is* the desired location **and** that
navigation says we are there. Recomputing the desired location before the tree ticks is
necessary and, on its own, not sufficient.

**4. `travel_to_nest.abort` keeps the chosen nest.** The abort that fires most often is not an
interruption — it is *arrival*, one tick after the idle branch takes over. Clearing the intent
there destroys exactly what `idle_at_nest` is about to read, and with a small nest list the
alien arrives and then stands there having forgotten why. Re-choosing on a genuine interruption
happens in `UnalertedState.enter`.

**5. Retreat separation is measured from belief, and `roam_anchor` is not in the chain.**
fsm.md does not say what `retreat_separation_m` is measured *from*, and the obvious candidate is
the wrong one: `roam_anchor` is derived from real player positions, so a Director whose anchor
tracked the party could hold an alien in `RETREATING` indefinitely. The chain is the hunt's last
credible target position, then the strongest hotspot captured *once* on entry, then the
creature's own position. It is Euclidean, unlike the Director's menace term.

`retreat_max_s` is an addition, not a deviation to be proud of: fsm.md gives `retreat_to_nest`
no `UNREACHABLE` failure clause where `travel_to_nest` has one, so an unreachable far nest plus
unmet separation leaves the state with no reachable exit. That asymmetry looks like a doc bug.

**6. The table order means the direct hunt is rare, and that is kept.** fsm.md lists
`UNALERTED → INVESTIGATING` above `UNALERTED → HUNTING`, and evaluates first-match-wins. A touch
strong enough to name a player also raises a hotspot well above `investigate_threshold`, so the
investigate row nearly always wins and the alien spends `min_dwell_s` coming to look before it
commits. That reads as a beat — *something is coming* before *it is coming for me* — so the
order is followed rather than quietly reversed.

## Two consequences of the alertness table worth knowing

`alertness_for[UNALERTED]` is `0.0`, below `PerceptionConfig.vision_activation_suspicion`
(0.25), so **vision is off while calm**. That is behavior.md §6 and it is deliberate. It has a
consequence the spec does not spell out: only vision and touch set `source_confidence` —
hearing never does — so with vision gated, `UNALERTED → HUNTING` can fire **on touch alone**. A
calm alien cannot be startled into hunting you by seeing you; you have to walk into it.

`alertness_for[RETREATING]` is `0.2`, also below the gate, so an alien walking away genuinely
stops looking. behavior.md §30's "will ignore a player who shoots it in the back" is not only a
transition rule here; it is also what the creature can perceive.

`BehaviorConfig.invariant_failures(perception)` takes the companion config and fails the build
if `alertness_investigating` or `alertness_hunting` ever drops below the gate — a searching alien
that cannot see also clears half as much per search, because the VISION bit drops out of the
disconfirmation mask.

## Rules the code enforces on itself

`tools/verify_behavior_static.gd` fails the build on each of these, because every one would
otherwise pass all 130 unit tests while destroying the property the tests exist to protect.

| Rule | Why |
|---|---|
| **`tree/` never names a creature subsystem** | The highest-value check here. A tree that knows what an alien is cannot be lifted into anything else, and "reusable" that is never checked against a second user is a claim rather than a property |
| No file names `submit_evidence` / `submit_disconfirmation` / `reduce_suspicion` / `clear_hotspot` | Belief has three doors and Behavior is not one. An action that lowered a number would resolve hotspots crisply and work visibly better, which is exactly why no behavioural test would flag it |
| Nothing but the facade reads a group or a `global_position` | The Director may know the truth precisely because it may not act on it. The facade is exempt for nests and the body, both level geometry rather than player state |
| No physics query anywhere | Navigation and Perception each own a probe; Behavior reaches the world only through them |
| Nothing reads a wall clock | `Time.get_ticks_msec()` ignores `get_tree().paused` and `Engine.time_scale`, so an alien would keep deciding in a paused game, and no test could drive it |
| `conditions/` never names `set_goal` or `request_activity_scan` | Every condition is re-evaluated from the root every frame, so one that commanded would command once per frame forever |
| Every `.gd` has its `.uid` sidecar | A missing one is regenerated with a fresh id, and scenes referencing the script by uid then point at nothing |
| A default `BehaviorConfig` agrees with a default `PerceptionConfig` | |

**Comments are stripped before any token check**, and that is not a nicety: both the wall-clock
and domain-free rules lived in the GUT suite first and both failed on their own explanatory
prose. That is why file-scanning lives here rather than in `tests/`.

`tests/test_behavior_invariants.gd` covers the rest — including a sweep asserting the facade has
grown no `set_state` / `reduce_suspicion` / `move_to` method, because a fourth door into belief
or a second way to change state makes every other rule here decorative.

## Wiring one up

```gdscript
var behavior := CreatureBehavior.new()
behavior.config = preload("res://.../my_creature_behavior.tres")
behavior.suspicion = suspicion
behavior.perception = perception
behavior.navigation = navigation
behavior.body = self
add_child(behavior)

behavior.state_changed.connect(_on_state_changed)     # for audio stings and debug
behavior.action_changed.connect(_on_action_changed)   # for animation
```

That is the whole of it. **`CreatureBehavior` owns the tick** and switches off the other three
facades' `_physics_process`, because all of them run their own and leaving them on
double-advances every clock — navigation would emit `motion_planned` twice per frame with the
same body state and the motor would consume both. Set `drive_subsystems = false` if a level or a
prototype wants to order the nine steps itself.

Nests are data:

```gdscript
behavior.nests = [$NestA, $NestB, $NestC]          # or drop CreatureNest markers in the level
behavior.set_nest_positions(my_positions)          # or hand it a PackedVector3Array
```

A `Director` is optional and duck-typed — anything with
`exchange(creature, report) -> EncounterDirective`.

## Tuning

`BehaviorConfig` is the whole temperament dial, the way `PerceptionConfig` is the whole
difficulty dial. The alien's *own* numbers — hearing range, hotspot decay, crawl speed — stay on
`PerceptionConfig`, `SuspicionConfig` and `LocomotionProfile`, because they are properties of
the creature rather than of its decision-making.

Seven defaults are measured values carried across from `prototypes/creature_awareness/` rather
than re-guessed: `investigate_threshold 0.25`, `investigate_timeout_s 45.0`, `nest_dwell_s 4.0`,
`arrive_distance 3.0`, `search_half_extent 4.0`, `search_thoroughness 1.0`,
`nest_recent_penalty_s 60.0`.

`goal_refresh_m` has a hard floor of 2.0 and `invariant_failures()` enforces it. See deviation 1.

## Not included

The `HUNTING` and `RETREATING` trees, and everything they need: an attack, a tunnel-mouth lurk, a target
estimate that ages, `attack_window_open` and `lurking_at_tunnel_mouth` on the encounter report (both
ship hardcoded `false`, which silently zeroes the Director's `w_attack` and `w_lurk` terms — a
stub, not tuning).

The Director. Spatial Memory, so `roam_anchor` has no producer yet. Any `.tres` config presets —
every field has a working default, so `BehaviorConfig.new()` runs without one.

A `tools/capture_sandbox.tscn`. Perception and navigation each have one and photograph a
`debug_draw`; this module's debug half is a text panel, so there is nothing yet whose pixels
are worth pinning down. Suspicion is in the same position and does without one too.

`prototypes/creature_awareness/` is untouched and still drives its own flat four-state FSM. It is
the natural first customer for this module.
