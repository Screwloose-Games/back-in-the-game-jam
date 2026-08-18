The Spatial Memory system is the alien’s persistent internal model of cave geometry. It deliberately differs from the authoritative terrain so the alien can be wrong, surprised, and forced to learn.

# Spatial Memory System

## 1. Purpose

The Spatial Memory system answers:

> **What does the alien currently believe the environment looks like?**

It stores the alien's remembered understanding of 3D geometry independently of the actual voxel terrain.

This separation is required because the terrain can change while the alien is elsewhere.

For example:

```text
ACTUAL WORLD

██████        ██████
       opening


ALIEN MEMORY

████████████████████
          wall
```

The player has destroyed the wall, but the alien has not observed that change.

From the alien's perspective, the wall still exists.

The Spatial Memory system therefore provides a persistent but potentially stale world model that Navigation uses for planning.

---

# 2. Architectural Role

Spatial Memory sits between **Perception** and **Navigation**.

```text
                 ACTUAL TERRAIN
                       │
                       │ local observation
                       ▼
                  PERCEPTION
                       │
                GeometryObservation
                       │
                       ▼
               ┌────────────────┐
               │ SPATIAL MEMORY │
               └───────┬────────┘
                       │
                remembered geometry
                       │
                       ▼
                  NAVIGATION
                       │
                       ▼
                    MOVEMENT
                       │
                       ▼
                 ACTUAL TERRAIN
```

Perception is the primary writer.

Navigation is the primary reader.

The central rule is:

> **Navigation plans against Spatial Memory, not against authoritative voxel geometry.**

Immediate movement may still use real collision physics so the creature cannot physically walk through a wall that its memory says is open.

---

# 3. Responsibilities

Spatial Memory owns:

* remembered occupancy,
* remembered traversable space,
* remembered creature clearance,
* unknown space,
* observation confidence,
* observation age,
* geometry revisions,
* localized change notifications,
* navigation-oriented snapshots or queries.

Spatial Memory does not own:

* live voxel terrain,
* geometry perception,
* pathfinding,
* creature movement,
* suspicion,
* player evidence,
* behavior decisions.

---

# 4. Architecture

Recommended internal structure:

```text
CreatureSpatialMemory
│
├── GeometryMemoryStore
│
│   └── remembered spatial cells/chunks
│
├── GeometryObservationIntegrator
│
│   └── reconciles observations with memory
│
├── SpatialQueryInterface
│
│   └── read API for Navigation
│
└── RevisionTracker
    └── tracks changed regions
```

Recommended files:

```text
res://gameplay/creature/spatial_memory/
├── creature_spatial_memory.gd
├── geometry_memory_store.gd
├── geometry_memory_cell.gd
├── geometry_observation.gd
├── spatial_memory_region.gd
├── spatial_memory_snapshot.gd
└── spatial_memory_config.gd
```

For a smaller implementation, `geometry_memory_store.gd` and the observation integration logic can initially live inside `creature_spatial_memory.gd`.

The interface boundaries should still remain explicit.

---

# 5. Memory Representation

The exact storage representation should be chosen based on the voxel system, but the conceptual model should support at least:

```gdscript
enum OccupancyState {
    UNKNOWN,
    FREE,
    SOLID
}
```

Each remembered spatial element should contain approximately:

```gdscript
class_name GeometryMemoryCell

var occupancy: OccupancyState

var clearance: float
var confidence: float

var last_observed_at: float

var revision: int
```

A cell does not necessarily need to correspond one-to-one with a gameplay voxel.

Spatial Memory may use a lower-resolution representation optimized for creature navigation.

For example:

```text
Game terrain:
    10 cm voxels

Creature memory:
    20–30 cm spatial cells
```

The creature only needs enough fidelity to reason about where its body can travel.

---

# 6. Unknown Space

`UNKNOWN` must remain distinct from both free and solid space.

```text
FREE
    "I remember that I can probably occupy this space."

SOLID
    "I remember that something blocks this space."

UNKNOWN
    "I do not know what is here."
```

This distinction makes it possible to tune how adventurous the creature is.

For example:

```text
Conservative navigation:
    UNKNOWN treated as blocked.

Exploratory navigation:
    UNKNOWN may be entered with additional path cost.

Very confident territorial creature:
    only uses known routes while hunting.
```

For the initial implementation, treating `UNKNOWN` as non-traversable is the simplest and most predictable rule.

---

# 7. Clearance Memory

Occupancy alone is not sufficient.

The alien may fit through one passage but not another.

Spatial Memory should therefore maintain approximate **clearance**.

Conceptually:

```text
clearance(position)
    =
distance from remembered free-space point
to nearest remembered obstruction
```

Navigation can ask:

```gdscript
is_known_traversable(
    position,
    required_clearance
)
```

rather than merely:

```gdscript
is_free(position)
```

This keeps knowledge of creature size and valid movement corridors explicit.

---

# 8. Geometry Observations

Spatial Memory is updated through:

```text
GeometryObservation
```

produced by Perception.

> **Implementation note — do not re-declare this type.**
> `GeometryObservation` already exists, at
> `gameplay/creature/perception/observations/geometry_observation.gd`, and is what
> `CreaturePerception.geometry_observed` emits. Godot's `class_name` table is flat
> and project-wide, so declaring it a second time here is a hard parse error at
> project scan rather than a warning. Spatial Memory consumes Perception's type.
>
> The shipped type matches the fields below. Note that Perception emits observations
> in **batches** (one signal per scan), which is the `observe_geometry_batch` form
> section 21 of `perception.md` anticipates.

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

The implementation may later use chunk coordinates, voxel masks, or compressed regions instead of individual records.

The semantic contract remains:

> A GeometryObservation describes what the alien has just perceived about physical space.

---

# 9. Perception → Spatial Memory API

The primary write API should be small.

Single observation:

```gdscript
func observe_geometry(
    observation: GeometryObservation
) -> void
```

Batch version:

```gdscript
func observe_geometry_batch(
    observations: Array[GeometryObservation]
) -> void
```

The batch form will probably be preferable for geometry scans.

For example:

```gdscript
spatial_memory.observe_geometry_batch(
    geometry_perception.scan_region(region)
)
```

Perception should not manipulate memory cells directly.

---

# 10. Observation Integration

When an observation arrives, Spatial Memory reconciles it with existing knowledge.

For example:

```text
Memory:
    SOLID

Observation:
    FREE

Result:
    FREE
    revision increments
```

Or:

```text
Memory:
    UNKNOWN

Observation:
    SOLID

Result:
    SOLID
```

The basic operation is:

```text
observation
    ↓
determine affected memory cells
    ↓
compare with remembered state
    ↓
update occupancy / clearance / confidence
    ↓
mark changed region
    ↓
increment revision
    ↓
notify interested readers
```

---

# 11. Contradictory Observations

An observation may contradict existing memory.

This is expected.

It is not an error condition.

For example:

```text
remembered:
    wall

observed:
    empty tunnel
```

means the player's destruction has finally been discovered.

Likewise:

```text
remembered:
    open passage

observed:
    obstruction
```

means the remembered route is no longer valid.

The system should strongly prefer recent high-confidence observations over stale memory.

---

# 12. Confidence

Each remembered region may carry confidence.

For example:

```text
Recently physically traversed tunnel:
    confidence = 1.0

Observed indirectly at edge of perception:
    confidence = 0.6

Very old remembered space:
    confidence = 0.4
```

Confidence can eventually influence Navigation.

For example:

```text
high confidence route:
    normal cost

low confidence route:
    slightly increased cost
```

This is optional for the initial implementation.

The API should preserve the possibility.

---

# 13. Observation Age

Memory should record:

```gdscript
last_observed_at
```

even if the first implementation never forgets geometry.

This allows later behavior such as:

* uncertainty increasing with age,
* preferring recently traveled routes,
* rechecking old passages,
* memory degradation,
* different memory capabilities by difficulty.

The initial rule can simply be:

> Remembered geometry persists indefinitely until contradicted.

That is easy to reason about and avoids unnecessary complexity.

---

# 14. Spatial Memory Revisions

Geometry changes should be versioned.

At minimum maintain:

```gdscript
var global_revision: int
```

Each actual memory update increments it.

Changed regions should also report the revision.

For example:

```gdscript
signal geometry_changed(
    region: AABB,
    revision: int
)
```

This allows Navigation to determine whether data used for an existing route is stale.

---

# 15. Why Revision Tracking Matters

Suppose Navigation creates a path using memory revision `104`.

Then Perception discovers a new opening.

```text
Spatial Memory revision:

104 → 105
```

If the changed region is unrelated to the path, Navigation can continue.

If it intersects the route:

```text
current path
     │
     X  changed geometry
     │
```

Navigation can invalidate and replan.

This avoids rebuilding or reevaluating every route whenever any memory changes.

---

# 16. Navigation Read API

Navigation should query Spatial Memory through a narrow interface.

At the simplest level:

```gdscript
func get_occupancy(
    position: Vector3
) -> OccupancyState
```

```gdscript
func get_clearance(
    position: Vector3
) -> float
```

```gdscript
func is_known_traversable(
    position: Vector3,
    required_clearance: float
) -> bool
```

```gdscript
func is_known_blocked(
    position: Vector3,
    required_clearance: float
) -> bool
```

```gdscript
func get_confidence(
    position: Vector3
) -> float
```

---

# 17. Regional Query API

Navigation will usually need more than individual point queries while rebuilding parts of its graph.

Provide:

```gdscript
func get_region(
    region: AABB
) -> SpatialMemoryRegion
```

`SpatialMemoryRegion` can contain the remembered geometry required to construct navigation data for that area.

Conceptually:

```gdscript
class_name SpatialMemoryRegion

var bounds: AABB
var revision: int

var cells: Array[GeometryMemoryCell]
```

The exact internal representation should remain opaque to Navigation where practical.

---

# 18. Snapshot API

If Navigation needs a stable representation while performing graph construction, expose an immutable snapshot.

```gdscript
func create_snapshot(
    region: AABB
) -> SpatialMemorySnapshot
```

Conceptually:

```gdscript
class_name SpatialMemorySnapshot

var bounds: AABB
var revision: int

func get_occupancy(position: Vector3) -> OccupancyState
func get_clearance(position: Vector3) -> float
```

This avoids data changing halfway through a potentially expensive path or graph operation.

For the jam, this may be unnecessary; direct regional reads are acceptable.

---

# 19. Spatial Memory → Navigation Events

Recommended signal:

```gdscript
signal geometry_changed(
    region: AABB,
    revision: int
)
```

Navigation listens for this.

Conceptually:

```gdscript
func _on_geometry_changed(
    region: AABB,
    revision: int
) -> void:

    nav_graph.invalidate_region(region)

    if current_path.intersects(region):
        request_replan()
```

Spatial Memory does not tell Navigation exactly how to rebuild.

It only reports:

> My remembered geometry changed here.

---

# 20. Initial Memory

The creature needs an initial model of the cave.

There are several possibilities.

For this design, the recommended initial approach is to initialize Spatial Memory from the **starting authored/generated cave geometry**.

```text
Initial cave
    ↓
memory initialization
    ↓
Spatial Memory revision 1
```

This represents the creature being familiar with its territory before gameplay begins.

After initialization:

> Live terrain modifications must no longer automatically update memory.

So:

```text
GAME START

Terrain state ───────────────┐
                            │
                            ▼
                      Spatial Memory


DURING GAME

Terrain changes      X      Spatial Memory
                              ▲
                              │
                        Perception only
```

This gives the creature full initial territorial knowledge while still allowing player modifications to surprise it.

---

# 21. Relationship to Navigation Graph

Spatial Memory should not itself contain `AStar3D`.

The relationship is:

```text
Spatial Memory
    ↓
remembered geometry
    ↓
Navigation Graph Builder
    ↓
Creature Navigation Graph
    ↓
AStar3D
```

This distinction is important.

Spatial Memory answers:

> What space do I believe exists?

The navigation graph answers:

> What movement connections can I derive from that believed space?

---

# 22. Navigation Graph Generation

Navigation may build a sparse graph from Spatial Memory using the previously defined process:

```text
remembered occupancy
      ↓
clearance field
      ↓
~2m candidate lattice
      ↓
remove insufficient-clearance candidates
      ↓
sort by clearance
      ↓
~3m greedy decimation
      ↓
connect nearby nodes
      ↓
validate edges against remembered geometry
      ↓
AStar3D
```

The graph is therefore a **derived cache**.

Spatial Memory remains the source of truth for what the alien remembers.

If necessary, the entire graph could be deleted and regenerated from Spatial Memory.

---

# 23. Local Graph Updates

When memory changes, Navigation should update only the affected region.

Example:

```text
Spatial Memory

geometry_changed(region)
        ↓
Navigation
        ↓
expand region by graph margin
        ↓
remove affected nodes / edges
        ↓
resample candidates
        ↓
reconnect with surrounding graph
```

This is especially important for player excavation.

Discovering a small tunnel should not require rebuilding the entire cave.

---

# 24. Geometry Surprise

The most important runtime interaction occurs when Navigation's remembered model does not match reality.

Example:

```text
Spatial Memory:
    passage is open

Navigation:
    path through passage

Actual World:
    passage is blocked
```

Movement cannot proceed.

Navigation should not conclude:

```text
memory[position] = SOLID
```

Instead:

```text
Navigation
    ↓
geometry validation request
    ↓
Perception
    ↓
actual local observation
    ↓
Spatial Memory
    ↓
memory changes
    ↓
Navigation receives geometry_changed
    ↓
replan
```

This ensures that only Perception converts reality into knowledge.

---

# 25. Discovering an Unexpected Opening

The reverse case is equally important.

Memory says:

```text
██████████████
     wall
```

Reality says:

```text
████      ████
    opening
```

Local Geometry Perception notices open space.

It submits:

```text
GeometryObservation:
    FREE
```

Spatial Memory changes.

Navigation's local graph update may discover that two previously disconnected navigation regions are now connected.

From that point onward, the alien remembers the shortcut.

---

# 26. Multiple Creatures

Spatial Memory should normally belong to a creature, not globally to the world.

```text
Creature A
    SpatialMemory A

Creature B
    SpatialMemory B
```

This naturally permits:

```text
Creature A discovers tunnel.

Creature B has not seen it.
```

Result:

```text
A can deliberately navigate through it.

B still plans as though the wall exists.
```

If later creature fiction requires shared knowledge, this can be implemented by sharing or propagating `GeometryObservation`s.

The Spatial Memory API does not need to change.

---

# 27. Spatial Memory and Suspicion

These systems should remain separate.

```text
SPATIAL MEMORY

"What do I think exists physically?"


SUSPICION

"Where do I think meaningful player activity exists?"
```

Both receive information from Perception:

```text
                       PERCEPTION
                       /        \
                      /          \
                     ▼            ▼
             SPATIAL MEMORY    SUSPICION
```

Suspicion may reference locations that Navigation cannot currently reach according to Spatial Memory.

For example:

```text
Suspicion:
    loud activity behind this wall.

Spatial Memory:
    no remembered route there.
```

That is valid information.

Behavior can decide what to do with the contradiction.

Spatial Memory should not attempt to resolve it.

---

# 28. Spatial Memory and Behavior

Behavior generally should **not query Spatial Memory directly**.

The normal path is:

```text
Behavior
    ↓
Navigation request
    ↓
Navigation
    ↓
Spatial Memory
```

For example:

```text
Behavior:
    investigate X

Navigation:
    cannot currently find remembered route to X
```

Behavior receives:

```text
destination unreachable
```

rather than performing its own geometry reasoning.

This keeps spatial planning inside Navigation.

---

# 29. Public API

A high-level interface could be:

```gdscript
class_name CreatureSpatialMemory


# ---- Writes from Perception ----

func observe_geometry(
    observation: GeometryObservation
) -> void


func observe_geometry_batch(
    observations: Array[GeometryObservation]
) -> void


# ---- Reads primarily for Navigation ----

func get_occupancy(
    position: Vector3
) -> OccupancyState


func get_clearance(
    position: Vector3
) -> float


func get_confidence(
    position: Vector3
) -> float


func is_known_traversable(
    position: Vector3,
    required_clearance: float
) -> bool


func get_region(
    region: AABB
) -> SpatialMemoryRegion


func get_revision() -> int


# ---- Change notification ----

signal geometry_changed(
    region: AABB,
    revision: int
)
```

Optional later APIs:

```gdscript
func create_snapshot(
    region: AABB
) -> SpatialMemorySnapshot


func get_last_observed_at(
    position: Vector3
) -> float


func is_known(
    position: Vector3
) -> bool
```

---

# 30. API Ownership

The dependency direction should be:

```text
PERCEPTION
    │
    │ observe_geometry(...)
    ▼
SPATIAL MEMORY
    │
    │ queries + geometry_changed
    ▼
NAVIGATION
```

Not:

```text
Navigation → edit Spatial Memory

Terrain → edit Spatial Memory

Behavior → edit Spatial Memory
```

Perception is the normal authoritative writer.

---

# 31. Spatial Memory Configuration

Recommended file:

```text
res://gameplay/creature/spatial_memory/
    spatial_memory_config.gd
```

as a Godot `Resource`.

Suggested parameters:

```gdscript
memory_cell_size: float
```

Controls spatial resolution.

---

```gdscript
minimum_observation_confidence: float
```

Observations below this value are ignored.

---

```gdscript
default_initial_confidence: float
```

Confidence assigned to the creature's pre-game territorial knowledge.

---

```gdscript
observation_conflict_threshold: float
```

Controls how much evidence is required to replace remembered information if observations are uncertain.

---

```gdscript
remember_geometry_indefinitely: bool
```

Initially:

```text
true
```

---

Potential future parameters:

```gdscript
confidence_decay_rate: float

unknown_navigation_policy: UnknownPolicy

minimum_navigation_confidence: float
```

These should not be required for the first implementation.

---

# 32. State Owned by Spatial Memory

The system should maintain:

```text
memory cells / chunks
global revision
regional revision information
confidence
observation timestamps
occupancy
clearance
```

It should not maintain:

```text
current path
navigation destination
current HFSM state
player target
suspicion
hotspots
last heard sound
active geometry scan
```

Those belong to other systems.

---

# 33. Example: Player Digs a Tunnel

At game start:

```text
ACTUAL WORLD

██████████████████


SPATIAL MEMORY

██████████████████
```

The player excavates:

```text
ACTUAL WORLD

█████        █████
```

Spatial Memory remains:

```text
██████████████████
```

Navigation therefore continues believing the regions are disconnected.

Later the creature approaches.

Geometry Perception observes:

```text
FREE SPACE
```

and calls:

```gdscript
spatial_memory.observe_geometry_batch(...)
```

Spatial Memory updates:

```text
█████        █████
```

and emits:

```gdscript
geometry_changed(changed_region, 128)
```

Navigation receives the event.

It rebuilds the affected section of its graph.

Previously:

```text
●──●        ●──●

disconnected
```

After update:

```text
●──●──●──●──●

connected
```

From then onward, the alien can intentionally use the tunnel.

---

# 34. Example: Remembered Route Becomes Invalid

Suppose the creature remembers:

```text
●────────────●
     route
```

Navigation plans through it.

Actual physics prevents progress.

Navigation reports:

```text
expected traversable geometry failed
```

and requests:

```gdscript
perception.request_geometry_scan(region, PATH_BLOCKED)
```

Perception observes the obstruction.

Spatial Memory changes.

Navigation receives:

```text
geometry_changed
```

and replans.

The creature therefore does not magically know the route changed, but it also does not mindlessly continue trying to walk through it.

---

# 35. Debugging Requirements

Spatial Memory must be independently visualizable.

The debugger should distinguish:

```text
actual geometry

from

remembered geometry
```

Recommended overlays:

```text
known free space

known solid space

unknown space

clearance

confidence

recently changed memory

current memory revision

navigation graph derived from memory
```

Particularly useful is a mode that displays:

```text
ACTUAL vs REMEMBERED
```

Differences should be visually apparent.

For example:

```text
Actual opening
+
Remembered wall
```

should be easy to inspect during development.

Debug information for a selected point might show:

```text
Spatial Memory

Position:
    (31.2, -8.4, 74.1)

Occupancy:
    SOLID

Clearance:
    0.0m

Confidence:
    .92

Last observed:
    71.4 sec ago

Revision:
    144

Actual terrain:
    FREE
```

That last line belongs only to developer debugging and must never affect creature logic.

---

# 36. Architectural Invariants

The Spatial Memory system should obey the following rules.

**Spatial Memory represents belief, not reality.**

**Terrain changes do not directly update Spatial Memory.**

**Perception is the normal writer of geometry knowledge.**

**Navigation reads remembered geometry rather than live terrain for strategic planning.**

**Movement still interacts with actual physics.**

**Navigation may report that its expectation failed, but it cannot rewrite memory itself.**

**Unknown, free, and solid space remain distinct concepts.**

**Clearance is remembered because traversability depends on creature size.**

**Memory changes are localized and revisioned.**

**The navigation graph is derived from Spatial Memory; it is not Spatial Memory itself.**

**Suspicion and geometry memory remain separate.**

**Behavior asks Navigation whether locations are reachable rather than reasoning directly about remembered geometry.**

The complete loop is therefore:

```text
                 PERCEPTION
                      │
                 what I observe
                      ▼
               SPATIAL MEMORY
                      │
                 what I believe
                      ▼
                 NAVIGATION
                      │
                    plan
                      ▼
                   MOVEMENT
                      │
                encounter reality
                      │
              expectation wrong?
                      │
                     yes
                      ▼
                 PERCEPTION
                      │
                    learn
                      ▼
               SPATIAL MEMORY
```

The Spatial Memory system is what turns destructible terrain from a simple pathfinding invalidation problem into part of the alien's cognition. The creature does not immediately know that the world has changed; it discovers changes, revises its model, and subsequently acts according to what it has learned.
