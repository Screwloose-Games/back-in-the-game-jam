# Suspicion System

## Purpose

The Suspicion system maintains the creature's evolving belief that player activity is occurring in particular parts of the environment.

It sits between **Perception** and **Behavior**.

Perception reports individual observations such as:

* a sound heard near a position,
* a player briefly seen,
* physical contact,
* an area searched without finding anything.

The Suspicion system combines those observations over time into a persistent spatial model of:

* how suspicious the creature currently is,
* where that suspicion is concentrated,
* how certain it is,
* which player may be responsible,
* which areas have been investigated and partially ruled out.

The system does **not** decide what the creature should do.

Its job is to answer:

> **Given everything I have perceived recently, what do I currently believe is worth investigating, and where?**

Behavior then decides what action to take based on that belief.

---

# High-Level Flow

```text
                     WORLD
                       │
                       ▼
                  PERCEPTION
                       │
            positive / negative evidence
                       │
                       ▼
                 SUSPICION
                 SYSTEM
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   Evidence        Hotspots      Player Beliefs
    Memory
        │              │              │
        └──────────────┼──────────────┘
              ┌────────┴────────┐
              ▼                 ▼
          BEHAVIOR          DIRECTOR
        HFSM + trees      (level-scoped)
```

The Suspicion system therefore transforms **momentary perception** into **persistent belief**.

---

# Core Concepts

The system tracks suspicion at three related levels.

## 1. Evidence

Evidence represents an individual perception event.

Examples:

```text
A loud noise occurred near X.

Player 1 was briefly visible near Y.

Something physically contacted the creature at Z.

This region was thoroughly searched and no player was found.
```

Each evidence item has a location, strength, confidence, age, and decay behavior.

Evidence is the raw input into the system.

---

## 2. Suspicion Hotspots

Nearby unresolved evidence is combined into spatial **hotspots**.

A hotspot means:

> There is enough current evidence around this area that the creature considers it worth attention.

For example:

```text
Hotspot A
    position: eastern tunnel
    suspicion: 0.82

Hotspot B
    position: generator chamber
    suspicion: 0.37
```

Multiple hotspots may exist simultaneously.

The creature does not have to forget one suspicious area merely because another one becomes interesting.

Hotspots weaken as:

* supporting evidence ages,
* the creature investigates the area,
* Perception reports that likely locations contain nothing.

---

## 3. Player Suspicion

Evidence that can be associated with a particular player also contributes to a player-specific belief.

For example:

```text
Player 1 suspicion: 0.81
Player 2 suspicion: 0.43
```

This gives the Director useful information for multiplayer target arbitration.

A hotspot does not need to be associated with a known player.

For example:

```text
Hotspot:
    suspicion = 0.74
    likely_source = unknown
```

may later become:

```text
Hotspot:
    suspicion = 0.91
    likely_source = Player 1
    source_confidence = 0.88
```

after additional perception.

---

# State Tracked by the System

The Suspicion system should own the following runtime state.

## Evidence Memory

```gdscript
var evidence: Array[SuspicionEvidence]
```

Each record approximately contains:

> **Implementation note — this type must be renamed when it is built.**
> `SuspicionEvidence` is already declared by the Perception module, at
> `gameplay/creature/perception/observations/suspicion_evidence.gd`, as the *wire*
> DTO Perception emits. Godot's `class_name` table is flat and project-wide, so a
> second declaration is a hard parse error at project scan, not a warning.
>
> Suspicion consumes Perception's `SuspicionEvidence` and wraps it in its own
> internal decaying record — call that `SuspicionEvidenceRecord`. The extra fields
> below (`id`, `evidence_type`, `initial_strength`, `decay_rate`) are exactly the
> ones that belong to the record rather than to the observation: Perception reports
> what it sensed, and persistence is Suspicion's business.

```gdscript
class_name SuspicionEvidenceRecord

var id: int

var evidence_type: EvidenceType
var sense: SenseType

var position: Vector3
var uncertainty_radius: float

var initial_strength: float
var confidence: float

var observed_at: float
var decay_rate: float

var source_player: Node = null
var source_confidence: float = 0.0
```

Evidence remains in memory until its effective contribution falls below a configurable threshold.

---

# Effective Evidence Strength

Evidence decays independently.

Conceptually:

```text
current contribution =
    initial strength
    × confidence
    × age decay
```

This means old evidence gradually becomes less important without needing to abruptly delete it after an arbitrary timeout.

Different evidence types may decay at different rates.

For example:

```text
weak footsteps
    decay quickly

heavy drilling
    decay moderately

direct visual confirmation
    remains meaningful somewhat longer

physical contact
    starts extremely strong but may become stale quickly
```

---

# Hotspot State

```gdscript
class_name SuspicionHotspot

var id: int

var position: Vector3
var radius: float

var suspicion: float
var confidence: float

var last_updated_at: float

var contributing_evidence_ids: Array[int]

var likely_source: Node = null
var source_confidence: float = 0.0

var investigation_progress: float
```

Hotspot position is derived from its current evidence.

Stronger, newer, higher-confidence observations contribute more heavily to the hotspot position.

This allows the hotspot to move as new evidence arrives.

Example:

```text
old sound             new loud sound

    ×----------------------X
               ↓
        hotspot shifts
```

---

# Investigation State

The system must also track which portions of a hotspot have been actively disconfirmed.

This should not be represented as a permanent "searched" flag.

Instead, Perception submits negative observations.

Conceptually:

```gdscript
class_name SuspicionDisconfirmation

var position: Vector3
var radius: float

var strength: float
var observed_at: float

var evidence_mask: int
```

This means:

> The creature adequately checked this area and found no evidence supporting these hypotheses.

Disconfirmation reduces **current local suspicion**, not the historical fact that an earlier event occurred.

For example:

```text
Historical belief:
    "I heard drilling here."

still true.

Current belief:
    "The player is probably still here."

reduced after searching.
```

---

# Spatial Suspicion

A hotspot should conceptually behave as a spatial distribution rather than a single point.

The implementation does not require a dense 3D probability field.

A lightweight representation can use a set of samples inside the hotspot:

```text
          ● .40

     ● .65     ● .32

          ● .88

     ● .54     ● .26
```

Each sample represents unresolved suspicion in that sub-region.

As the creature searches:

```text
          ● .40

     ✓ .08     ● .32

          ✓ .12

     ● .54     ● .26
```

Behavior can then request the strongest unresolved location.

---

# Derived State

Several useful values should be calculated from the underlying evidence rather than stored independently.

## Overall Suspicion

```gdscript
func get_overall_suspicion() -> float
```

Returns a normalized `0..1` value representing the creature's total current concern.

It is a useful summary of concern:

```text
0.00–0.20
    calm

0.20–0.70
    suspicious / investigating

0.70–1.00
    sufficiently suspicious to support hunting
```

It is **not** what opens the investigate transition. Overall suspicion is a scalar with no
location — it can cross a threshold while giving Behavior nowhere to walk. Behavior keys
`UNALERTED → INVESTIGATING` off the strongest hotspot instead, so that entering the state
comes with a destination. Overall suspicion serves the calm-down guard, the Director, and
debug. See `fsm.md`.

Exact thresholds belong to Behavior configuration.

Suspicion should not itself transition the HFSM.

---

## Strongest Hotspot

```gdscript
func get_strongest_hotspot() -> SuspicionHotspot
```

Used primarily by investigation behavior.

---

## Player Suspicion

```gdscript
func get_player_suspicion(player: Node) -> float
```

Used primarily by the Director for target selection.

---

## Suspicion Near Position

```gdscript
func get_suspicion_near(
    position: Vector3,
    radius: float
) -> float
```

Useful for search behavior and deciding whether an area still deserves attention.

---

# Parameters

Recommended parameters should live in:

```text
res://gameplay/creature/suspicion/suspicion_config.gd
```

Prefer a Godot `Resource`.

---

## Evidence Parameters

```gdscript
evidence_min_retention_strength: float
default_uncertainty_radius: float
max_evidence_count: int
```

Per-sense or per-evidence tuning:

```gdscript
hearing_decay_rate: float
vision_decay_rate: float
touch_decay_rate: float

hearing_weight: float
vision_weight: float
touch_weight: float
```

These allow individual senses to have different persistence and influence.

---

## Hotspot Parameters

```gdscript
hotspot_merge_distance: float
hotspot_min_strength: float
hotspot_max_radius: float

hotspot_position_smoothing: float
hotspot_saturation_rate: float
```

Potential topology control:

```gdscript
require_same_spatial_region_for_merge: bool
```

This prevents evidence from opposite sides of a thin cave wall from being incorrectly merged.

---

## Investigation Parameters

```gdscript
disconfirmation_strength_multiplier: float
investigation_min_observation_strength: float

resolved_hotspot_threshold: float
```

Potentially:

```gdscript
searched_area_recovery_rate: float
```

if negative evidence should itself become stale over time.

This would allow the creature to eventually reconsider an area if enough time passes.

---

## Player Association Parameters

```gdscript
source_association_gain: float
source_association_decay: float

player_suspicion_saturation_rate: float
```

These determine how quickly anonymous evidence becomes associated with a particular player.

---

# Public API

The public API should remain relatively narrow.

## Perception → Suspicion

Positive evidence:

```gdscript
func submit_evidence(
    evidence: SuspicionEvidence
) -> void
```

Optional batch version:

```gdscript
func submit_evidence_batch(
    evidence: Array[SuspicionEvidence]
) -> void
```

Negative evidence:

```gdscript
func submit_disconfirmation(
    observation: SuspicionDisconfirmation
) -> void
```

These should be the primary write APIs.

No other subsystem should normally manipulate suspicion directly.

---

# Behavior → Suspicion

Behavior primarily reads.

```gdscript
func get_overall_suspicion() -> float

func get_strongest_hotspot() -> SuspicionHotspot

func get_hotspots() -> Array[SuspicionHotspot]

func get_hotspots_above(
    minimum_suspicion: float
) -> Array[SuspicionHotspot]

func get_suspicion_near(
    position: Vector3,
    radius: float
) -> float

func get_best_unresolved_location(
    hotspot_id: int
) -> Vector3
```

Behavior should not call methods such as:

```text
reduce_suspicion()
clear_hotspot()
mark_investigation_complete()
```

Those would bypass the evidence model.

Instead, Behavior causes the creature to investigate, Perception observes the result, and Suspicion updates accordingly.

---

# Director → Suspicion

The Director reads player-specific information.

```gdscript
func get_player_suspicion(
    player: Node
) -> float

func get_player_source_confidence(
    player: Node
) -> float

func get_best_player_candidate() -> PlayerSuspicionCandidate
```

The Director may then apply:

* target stickiness,
* retarget thresholds,
* multiplayer encounter rules.

The Director should not change suspicion values directly.

---

# Suspicion Events

The system may expose signals for consumers that do not need continuous polling.

Recommended:

```gdscript
signal overall_suspicion_changed(value: float)

signal hotspot_created(hotspot_id: int)

signal hotspot_updated(hotspot_id: int)

signal hotspot_resolved(hotspot_id: int)

signal player_suspicion_changed(
    player: Node,
    suspicion: float
)
```

HFSM transitions should still be owned by Behavior.

For example, Behavior can react to a suspicion update and evaluate its own thresholds.

---

# System Interactions

## Perception

**Dependency:**

```text
Perception → Suspicion
```

Perception is the primary source of evidence.

It reports:

```text
heard something
saw something
touched something
searched an area and found nothing
```

Suspicion converts those observations into persistent beliefs.

---

## Behavior / HFSM

**Dependency:**

```text
Behavior → Suspicion
```

Behavior asks:

```text
How suspicious am I?

Where is the strongest hotspot?

Is this hotspot resolved?

Where should I search next?
```

Behavior decides what to do with those answers.

---

## Director

**Dependency:**

```text
Director → Suspicion
```

The Director reads:

```text
player-specific suspicion
source confidence
overall suspicion
```

and uses that information for stable target selection.

It may ignore the strongest suspicious player temporarily because of target stickiness or other pacing rules.

---

## Navigation

Navigation should generally **not depend directly on Suspicion**.

Instead:

```text
Suspicion
    ↓
Behavior
    ↓
Navigation
```

For example:

```text
Suspicion:
    strongest unresolved location = X

Behavior:
    decide to investigate X

Navigation:
    move_to(X)
```

This preserves navigation as a purely movement-planning system.

---

## Spatial Memory

Suspicion and Spatial Memory should remain sibling systems.

```text
                 Perception
               /            \
              ▼              ▼
       Spatial Memory     Suspicion
              │              │
              ▼              ▼
         Navigation       Behavior
```

Spatial Memory represents:

> What does the creature believe the cave geometry looks like?

Suspicion represents:

> Where does the creature believe meaningful player activity may currently exist?

Suspicion may reference positions and spatial-region IDs, but should not own geometry.

---

# Dependency Graph

```text
                              WORLD
                                │
                                ▼
                           PERCEPTION
                         /            \
                        /              \
                       ▼                ▼
              SPATIAL MEMORY       SUSPICION
                     │             SYSTEM
                     │            /       \
                     ▼           ▼         ▼
                NAVIGATION    BEHAVIOR  DIRECTOR
                     ▲        HFSM+trees    │
                     │           ▲          │
                     │           └──────────┘
                     └───────────┘   directive
```

Expanded:

```text
WORLD
 │
 ▼
PERCEPTION
 │
 ├── GeometryObservation ─────────────► SPATIAL MEMORY
 │                                         │
 │                                         ▼
 │                                     NAVIGATION
 │
 ├── SuspicionEvidence ───────────────► SUSPICION
 │                                         │
 └── DisconfirmationObservation ──────────┘
                                           │
                          ┌────────────────┴──────────────┐
                          │                               │
                          ▼                               ▼
                       BEHAVIOR ◄──────────────────── DIRECTOR
                      HFSM + trees      directive     (level-scoped)
                          │
                          ▼
                     NAVIGATION
```

---

# Example Lifecycle

A player starts drilling.

```text
Perception:
    strong hearing evidence at A
```

Suspicion stores:

```text
Evidence #1
    position A
    strength .90
```

and forms:

```text
Hotspot A
    suspicion .84
```

Behavior sees:

```text
overall suspicion > investigate threshold
```

and enters:

```text
INVESTIGATING
```

Behavior asks:

```text
best unresolved location?
```

Suspicion returns:

```text
A
```

Navigation takes the creature there.

The player has already left.

Perception performs a search and reports:

```text
strong disconfirmation around A
```

Suspicion reduces local unresolved suspicion:

```text
Hotspot A
    .84 → .34
```

Another unsearched portion of the hotspot still contains:

```text
.52 suspicion
```

Behavior asks again:

```text
best unresolved location?
```

and moves there.

Eventually:

```text
Hotspot A < resolved threshold
```

Suspicion emits:

```text
hotspot_resolved(A)
```

If no other meaningful hotspot exists and overall suspicion has decayed sufficiently, Behavior returns the creature to `UNALERTED`.

---

# Design Invariants

The Suspicion system should obey these rules:

**Perception creates evidence.**
Suspicion does not independently inspect the world.

**Evidence has location.**
Suspicion is spatial, not merely a global float.

**Evidence decays independently.**
An old observation becomes less important over time.

**Multiple locations can remain suspicious simultaneously.**

**Nearby evidence can accumulate into hotspots.**

**Investigation creates negative evidence.**
Behavior does not arbitrarily subtract suspicion.

**Searching part of a hotspot only reduces suspicion where the creature actually searched.**

**Historical evidence and current presence are different concepts.**

**Overall suspicion is derived from spatial evidence.**

**Behavior interprets suspicion but does not own it.**

**The Director reads player suspicion but does not manipulate it.**

**Navigation receives destinations from Behavior, not from Suspicion directly.**

The result is a system where suspicion behaves less like an alert meter and more like the creature's continuously changing hypothesis about **where prey-related activity is likely to be happening right now**.
