# Behavior — HFSM and Behavior Trees

## Purpose

Behavior answers:

> **Given what the creature currently believes, what should it do?**

It is the only system that turns belief into action. Everything upstream — Perception,
Suspicion, Spatial Memory — describes the world. Everything downstream — Navigation,
Movement — executes. Behavior is the hinge.

It has two layers, and the split is load-bearing:

```text
HFSM     persistent modes     "what set of rules am I operating under?"
Trees    moment-to-moment     "what action makes sense right now?"
```

The four modes stay explicit states rather than collapsing into one large tree because
they change the *rules*, not merely the chosen action. An alien that is hunting evaluates
noise differently, commits to a target across perception gaps, and is subject to Director
pacing — none of which is expressible as "a different branch fired this frame".

**Only the HFSM changes state. Trees never transition.** A tree returns actions; if it has
nothing useful to do, that is a fact the HFSM reads, not a transition the tree performs.

Companion document: `director.md`, authoritative for what each `EncounterDirective` field
*means*. This document is authoritative for the state set and the transition guards.

---

## The four states

**`UNALERTED`** — territorial ambient behaviour. The alien moves between nests, not along a
patrol route. Vision is dulled (low alertness context). It is not looking for you.

**`INVESTIGATING`** — resolve uncertainty about a *place*. The alien has a hotspot worth
walking to. It travels, searches, and lets Perception's disconfirmations resolve or fail to
resolve the belief. It does not have a target; it has a location.

**`HUNTING`** — pursue a credible *player*. The distinction from `INVESTIGATING` is the
whole reason both exist: **you investigate a where, you hunt a who.** Hunting requires a
`PlayerSuspicionCandidate`, not merely a strong hotspot. Hunting is also a commitment — it
survives brief perception loss, and `director.md` rather than evidence decides when it ends.

**`RETREATING`** — end the encounter legibly. The alien increases separation, heads for a
nest, and makes itself heard leaving. The player has to *know* it is over.

---

## Transitions

Evaluated **once per tick, before the tree ticks, in table order, first match wins**. Each
carries a named reason into `state_changed`. `bias` below is
`directive.escalation_bias × bias_span`, from the Director.

| From → To | Guard |
|---|---|
| `UNALERTED → INVESTIGATING` | strongest hotspot `.suspicion >= investigate_threshold − bias` |
| `UNALERTED → HUNTING` | candidate `.suspicion >= direct_hunt_threshold` **and** `.source_confidence >= hunt_confidence` **and** `directive.permit_hunt` |
| `INVESTIGATING → HUNTING` | candidate `.suspicion >= hunt_threshold − bias` **and** `.source_confidence >= hunt_confidence` **and** `directive.permit_hunt` |
| `INVESTIGATING → UNALERTED` | `get_hotspots_above(attention_floor)` is empty, **or** `time_in_state > investigate_timeout_s` |
| `HUNTING → RETREATING` | `directive.force_disengage`, **or** hunt sustain lost |
| `RETREATING → UNALERTED` | `time_in_state >= retreat_min_s` **and** separation `>= retreat_separation_m` |

Every state also honours `min_dwell_s` before any transition out, which is what stops an
alien on a threshold boundary flickering between modes.

### Three guards that need spelling out

**Investigate keys off the strongest hotspot, not overall suspicion.** Overall suspicion is a
scalar with no location — it can cross a threshold while giving Behavior nowhere to walk. The
hotspot check guarantees that entering `INVESTIGATING` comes with a destination. Overall
suspicion still serves the calm-down guard, the Director, and debug; it is not what opens
this door.

**Hunt sustain is what makes hunting a commitment.** It is lost only when *both* hold: no
candidate above `hunt_sustain_threshold` for a continuous `hunt_sustain_grace_s`, **and** no
unresolved suspicion within `hunt_sustain_radius` of the last credible target position.
Losing sight of the player does not end a hunt — the alien searches (`behavior.md` §28).

**`RETREATING` has exactly one exit.** There is no path back to `HUNTING` from a retreat, at
any suspicion level, for any evidence type. `behavior.md` §30 requires this or the Director
cannot reliably terminate an encounter, and an encounter that cannot be terminated has no
rhythm. The visible consequence is real: an alien walking away will ignore a player who
shoots it in the back.

---

## Tick contract

One `_physics_process`, one order, no exceptions.

```text
1  clock += delta                        injected, never a wall clock
2  perception.advance(delta)             emits evidence / disconfirmation
3  suspicion.advance(delta)              decay, hotspot merge, pruning
4  directive = director.exchange(creature, build_report())
                                         EncounterReport up, directive down
5  hfsm.evaluate_transitions()           once; a change aborts the old tree
6  perception.set_alertness_context(alertness_for[state])
7  tree[state].tick(context)             may call navigation.set_goal / clear_goal
8  navigation.advance(delta, position)
9  motor consumes the NavMotionCommand
```

Steps 2 and 3 are ordered: evidence must land before decay runs and before any query reads
it. Step 4 happens once — the directive is held constant for the whole tick, per
`director.md`'s one-directive-per-tick invariant. Behavior is also the *source* of the
`EncounterReport`: current state, time in state, position, visual contact, attack window,
lurk status, and the two Navigation metrics (`follower.distance_remaining()`,
`route.status != UNREACHABLE`) that the Director has no other legitimate way to read.

Step 6 is the one place Behavior writes to Perception, and it is legitimate: vision is
designed to sharpen once the creature is already suspicious (`behavior.md` §6). That is the
creature's attention responding to its own belief. The Director has no such channel.

**The clock is the injected `delta`, never `Time.get_ticks_msec()`,** which ignores
`get_tree().paused` and `Engine.time_scale`. Promoted verbatim from the prototype, and from
the same rule in all three shipped modules.

**Arrival has no signal.** `CreatureNavigation` emits no `goal_reached`. Arrival is
`navigation.follower.is_finished(at)`, with an `arrive_distance` fallback for a route that
never attached. A `PARTIAL` route still finishes — the alien reaches the far end of what it
could reach and acts from there, which is correct: it searches the mouth of a shaft it cannot
enter, and correctly fails to resolve a hotspot on the other side.

---

## The behavior tree framework

None exists in this repository. This is the whole of what must be built, and it is
deliberately small.

```gdscript
class_name BtNode

enum Status { SUCCESS, FAILURE, RUNNING }

func tick(ctx: BehaviorContext) -> Status
func abort(ctx: BehaviorContext) -> void
```

| Node | Behaviour |
|---|---|
| `BtSelector` | Ticks children in order; returns the first non-`FAILURE`. All failed → `FAILURE`. |
| `BtSequence` | Ticks children in order; returns the first non-`SUCCESS`. All succeeded → `SUCCESS`. |
| `BtCondition` | `SUCCESS` or `FAILURE` only. Never `RUNNING`, never side-effecting. |
| `BtAction` | Any status. The only nodes permitted to command anything. |
| `BtInverter` | Swaps `SUCCESS` and `FAILURE`; passes `RUNNING` through. |
| `BtCooldown` | `FAILURE` until `seconds` have elapsed since its child last succeeded. |

### Fully reactive, no sibling memory

The tree is re-ticked **from the root every frame**. Conditions are re-evaluated even when a
deeper leaf is `RUNNING`, and no composite remembers which child succeeded last tick.

This is the right trade for a predator. A memory-BT would keep the alien walking to a stale
hotspot while a louder, closer lead went unexamined, because the branch that chose the stale
one is never revisited. Reactive costs a few condition evaluations per frame and buys an
alien that changes its mind the instant the evidence does.

### The abort contract

The tree records which leaf returned `RUNNING` last tick. On the next tick, **if that leaf is
not reached again, `abort()` is called on it** before any new leaf ticks. `abort()` also
fires on state change and on teardown.

This is not optional bookkeeping. Actions own a navigation goal. Without abort,
`chase_target` yielding to `lurk_at_tunnel_mouth` leaves the chase goal live, and the alien walks
to a position nothing asked for. Every action that calls `set_goal` must `clear_goal` in
`abort`.

### Typed context, not a blackboard

```gdscript
class_name BehaviorContext

var suspicion: CreatureSuspicion
var navigation: CreatureNavigation
var perception: CreaturePerception
var body: Node3D
var config: BehaviorConfig
var directive: EncounterDirective
var clock: float
```

A string-keyed `Dictionary` blackboard is the conventional choice and the wrong one here: it
defeats autocomplete, hides typos as silent nulls, and gives `gdlint` nothing to check.
Per-state memory that outlives a tick — the active hotspot id, the chosen nest, the lurk
deadline — lives on the **state object**, not the context, so the context stays a pure
per-tick view.

---

## The four trees

```text
UNALERTED
Selector
├── Sequence
│   ├── Condition  at_nest
│   └── Action     idle_at_nest
└── Action         travel_to_nest

INVESTIGATING
Selector
├── Sequence
│   ├── Condition  arrived_at_goal
│   └── Action     search_area
└── Action         investigate_location

HUNTING                                    (behavior.md §26)
Selector
├── Sequence
│   ├── Condition  can_attack
│   └── Action     attack
├── Sequence
│   ├── Condition  has_target_estimate
│   └── Action     chase_target
├── Sequence
│   ├── Condition  target_beyond_reach
│   └── Action     lurk_at_tunnel_mouth
└── Action         search_area             (last credible region, §28)

RETREATING
Selector
├── Sequence
│   ├── Condition  disengage_was_sated
│   └── Action     retreat_to_nest(loud)
└── Action         retreat_to_nest(quiet)
```

`HUNTING`'s ordering is the priority claim: bite beats pursue beats wait beats search. The
`RETREATING` split reads `directive.disengage_reason` — a `SATED` exit leaves loudly and
unhurried so the player gets the exhale; a `STALLED` exit leaves quietly, because nothing
was earned.

---

## Action library

Every action: what it reads, what it commands, how it terminates, what `abort` must undo.

| Action | Commands | Terminates |
|---|---|---|
| `idle_at_nest` | nothing (animation only) | `SUCCESS` after `nest_dwell_s` |
| `travel_to_nest` | `set_goal(nest)` | `RUNNING` until arrival; `FAILURE` if route `UNREACHABLE` |
| `investigate_location` | `set_goal(location)` | `RUNNING` until arrival; `FAILURE` on a dead hotspot |
| `search_area` | `request_activity_scan(region, thoroughness)` | `RUNNING` while `is_activity_scan_active()` |
| `chase_target` | `set_goal(estimate)` on drift | `RUNNING`; `FAILURE` with no estimate |
| `lurk_at_tunnel_mouth` | `set_goal(estimate)`; a PARTIAL route stops at the mouth | `SUCCESS` at a randomised deadline |
| `attack` | damage, per `directive.lethality` | `SUCCESS` either way |
| `retreat_to_nest` | `set_goal(far nest)` | `RUNNING` until arrival |

Every action that calls `set_goal` calls `clear_goal` in `abort`.

`travel_to_nest` and `retreat_to_nest` share one scoring function, and it is where the
Director's ambient bias lands (`director.md`, *Ambient placement bias*):

```text
nest_score = distance_term + recency_term + directive.roam_bias × proximity_to(roam_anchor)
```

`nest_recent_penalty_s` keeps the alien from ping-ponging between two nests. `roam_anchor`
weights a list of nests the creature already knows — it is never itself a goal, so the alien's
movement stays explicable in terms of its own knowledge. Only the odds changed.

### Four traps, each already paid for once in the prototype

**`get_best_unresolved_location(id)` returns `Vector3.ZERO` for an id that is no longer
live** — not the hotspot centre, whatever its docstring says. Unguarded, an alien whose
hotspot resolves mid-approach sets off for the world origin. `investigate_location` must
re-check the id is live and return `FAILURE`, not navigate to zero.

**A degenerate scan AABB aborts the scan and reports a *zero-strength* disconfirmation**,
which suppresses nothing. The alien arrives, searches, and the hotspot never resolves — and
it looks like disconfirmation is broken when the region is. `search_area` builds its region
from `search_half_extent` and must never hand over an empty volume.

**Re-issuing `set_goal` every frame thrashes the route planner.** `chase_target` re-issues
only when the target estimate has moved more than `goal_refresh_m`.

**Lurk duration must vary** (`behavior.md` §29). A fixed timer is something the player counts,
and a tunnel with a known safe interval stops being a gamble.

### Two rules actions may not break

**An action never writes belief.** `search_area` does not subtract suspicion — it makes the
creature dwell and sweep so that *Perception* emits the disconfirmation, which suppresses the
belief. Suspicion has exactly three doors: evidence, disconfirmation, and the clock. Anything
here that reached in and lowered a number would work visibly better and destroy the design.
`attack` likewise *reads* `directive.lethality`; it does not decide lethality.

**An action never moves the body.** It commands Navigation. Movement is downstream and owns
acceleration, turning and collision response.

---

## Configuration, signals, debug

`behavior/behavior_config.gd`, a `Resource`, in the house style of the shipped
`perception_config.gd` and `suspicion_config.gd`: `const DEFAULT_*` above each `@export`,
`@export_group` sections, `@export_range` with units and a `##` per field, usable from a bare
`.new()`, and `invariant_failures() -> PackedStringArray`.

```gdscript
# Thresholds     investigate_threshold, hunt_threshold, direct_hunt_threshold,
#                hunt_confidence, attention_floor, bias_span
# Commitment     min_dwell_s, investigate_timeout_s, hunt_sustain_threshold,
#                hunt_sustain_grace_s, hunt_sustain_radius,
#                retreat_min_s, retreat_separation_m
# Actions        nest_dwell_s, nest_recent_penalty_s, arrive_distance,
#                search_half_extent, search_thoroughness,
#                goal_refresh_m, lurk_min_s, lurk_max_s
# Perception     alertness_for[state]
```

```gdscript
signal state_changed(from: State, to: State, reason: String)
signal action_changed(action: StringName)
```

One debug line must answer "why is it doing that": state, time in state, active action, the
value that fired the last transition, and the directive fields currently constraining it.

---

## Promotion path from `prototypes/creature_awareness/`

The prototype is a stepping stone by construction — its behaviour file says so — and this is
the mapping.

| Prototype | Target |
|---|---|
| `State.IDLE`, `State.WANDER` | the `UNALERTED` tree (`idle_at_nest`, `travel_to_nest`) |
| `State.INVESTIGATE` | the `INVESTIGATING` tree |
| `State.SEARCH` | **demoted from a state to the `search_area` action** inside `INVESTIGATING` |
| — | `HUNTING` and `RETREATING` are genuinely new; nothing maps to them |
| `creature_awareness_knobs.gd` §Behaviour | `behavior_config.gd` `@export`s, one per const |
| `INVESTIGATE_THRESHOLD 0.25`, `INVESTIGATE_TIMEOUT 45.0`, `NEST_DWELL 4.0`, `ARRIVE_DISTANCE 3.0`, `SEARCH_HALF_EXTENT 4.0` | the measured starting values, carried across rather than re-guessed |

Graduating unchanged: the "behaviour never writes belief" rule, the injected `clock`, the
`@export`-injected subsystem references, and all four trap notes in the prototype's file
docstring. The knobs file's own caveat holds too — the alien's *own* numbers (hearing range,
hotspot decay, crawl speed) stay on `PerceptionConfig`, `SuspicionConfig` and
`LocomotionProfile`, because they are properties of the creature, not of Behavior.

Not graduating: the flat `enum State`, and the prototype's map, stimulus and camera rigs.

---

## Design invariants

**Only the HFSM changes state.** Trees select actions; they never transition.

**Transitions are evaluated once per tick, in table order, first match wins.**

**The tree is re-entered from the root every tick.** No sibling memory.

**A `RUNNING` leaf that is not reached again gets `abort()`.** No leaked navigation goals.

**Actions never write belief.** Perception is the only door into Suspicion.

**Actions never move the body.** They command Navigation.

**Conditions never have side effects.** A condition that mutates makes the reactive re-tick
unsound.

**Every transition carries a named reason**, in the signal and in debug.

**Behavior honours the Director's directive at a moment of its own choosing.** A latch is
consumed at the next transition check, never mid-action.
