# Director

## Purpose

The Director answers:

> **What should happen for this to remain a good horror encounter?**

Every other creature system reasons from the alien's own limited knowledge. The Director
does not reason as the alien at all. It watches the encounter from outside and decides
whether the scene needs more pressure or less.

This gives it an authority no other system has, and a matching prohibition:

> **The Director is the only system permitted to know the truth, precisely because it is
> the only system forbidden from acting on the truth.**

It may read real player positions, party state and session tempo. It may never hand the
alien a position, a fact, or a piece of evidence. Everything it emits is *pressure* and
*permission* — how willing the creature should be, how close it should drift, whether a
hunt may begin, whether one must end. The alien still has to find you itself.

That asymmetry is what keeps the Director from becoming a cheat. If it could tell the
creature where you are, the imperfect-knowledge architecture the other five documents
describe would be decoration.

---

## Scope

The Director is **level-scoped** — one per level, not one per creature.

It owns facts no single creature can legitimately own: time since the last encounter
anywhere, the state of every player, the tempo of the session so far. It directs the one
alien today and extends to several without redesign.

Party-wide state (lull, session history) lives on the Director. Per-creature pacing state
— menace, phase, target, timers — lives in an `EncounterTrack`, one per registered
creature.

It lives at `res://gameplay/director/`, not under `creature/`. The type names below are new
and must not collide with anything already in Godot's flat, project-wide `class_name` table
— the same hazard `suspicion.md` documents for `SuspicionEvidence`. `CrawlerCameraDirector`
in `prototypes/tentacle_crawler/` is unrelated and does not collide.

---

## The pacing cycle

The Director derives a phase per creature. This is **not** a second hand-written state
machine — it is a value computed from the accumulators below, and it exists so that debug
output and designer conversation have one word for where the scene is.

```text
   QUIET  ──────►  BUILD  ──────►  PEAK  ──────►  RELIEF  ──┐
   lull rising    menace rising   at ceiling,    cooldown,  │
   alien drifts   encounter is    exit sought    escalation │
   toward party   underway                       gated      │
      ▲                                                     │
      └─────────────────────────────────────────────────────┘
```

The HFSM is the creature's mind — *what do I want to do?* The phase is the scene's arc —
*what should this feel like?* They are not synchronised. The alien can be `HUNTING` while
the Director is in `RELIEF` and wants it to stop; that disagreement is the entire point of
having a Director.

---

## Two accumulators

### Menace — the brake

`menace: 0.0 … 1.0` — how much pressure this encounter has actually **delivered**. It
rises while the creature hunts, from weighted terms:

```text
menace_rate =
      w_time
    + w_proximity  × (1 − clamp(route_distance / menace_range))
    + w_sight      × has_visual_contact
    + w_attack     × attack_pressure       (lunge, block, near-miss)
    + w_lurk       × lurking_at_crevice
    − w_stall      × target_unreachable
```

`route_distance` is path length from Navigation, never Euclidean distance. An alien twelve
metres away through forty metres of tunnel is not delivering twelve metres of dread.

Menace decays at `menace_relief_rate` whenever the creature is not hunting.

### Lull — the throttle

`lull: 0.0 … 1.0` — accumulated dead air. Rises only while the phase is `QUIET` **and**
overall suspicion sits below `calm_suspicion_threshold`; a player being stalked is not
experiencing dead air even if nothing has happened yet. Zeroed on entering `BUILD`.

As lull rises, two outputs move: `escalation_bias` goes positive (the alien acts on weaker
evidence) and `roam_bias` goes positive (it drifts toward the party).

**Lull never fabricates evidence.** The throttle raises the creature's willingness and its
proximity, and nothing else. There is deliberately no lever for injecting a false noise
into Suspicion to bait a player, because it would make noise discipline meaningless — you
could no longer trust that an approaching alien means you made a mistake. That trust is the
mechanic. If a scripted lure is ever wanted it belongs in level scripting, as an actual
world event that Perception observes honestly.

### Two ways to end a hunt

The exit matters as much as the timing.

```text
SATED     menace reached peak_threshold.
          The earned exit. The alien leaves loudly and slowly.
          lull resets fully.

STALLED   hunt exceeded hunt_max_duration with menace still low —
          the alien could not reach you, or you went silent in a crevice.
          The unearned exit. The alien leaves quietly.
          lull resets only partially, so the Director rebuilds sooner.
```

Without this split, a stalemate ends with the same triumphant beat as a real chase, and the
game congratulates a player who did nothing. `disengage_reason` carries the distinction
downstream so Behavior can pick the retreat that reads correctly.

---

## The single output

The Director calls into nothing. Once per tick it publishes one object per creature, and
Behavior reads it.

```gdscript
class_name EncounterDirective

var phase: Phase                  ## QUIET / BUILD / PEAK / RELIEF
var menace: float                 ## 0..1, this creature's encounter
var lull: float                   ## 0..1, party-wide

var target: Node                  ## arbitrated hunt target, may be null
var target_committed_at: float

var permit_hunt: bool             ## hard gate on entering HUNTING
var force_disengage: bool         ## latch, forces HUNTING → RETREATING
var disengage_reason: Reason      ## SATED / STALLED / NONE

var escalation_bias: float        ## −1..+1, soft threshold shift
var lethality: Lethality          ## GRACE / LETHAL
var roam_bias: float              ## −1..+1, toward / away from the party
var roam_anchor: Vector3          ## what "toward" means
```

Behavior pushes one object back up, carrying what only Behavior knows:

```gdscript
class_name EncounterReport

var state: CreatureState          ## current HFSM state
var time_in_state: float
var position: Vector3

var route_distance: float         ## RouteFollower.distance_remaining()
var target_reachable: bool        ## NavRoute.status != UNREACHABLE

var has_visual_contact: bool
var attack_window_open: bool
var lurking_at_crevice: bool
```

One struct up, one struct down, once per tick. The entire coupling is a pure function of
two structs, so it tests without a scene, a body, or a baked graph.

---

## Interface with each system

### Suspicion — read only

The Director reads three things and writes nothing:

```gdscript
suspicion.get_best_player_candidate()   -> PlayerSuspicionCandidate
suspicion.get_player_suspicion(player)  -> float
suspicion.get_overall_suspicion()       -> float
```

All three already ship in `gameplay/creature/suspicion/creature_suspicion.gd`.

**Target arbitration** converts candidate scores into a stable decision. The current target
holds unless a rival exceeds it by `retarget_margin` *and* the current target has been held
for at least `min_target_commit_s`:

```text
holding Player 1:   P1 .72   P2 .76   margin .04  →  stay on Player 1
holding Player 1:   P1 .55   P2 .94   margin .39  →  switch to Player 2
```

Stickiness lives here rather than in Suspicion because Suspicion's job is to be accurate,
and accuracy oscillates. Committing to a slightly-wrong target is a Director decision.

**The Director never damps suspicion.** After a forced disengagement the creature still
fully believes you are there — the cooldown works by shifting Behavior's thresholds, not by
editing belief. The difference is legible in play: an alien that has lost interest reads as
a predator making a choice, while an alien that has lost its memory reads as a bug.

### Behavior / HFSM — the only bidirectional link

| Directive field | Gates | Effect |
|---|---|---|
| `escalation_bias` | `UNALERTED → INVESTIGATING`, `INVESTIGATING → HUNTING` | Shifts both thresholds by `bias × bias_span`. Negative during `RELIEF`, positive as lull grows. |
| `permit_hunt` | `→ HUNTING` (any source) | Hard veto. False throughout `RELIEF`. |
| `force_disengage` | `HUNTING → RETREATING` | Latch. Overrides any suspicion level. |
| `disengage_reason` | retreat style | `SATED` → leave loudly; `STALLED` → leave quietly. |
| `target` | `chase_target` | The creature chases this. If null, Behavior falls back to hotspot search. |
| `lethality` | `attack` | `GRACE` resolves as a near-miss. |
| `roam_bias`, `roam_anchor` | nest selection | One extra weighting term. |

`force_disengage` is **a latch the HFSM consumes at its next transition check**, never a
mid-action interrupt — a leap, a lunge or an attack animation is allowed to finish. A
Director that could sever an action mid-frame would produce visible glitching, and the one
frame it saves is worth nothing.

`RETREATING → UNALERTED` stays entirely Behavior's, on separation and elapsed time. The
Director asks for a retreat; it does not conduct one.

The authoritative list of states and transitions is `fsm.md`. This table names the coupling
only; it does not redefine the guards.

### Navigation — read only, through Behavior

The Director needs two metrics: remaining route distance to the target, and whether the
target is reachable at all.

Both values exist — `RouteFollower.distance_remaining(position)` and
`NavRoute.status == UNREACHABLE` — but **neither is exposed on `CreatureNavigation`'s
public surface today**. Rather than adding an accessor so that a level-scoped Director can
reach into one creature's route follower, both ride on `EncounterReport`; Behavior already
holds the route. The Director never issues a destination.

### Perception — no link, deliberately

The Director does not touch hearing range, vision cone, sense weights or any other sensing
parameter. Not "should not" — the interface does not exist. If the Director could deafen
the alien to relieve pressure, noise discipline would stop being a real mechanic; the
player's only feedback loop for a mistake is that the alien heard it. Difficulty lives in
`perception_config.gd`. Pacing lives here.

Note the near-miss: `CreaturePerception.set_alertness_context()` does exist, and vision is
designed to sharpen once the creature is already suspicious. **Behavior** sets that, from
its own HFSM state. That is the creature's attention responding to its own belief, not the
Director reaching in.

### Spatial Memory, Movement — no link, in either direction

---

## Kill grace

```gdscript
enum Lethality { GRACE, LETHAL }
```

`GRACE` when any of:

* no encounter this session has yet reached `PEAK` — the first one teaches, it does not kill
* the target respawned within `respawn_grace_s`
* menace is below `lethal_menace_threshold` — the encounter has not earned its payoff

Under `GRACE` the attack action resolves as a near-miss: it connects visually, staggers,
and the alien overshoots. Behavior owns the animation and the damage; the Director owns
only the flag.

**One near-miss per encounter.** After a grace hit lands, lethality flips to `LETHAL` for
the remainder of that encounter regardless of any condition above. Without this rule a
player eventually notices they are safe, and a horror game that the player knows cannot
kill them has no remaining mechanism.

---

## Ambient placement bias

`behavior.md` §24 already weights nest choice by distance and recent use. The Director adds
one term:

```text
nest_score = distance_term + recency_term + roam_bias × proximity_to(roam_anchor)
```

`roam_anchor` is derived from real player positions — the Director is allowed to know them.
Positive bias during a long lull drifts the alien toward the party; negative bias during
`RELIEF` clears it out, so a retreat actually creates space.

The anchor **weights a list of nests the creature already knows**. It is never a navigation
destination, and it never creates a nest. The alien's movement stays explicable in terms of
its own knowledge; only the odds changed.

---

## Configuration

`director/director_config.gd`, a `Resource`, in the house style of the shipped
`perception_config.gd` and `suspicion_config.gd`: a `const DEFAULT_*` above each `@export`,
`@export_group` sections, `@export_range` with units and a `##` per field, usable from a
bare `.new()`, and `invariant_failures() -> PackedStringArray`.

```gdscript
# Menace
w_time, w_proximity, w_sight, w_attack, w_lurk, w_stall
menace_range_m, menace_relief_rate, peak_threshold, hunt_max_duration_s

# Escalation gate
bias_span, cooldown_s, cooldown_separation_m

# Lull
lull_full_s, calm_suspicion_threshold, max_roam_bias, stalled_lull_retention

# Target arbitration
retarget_margin, min_target_commit_s

# Lethality
lethal_menace_threshold, respawn_grace_s, first_encounter_grace: bool
```

## Signals and debug

```gdscript
signal encounter_phase_changed(creature: Node, from: Phase, to: Phase)
signal target_changed(creature: Node, from: Node, to: Node)
signal disengage_requested(creature: Node, reason: Reason)
signal lethality_changed(creature: Node, lethality: Lethality)
```

Every override must be attributable. The debug panel shows menace and lull as bars, the
phase, the current target with its margin over the runner-up, and the reason string for
whatever the Director is currently forcing. "The alien left" is not a bug report; "the alien
left, SATED, menace 1.00 at t+47" is.

---

## Worked encounter

```text
t+0    QUIET     lull .6 after two quiet minutes → bias +.3, roam +.6
                 alien drifts to a nest nearer the party

t+12   player drills. Hotspot forms, overall .34, which clears the
       shifted investigate threshold → INVESTIGATING. BUILD, lull zeroed.

t+31   player seen, candidate .81. permit_hunt true, target = Player 1
       → HUNTING. lethality GRACE, first encounter of the session.

t+44   menace climbing on closing route distance and held visual contact.
       Attack window → near-miss, stagger, overshoot.
       lethality flips to LETHAL for the rest of this encounter.

t+52   player reaches a crevice, goes silent. menace .87 on lurk pressure.

t+58   menace 1.00 → PEAK. force_disengage, reason SATED. The HFSM
       consumes the latch after the lurk action completes → RETREATING.
       RELIEF: permit_hunt false, bias −.4, roam −.8. The alien leaves
       loudly and heads away from the party.

t+71   separation met → UNALERTED
t+79   cooldown expires → QUIET, lull begins rising again
```

No system contains this script. Each value moved for its own reason.

---

## Design invariants

**The Director never writes belief.** Suspicion has three doors — evidence,
disconfirmation, the clock — and the Director is not one of them.

**The Director never issues navigation destinations.** Behavior owns goals.

**The Director never adjusts perception.** Sensing is difficulty, not pacing.

**The Director never transitions the HFSM.** It publishes a directive; Behavior honours it,
at a moment of Behavior's choosing.

**The Director may know the truth, and may only emit bias.** Real player positions may
inform `roam_anchor` and target arbitration. They may never reach the creature as a
position it navigates to.

**Exactly one directive is in effect per creature per tick.** No mid-frame revisions.

**Every override carries a named reason**, visible in debug and in the signal.

The result is a system that shapes the *rhythm* of the encounter without ever lying to the
creature about the world — so the alien remains a predator working from what it actually
knows, while the encounter still has a shape somebody designed.
