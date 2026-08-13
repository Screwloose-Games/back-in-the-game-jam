The Perception system is the alien’s controlled interface to the authoritative game world. It converts raw world state into observations that other AI systems can reason about, without allowing those systems to query reality directly.

# Perception System

## 1. Purpose

The Perception system answers:

> **What can the alien observe right now?**

It is responsible for converting actual game-world state into imperfect, localized observations.

The Perception system is intentionally different from both memory and decision-making.

It does not answer:

* What does the alien remember?
* How suspicious should the alien be?
* Where should the alien go?
* Should the alien hunt?
* What does the cave actually look like everywhere?

Instead, it answers questions such as:

* Did I hear something?
* Approximately where did it come from?
* How strong was the sound?
* Can I currently see this player?
* Did I physically contact something?
* What geometry can I currently perceive around me?
* Did I search this region and fail to find evidence of the player?

Perception produces **observations**. Other systems determine what those observations mean.

---

# 2. Architectural Role

Perception sits directly between the authoritative game world and the alien's internal models.

```text
                        ACTUAL WORLD
                players / terrain / physics
                        / sound events
                              │
                              ▼
                       ┌────────────┐
                       │ PERCEPTION │
                       └─────┬──────┘
                             │
                   observations only
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
        SUSPICION                     SPATIAL MEMORY
   activity / player belief           geometry belief
```

The two primary outputs are:

### Suspicion evidence

Information related to possible player activity.

Examples:

```text
sound near position X
player briefly visible at Y
physical contact at Z
region searched without finding target
```

This flows to the **Suspicion system**.

### Geometry observations

Information about perceived physical space.

Examples:

```text
this region is open
this region is solid
this passage has enough clearance
remembered wall is actually gone
remembered passage is now blocked
```

This flows to **Spatial Memory**.

---

# 3. Core Architectural Principle

The Perception system should be the normal boundary across which the alien learns facts about the current world.

For example, if the player destroys a wall:

```text
Voxel Terrain
    wall removed
```

this must **not** directly update:

```text
Spatial Memory
Navigation
Behavior
Suspicion
```

The terrain change only alters reality.

The alien learns about it later through Perception.

Similarly, player position should not normally be read directly by Behavior.

Instead:

```text
Player position
      │
      ▼
Vision / Hearing / Touch
      │
      ▼
Perception observation
      │
      ▼
Suspicion
```

This is what allows the alien to possess imperfect information.

---

# 4. Perception Architecture

Recommended internal structure:

```text
CreaturePerception
│
├── Hearing
│
├── Vision
│
├── Touch
│
├── GeometryPerception
│
└── ObservationDispatcher
```

File organization:

```text
res://gameplay/creature/perception/
├── creature_perception.gd
├── hearing.gd
├── vision.gd
├── touch.gd
├── geometry_perception.gd
│
├── observations/
│   ├── suspicion_evidence.gd
│   ├── disconfirmation_observation.gd
│   └── geometry_observation.gd
│
└── perception_config.gd
```

`CreaturePerception` is the facade used by the rest of the alien AI.

The individual senses should remain independently replaceable.

---

# 5. CreaturePerception

`creature_perception.gd`

This is the coordinating component.

It owns or references:

```gdscript
var hearing: Hearing
var vision: Vision
var touch: Touch
var geometry_perception: GeometryPerception
```

Its responsibilities are:

* update senses,
* receive externally emitted sensory events,
* normalize observations,
* route activity observations to Suspicion,
* route geometry observations to Spatial Memory,
* handle explicit local observation requests.

It should contain very little sensory logic itself.

Conceptually:

```text
CreaturePerception
       │
       ├── Hearing evaluates noises
       ├── Vision evaluates visibility
       ├── Touch evaluates contact
       └── GeometryPerception evaluates space
```

---

# 6. Perception Is Mostly Event-Driven

Not every sense needs to poll the environment continuously.

Different senses should use different acquisition mechanisms.

## Hearing

Primarily event-driven.

```text
NoiseEvent
    ↓
Hearing
    ↓
SuspicionEvidence
```

## Touch

Primarily collision/event-driven.

```text
Physics contact
    ↓
Touch
    ↓
SuspicionEvidence
```

## Vision

Usually sampled periodically.

```text
Candidate players
    ↓
cone / distance / LOS test
    ↓
SuspicionEvidence
```

## Geometry Perception

Usually sampled locally or explicitly requested.

```text
nearby geometry
or
navigation validation request
        ↓
GeometryPerception
        ↓
GeometryObservation
```

This avoids turning Perception into one large expensive world scan every frame.

---

# 7. Observation Types

The rest of the AI should consume structured observations rather than raw physics results.

There are three primary observation types.

---

# 8. SuspicionEvidence

Used for positive evidence of meaningful activity.

Conceptually:

```gdscript
class_name SuspicionEvidence

enum Sense {
    HEARING,
    VISION,
    TOUCH
}

var sense: Sense

var position: Vector3
var uncertainty_radius: float

var strength: float
var confidence: float

var observed_at: float

var source_player: Node = null
var source_confidence: float = 0.0

var category: StringName
```

Example:

```text
Hearing evidence

position:
    (31, -4, 82)

uncertainty:
    4.5m

strength:
    0.71

confidence:
    0.62

source:
    unknown
```

Or:

```text
Vision evidence

position:
    Player 1 position

uncertainty:
    0.25m

strength:
    0.96

confidence:
    0.98

source:
    Player 1
```

Perception supplies the observation.

Suspicion determines its persistence and contribution.

---

# 9. DisconfirmationObservation

Used when Perception successfully examines an area but fails to find expected supporting evidence.

Conceptually:

```gdscript
class_name DisconfirmationObservation

var position: Vector3
var radius: float

var strength: float
var observed_at: float

var senses_checked: int
```

This represents:

> "I meaningfully checked this area and found no evidence supporting the current hypothesis."

For example:

```text
Creature thoroughly examines dead end.

position:
    dead-end center

radius:
    5m

strength:
    .90
```

Suspicion can then substantially reduce unresolved suspicion there.

A brief glance might instead produce:

```text
strength:
    .20
```

---

# 10. GeometryObservation

Used to update Spatial Memory.

Conceptually:

```gdscript
class_name GeometryObservation

enum ObservationType {
    FREE,
    SOLID,
    CLEARANCE
}

var type: ObservationType

var region: AABB
var position: Vector3

var clearance: float

var confidence: float
var observed_at: float
```

The representation can later become voxel- or chunk-oriented.

The semantic API should remain:

> Perception observed something about physical space.

---

# 11. Hearing Architecture

`hearing.gd`

Hearing receives `NoiseEvent`s from the world.

Noise emitters should produce something approximately like:

```gdscript
class_name NoiseEvent

var position: Vector3
var loudness: float

var source: Node
var source_player: Node

var category: StringName
```

Hearing processes:

```text
raw loudness
    ×
distance attenuation
    ×
obstruction attenuation
    ×
creature hearing sensitivity
```

to produce perceived strength.

Conceptually:

```gdscript
func perceive_noise(event: NoiseEvent) -> SuspicionEvidence:
    ...
```

The result includes spatial uncertainty.

A weaker or more distant sound should normally produce a less certain location.

For example:

```text
Nearby drilling:

      ×
     1m uncertainty


Distant footsteps:

   ┌──────────────┐
   │ possible     │
   │ origin area  │
   └──────────────┘
```

This allows Suspicion to reason about areas rather than receiving magically precise coordinates from hearing.

---

# 12. Hearing API

Primary external input:

```gdscript
func on_noise(event: NoiseEvent) -> void
```

Internal evaluation may expose:

```gdscript
func calculate_received_strength(
    event: NoiseEvent
) -> float
```

and:

```gdscript
func estimate_uncertainty(
    event: NoiseEvent,
    received_strength: float
) -> float
```

Its output goes through `CreaturePerception`, not directly to Behavior.

---

# 13. Vision Architecture

`vision.gd`

Vision evaluates known potential targets rather than searching every object in the world.

It may use:

* distance,
* cone angle,
* line-of-sight shapecast/raycast,
* lighting or visibility modifiers,
* creature alertness gating.

Example:

```text
potential player
      ↓
within range?
      ↓
within cone?
      ↓
line of sight?
      ↓
visibility modifier
      ↓
Vision evidence
```

Vision can be disabled entirely.

```gdscript
vision.enabled = false
```

No other AI subsystem should require changes when vision is disabled.

---

# 14. Suspicion May Influence Perception Sensitivity

Although Perception writes observations into Suspicion, Suspicion may also influence **how much attention the creature is currently paying**.

This creates a deliberate narrow feedback relationship:

```text
Perception ─────► Suspicion
                    │
                    │ alertness context
                    ▼
               Perception
```

For example:

```text
low suspicion:
    vision disabled
    lower scan frequency

high suspicion:
    vision enabled
    increased scan frequency
    geometry/search scan more thorough
```

This should be implemented as **read-only context**, not Suspicion controlling individual perception results.

For example:

```gdscript
func set_alertness_context(value: float)
```

or preferably:

```gdscript
var alertness := suspicion.get_overall_suspicion()
```

The Perception system can then use the value to choose sensing effort.

The important distinction is:

> Suspicion may affect **how the alien looks**, but not **what the world contains**.

---

# 15. Touch Architecture

`touch.gd`

Touch processes immediate physical interactions.

Sources include:

```text
body collision
Area3D overlap
attack/contact volume
very-short-range proximity sensing
```

Touch normally produces:

```text
high strength
high confidence
very low uncertainty
```

For example:

```gdscript
SuspicionEvidence.new(
    Sense.TOUCH,
    player.global_position,
    uncertainty_radius = 0.1,
    strength = 1.0,
    confidence = 1.0
)
```

Touch may also help identify:

```text
player recently entered crevice
```

but the behavioral inference:

> "The player is probably hiding there."

belongs to Suspicion/Behavior, not Touch.

---

# 16. Geometry Perception Architecture

`geometry_perception.gd`

Geometry Perception is separate from Vision.

The alien may be visually poor at detecting players while still being capable of moving through caves and perceiving nearby physical structure.

Geometry sensing may fictionally represent:

* echolocation,
* vibration sensing,
* tendrils,
* close-range spatial sensing,
* physical probing.

The implementation can therefore use physics queries without implying conventional vision.

---

# 17. Passive Geometry Observation

While moving, Geometry Perception may periodically sample nearby space.

Example:

```text
           perceived area

        ┌───────────────┐
        │               │
        │       A       │
        │     alien     │
        │               │
        └───────────────┘
```

It updates only the geometry the alien could plausibly perceive.

The output is submitted to Spatial Memory.

---

# 18. Requested Geometry Validation

Navigation can explicitly ask Perception to examine a suspicious region.

This happens when physical reality contradicts remembered geometry.

For example:

```text
Navigation:
    "There should be a tunnel here."

Movement:
    blocked.

Navigation:
    request validation.
```

API:

```gdscript
func request_geometry_scan(
    region: AABB,
    reason: GeometryScanReason
) -> void
```

Example reasons:

```gdscript
enum GeometryScanReason {
    PASSIVE,
    PATH_BLOCKED,
    EXPECTED_WALL_MISSING,
    CLEARANCE_MISMATCH,
    SEARCH_BEHAVIOR
}
```

Perception then observes the region and publishes `GeometryObservation`s.

Navigation never says:

```text
"The geometry is now SOLID."
```

It only says:

```text
"My expectation seems incorrect; inspect this region."
```

---

# 19. Search Observation

Behavior may also ask Perception to deliberately inspect an area during investigation.

For example:

```text
Behavior:
    Search this section of hotspot A.
```

This is different from telling Suspicion:

```text
reduce hotspot A.
```

Instead:

```text
Behavior
    ↓
request deliberate search
    ↓
Perception
    ↓
positive observations?
    │
 ┌──┴───┐
yes     no
 │       │
 ▼       ▼
evidence disconfirmation
 │       │
 └───┬───┘
     ▼
 Suspicion
```

Potential API:

```gdscript
func request_activity_scan(
    region: AABB,
    thoroughness: float
) -> void
```

The resulting observations depend on what Perception actually finds.

---

# 20. Perception → Suspicion API

Perception writes to Suspicion through two operations.

Positive evidence:

```gdscript
suspicion.submit_evidence(
    evidence: SuspicionEvidence
)
```

Negative evidence:

```gdscript
suspicion.submit_disconfirmation(
    observation: DisconfirmationObservation
)
```

That is the complete required write API between these systems.

Perception should not call methods like:

```text
increase_suspicion()
start_hunting()
set_hotspot()
clear_hotspot()
set_target()
```

Those would couple sensing to interpretation.

---

# 21. Perception → Spatial Memory API

Geometry observations are submitted through:

```gdscript
spatial_memory.observe_geometry(
    observation: GeometryObservation
)
```

Potentially batched:

```gdscript
spatial_memory.observe_geometry_batch(
    observations: Array[GeometryObservation]
)
```

Perception does not modify navigation nodes or spatial-memory cells directly.

---

# 22. Navigation → Perception API

Navigation has one narrow interaction with Perception:

```gdscript
perception.request_geometry_scan(
    region,
    reason
)
```

This supports stale geometry discovery.

Navigation does not otherwise depend on Hearing, Vision, Touch, or player perception.

---

# 23. Behavior → Perception API

Behavior may request deliberate sensing actions.

Recommended high-level API:

```gdscript
func request_activity_scan(
    region: AABB,
    thoroughness: float
) -> void
```

and potentially:

```gdscript
func is_activity_scan_complete() -> bool
```

For example, the Investigating behavior tree can execute:

```text
MoveToSearchPoint
       ↓
SearchArea
       ↓
request_activity_scan(...)
       ↓
wait for scan
       ↓
Suspicion receives result
```

Behavior does not need to know which rays, overlaps, hearing checks, or other physics operations Perception used.

---

# 24. Public Perception Interface

A useful facade might look roughly like:

```gdscript
class_name CreaturePerception

# External sensory event
func receive_noise(event: NoiseEvent) -> void

# Explicit behavior request
func request_activity_scan(
    region: AABB,
    thoroughness: float
) -> void

# Navigation validation request
func request_geometry_scan(
    region: AABB,
    reason: GeometryScanReason
) -> void

# Optional status
func is_activity_scan_active() -> bool

func is_geometry_scan_active() -> bool
```

Most output does not need to be pulled through getters.

Perception publishes observations directly into the corresponding memory systems.

---

# 25. Internal Observation Dispatch

It can be useful to have one internal dispatch point inside `CreaturePerception`.

Conceptually:

```gdscript
func _submit_activity_evidence(
    evidence: SuspicionEvidence
) -> void:
    suspicion.submit_evidence(evidence)


func _submit_disconfirmation(
    observation: DisconfirmationObservation
) -> void:
    suspicion.submit_disconfirmation(observation)


func _submit_geometry(
    observation: GeometryObservation
) -> void:
    spatial_memory.observe_geometry(observation)
```

Individual senses therefore do not need direct references to Suspicion or Spatial Memory.

Dependency becomes:

```text
Hearing ──┐
Vision ───┤
Touch ────┼──► CreaturePerception
Geometry ─┘            │
                       ├──► Suspicion
                       └──► Spatial Memory
```

This provides a cleaner ownership boundary.

---

# 26. Recommended Dependency Graph

```text
                         WORLD
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
     noises            players          terrain
        │                 │                 │
        ▼                 ▼                 ▼
     HEARING           VISION       GEOMETRY PERCEPTION
        │                 │                 │
        │               TOUCH               │
        │                 │                 │
        └────────┬────────┴─────────┬───────┘
                 │                  │
                 ▼                  ▼
             activity           geometry
            observations       observations
                 │                  │
                 ▼                  ▼
          CREATURE PERCEPTION FACADE
                 │                  │
           ┌─────┘                  └─────┐
           ▼                              ▼
      SUSPICION                    SPATIAL MEMORY
           │                              │
           ▼                              ▼
       BEHAVIOR                       NAVIGATION
```

Request paths point back into Perception:

```text
BEHAVIOR
   │
   │ deliberate search request
   ▼
PERCEPTION


NAVIGATION
   │
   │ geometry validation request
   ▼
PERCEPTION
```

These are requests to **observe**, not commands specifying what Perception should conclude.

---

# 27. Perception Configuration

Recommended:

```text
res://gameplay/creature/perception/perception_config.gd
```

as a Godot `Resource`.

Suggested categories:

## Hearing

```gdscript
hearing_enabled: bool

hearing_max_range: float
hearing_sensitivity: float

hearing_distance_falloff: Curve
hearing_obstruction_multiplier: float

hearing_min_detectable_strength: float

hearing_min_uncertainty: float
hearing_max_uncertainty: float
```

---

## Vision

```gdscript
vision_enabled: bool

vision_range: float
vision_angle: float

vision_activation_suspicion: float

vision_scan_interval_calm: float
vision_scan_interval_alert: float

vision_min_visibility: float
```

---

## Touch

```gdscript
touch_enabled: bool

touch_strength: float
proximity_detection_range: float
```

---

## Geometry

```gdscript
geometry_perception_enabled: bool

geometry_passive_scan_radius: float
geometry_passive_scan_interval: float

geometry_validation_radius: float
geometry_clearance_resolution: float
```

---

## Search

```gdscript
search_scan_radius: float

search_scan_duration_min: float
search_scan_duration_max: float

search_disconfirmation_strength: float
```

---

# 28. State Owned by Perception

Perception should maintain very little long-term state.

It may track transient operational state such as:

```gdscript
last_vision_scan_time
last_geometry_scan_time

current_activity_scan
current_geometry_scan

nearby_player_candidates
```

It should **not** maintain:

```text
last known player position
suspicion value
hotspots
player suspicion
remembered walls
remembered tunnels
current navigation target
hunt state
```

Those belong elsewhere.

This is an important architectural rule.

Perception represents the alien's **present senses**, not its memory.

---

# 29. Why Perception Should Be Thin

Keeping Perception thin creates several useful properties.

### Senses are replaceable

Hearing can be substantially redesigned without rewriting Behavior.

### The creature can forget

Because observations are copied into Suspicion or Spatial Memory, Perception does not need to remember everything forever.

### Difficulty tuning remains clean

You can make the alien perceptually stronger by changing:

```text
hearing sensitivity
vision range
scan frequency
uncertainty
```

without altering decision logic.

### Debugging becomes understandable

You can distinguish:

```text
The alien didn't hear me.

versus

The alien heard me but didn't care enough.

versus

The alien was suspicious but chose another hotspot.

versus

The alien wanted to reach me but remembered the geometry incorrectly.
```

Those are different failures in different systems.

---

# 30. Debug Requirements

The Perception debugger should visualize what the alien is sensing, independent of what it believes.

Recommended visualizations:

```text
hearing event location
received hearing strength
hearing uncertainty radius

vision cone
vision ray / visibility result

touch/proximity volumes

geometry scan region

activity search region

generated evidence observations
generated disconfirmation observations
```

For example:

```text
HEARING

Event:
    Drill

Raw loudness:
    1.00

Distance:
    23.2m

Received:
    .61

Estimated uncertainty:
    4.8m

Submitted:
    SuspicionEvidence #143
```

This makes it possible to debug Perception independently of Suspicion.

---

# 31. Architectural Invariants

The Perception system should follow these rules:

**Perception observes reality but does not remember it long-term.**

**Perception produces observations, not behavioral commands.**

**Perception never transitions the HFSM.**

**Perception never selects a target.**

**Perception never directly changes suspicion values.**

**Perception never directly changes navigation paths.**

**Perception is the normal writer into Suspicion and Spatial Memory.**

**Terrain destruction does not directly update alien knowledge.**

**Behavior may request a search, but Perception determines what that search discovers.**

**Navigation may request geometry validation, but Perception determines what geometry is observed.**

**Individual senses report uncertainty rather than pretending all perception is exact.**

The system can therefore be summarized as:

```text
WORLD
   ↓
PERCEPTION
"What can I observe right now?"
   ↓
OBSERVATIONS
   ├──► SUSPICION
   │    "What does this imply about player activity?"
   │
   └──► SPATIAL MEMORY
        "What does this imply about the geometry?"
```

Perception establishes the boundary between **what actually exists in the game world** and **what the alien is allowed to know about it**. That boundary is what makes uncertainty, searching, misdirection, stale geometry, and surprise possible throughout the rest of the AI architecture.
