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
| **The HFSM** | All five states, every transition guard, `min_dwell_s`, the `force_disengage` latch, hunt sustain. |
| **`UNALERTED`** | Real tree: nest choice, travel, dwell. |
| **`INVESTIGATING`** | Real tree: travel to the best unresolved location, search, re-aim. |
| **`HUNTING`** | Real tree: bite, chase, wait out a gap it cannot fit through, sweep the last credible region. |
| **`RETREATING`** | Real tree: a far nest, loudly or quietly depending on how the encounter ended. |
| **`RECONSIDERING`** | No tree worth the name, on purpose: hold still, write off a lead that cannot be reached, go back to wandering. |

`BtDoNothing` is `RECONSIDERING`'s whole tree, and it was written for this and waited for it.
A state with nothing to do is a fact rather than a success, which is why it reports `RUNNING`
and the state ends by transition instead.

### The loop `RECONSIDERING` exists to break

An alien that hammers a wall for the rest of the session, and every layer reports itself
healthy while it does. A hotspot on the far side of rock the creature does not fit through
produces a **`PARTIAL`** route, and a partial route is deliberately not a failure — it
*finishes*, at the near face, so `is_arrived` answers yes. The tree searches there, the search
disconfirms there, the lead stays exactly as hot as it was, and `investigate_location`
re-commands the goal on every tick the search cooldown is closed. On screen it reads as the
action flipping between `search_area` and `investigate_location` several times a second.

`investigate_timeout_s` does not save it. That row drops to `UNALERTED` without writing the
lead off, and `UNALERTED` walks straight back in on the next tick, because `_take_lead` takes
the strongest board entry and has no memory of having just failed on it. It turns a
one-second loop into a forty-five-second one.

So the give-up row had to do two things at once: notice, and *remember*. Noticing is
`InvestigatingState._note_progress`; remembering is `CreatureSuspicion.mark_unreachable`,
called on entry to `RECONSIDERING`. Three details in the noticing were each arrived at by
watching it fail:

- **The route's verdict is latched, not read.** `investigate_location` releases the goal the
  moment `search_area` takes the tick, and releasing a goal clears the route — so for most of
  the ticks the creature spends at a wall there is no route to ask. A check that read it
  directly found nothing and reset itself forever.
- **The reachability clause comes before the arrival clause.** A hotspot fed by repeated noise
  grows to `hotspot_max_radius` (14 m), and "inside the hotspot" then calls a creature standing
  ten metres short of it arrived.
- **The lead is tracked by position, not by id.** Hotspot identity is carried by shared
  contributing evidence, so a lead *being searched* is renumbered every few seconds while
  sitting still — measured, twice inside eight seconds, and the deadline was never reached.

**There is no crevice type, no tunnel marker and no passability flag**, and there must not be.
A passage the alien cannot follow you through is a passage narrower than twice
`ClearanceProfile.min_traversal_clearance` — no candidate survives inside it, no edge is ever
validated through it, and the route to anything beyond it comes back `PARTIAL`. So `HUNTING`
infers "they went somewhere I cannot go" from its own navigation graph, which is the only
thing it legitimately knows, and the inference covers every gap too tight for it rather than
the ones somebody remembered to tag. See `behavior.md` §29 and §36.

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
| `6` | force `UNALERTED`, without a transition reason |
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

This room has no gap too narrow for the alien, so an escalation here reads as chase, bite and
walk-away and never as a lurk. **The tunnel-mouth beat lives in `encounter_sandbox.tscn`**,
below, which builds its own cave for exactly that reason. And `feedback_alertness` starts off:
press `L` once to turn suspicion's own alertness write back on and watch it fight Behavior's
step 6 for the readout, which is what
[`perception/README.md`](../perception/README.md) means by "the last writer of the frame
wins".

### The whole encounter

```sh
$GODOT --path . res://gameplay/creature/behavior/sandbox/encounter_sandbox.tscn
```

`behavior.md` §35 end to end, in a 60 m cave this scene builds itself. Walk with `WASD`,
make noise with `1` and `2`, and the arc comes out of the systems rather than out of this
file: a noise becomes a lead, the alien comes to look, it sees you, it chases, you slip into
a gap 1 m across that it cannot fit through, it stops at the mouth and waits, and eventually
it gives up and walks home. `G` toggles the graph, `F` the scored crawl fan, `R` resets.

**It proves its own premise on startup** and prints the line, in the three parts
`verify_navigation_runtime.gd` uses — no edge crosses the slot; the refuge has 30 nodes and
none is `reachable_from` this side; the route to it is `PARTIAL` and stops short. A cave
whose refuge simply had no nodes would pass the first part for entirely the wrong reason.

Five things are worth watching, and none of them is checkable any other way:

- **The wait must be a different length every time.** Press `R` and do it again. A countable
  wait turns a gamble into a known safe interval, and a gap with a known safe interval is
  just a door.
- **The creature must stop at the mouth and not clip into it.** `G` is the check: green is
  `NORMAL_VOLUME`, amber is `WIGGLE`, and **nothing at all** may cross the slot. The standoff
  is not tuned — it is where a `PARTIAL` route ends.
- **Hiding must not clear suspicion.** The hunt ends on sustain loss, never because the
  hotspot resolved: the alien cannot sweep a region it cannot walk into, so the belief it
  holds about you can only be worn down by the clock. You are physically safe and still
  believed in. The transition log must read `lost`, never anything about the hotspot.
- **A retreating alien must ignore you.** Stand up and drill at it mid-retreat. If it turns
  round, `RETREATING`'s single exit is broken and the Director can no longer end an
  encounter.
- **The arc must run without intervention.** `hotspot → candidate → lost → separated` in the
  panel's transition log, with only walking and noise as input. If a beat needs a keypress,
  something upstream has stopped feeding the next one.

**`F` is the avoidance demo**, and it is the only overlay in the project that shows
`NavAvoidance.risk` changing a decision: length carries the score, so the winner is the
longest ray, and you can watch the fan bend around the pillar mid-chase.

## Seven deliberate deviations from the spec

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

`retreat_max_s` is an addition rather than a deviation, and it survives the `RETREATING` tree
landing. The doc-bug half is fixed: the state reuses `travel_to_nest` outright, so both modes
now carry the same `UNREACHABLE` clause and fsm.md's asymmetry is gone. But that clause turns
out to be narrower than it reads — **against a baked graph, a target outside it comes back
`PARTIAL`, not `UNREACHABLE`**, because a partial route is deliberately not a failure. So an
alien sent to a nest it can only get halfway to walks at rock without ever failing, and an
alien whose every known nest sits inside `retreat_separation_m` of where it gave up has nowhere
to walk that would end the encounter at all. Neither is a per-nest failure and neither can be
made into one.

**6. The table order means the direct hunt is rare, and that is kept.** fsm.md lists
`UNALERTED → INVESTIGATING` above `UNALERTED → HUNTING`, and evaluates first-match-wins. A touch
strong enough to name a player also raises a hotspot well above `investigate_threshold`, so the
investigate row nearly always wins and the alien spends `min_dwell_s` coming to look before it
commits. That reads as a beat — *something is coming* before *it is coming for me* — so the
order is followed rather than quietly reversed.

**7. `HUNTING` decides once per tick whether it can reach the target, because the spec's tree
cannot be read literally.** fsm.md orders the selector bite → chase → wait → search, and gives
`chase_target` no failure clause for a route that reaches toward the estimate and stops short.
Taken at its word, the `lurk_at_tunnel_mouth` branch is unreachable in exactly the situation it
exists for: whenever there is an estimate to lurk at, chase claims the tick first.

Making chase fail on `PARTIAL` instead looks like the small fix and is not. The two leaves
would then hand the goal back and forth every tick, and `BehaviorGoal` re-issues
unconditionally on a change of owner — which nulls the route and resets navigation's stuck
watchdog every frame, which is the one thing `goal_refresh_m` exists to prevent.

So `HuntingState.refresh` answers it once, before the tree, and the two conditions read
complementary halves of the latch. It is the same shape as deviation 3 and for the same
reason: a question whose answer moves cannot be asked from inside a condition. It costs one
`plan_route` query on the ticks where nobody holds a goal at the estimate, and nothing at all
on the rest — while chase or the lurk is committed there, the live route has already answered.

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
| No file names `submit_evidence` / `submit_disconfirmation` / `reduce_suspicion` / `clear_hotspot` | Belief has three doors and Behavior is not one. An action that lowered a number would resolve hotspots crisply and work visibly better, which is exactly why no behavioural test would flag it. `mark_unreachable` is not an exception to this: it lowers nothing |
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

**Damage, and the one-near-miss-per-encounter latch.** `attack` reads `directive.lethality`,
resolves nothing itself, and emits `attack_landed(target, lethality)` — which is where a hit
animation and a health system attach when either exists. Nothing in `gameplay/` has health
today. The `GRACE → LETHAL` flip after a near-miss lands is the *Director's*, per
`director.md`: it needs session history that Behavior does not have and must not acquire.

**A gait, a noise, or anything else that would make the loud retreat literally loud.** The
split is carried on `action_changed` as `retreat_to_nest_loud`, because that is the animation
channel this module already owns; `NoiseEvent` is world state that only another creature's
hearing consumes, and Behavior may not move the body.

The Director. Spatial Memory, so `roam_anchor` has no producer yet. Any `.tres` config presets —
every field has a working default, so `BehaviorConfig.new()` runs without one.

A `tools/capture_sandbox.tscn`. Perception and navigation each have one and photograph a
`debug_draw`; this module's debug half is a text panel, so there is nothing yet whose pixels
are worth pinning down. Suspicion is in the same position and does without one too.

`prototypes/creature_awareness/` is untouched and still drives its own flat four-state FSM. It is
the natural first customer for this module.
