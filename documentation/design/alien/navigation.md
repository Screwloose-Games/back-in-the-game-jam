# Alien Navigation System Specification

## 1. Purpose

This system provides navigation for a single large alien creature moving through a deformable, high-density voxel cave in zero gravity.

The navigation system must support:

* arbitrary grabbable voxel surfaces;
* surface crawling;
* centered traversal through tunnels;
* slow traversal through tight spaces by deforming/squeezing the body;
* straight-line zero-gravity leaps across open spaces;
* player-only tunnels that the alien cannot fit through;
* locally deformable terrain;
* imperfect alien knowledge of terrain;
* discovery of newly mined routes;
* temporarily outdated navigation knowledge;
* believable inspection of changed terrain;
* higher-level search, interception, and ambush behavior;
* asynchronous path calculation;
* multiplayer;
* Web as the minimum-performance target.

The navigation system is not responsible for implementing sight, hearing, vibration sensing, or touch yet. Those systems will provide navigation goals through stubbed interfaces.

---

# 2. Fundamental Design Principles

## 2.1 Navigation derives entirely from voxel terrain

No navigation nodes, portals, tunnel markers, or chamber markers are manually placed.

All authoritative navigation data is generated from the voxel occupancy field.

## 2.2 The sparse navigation graph represents topology

The global navigation graph answers:

> What navigable areas are connected?

It does not prescribe exact physical body movement.

Graph nodes are navigation anchors, not necessarily positions through which the alien's center of mass must pass.

This distinction is especially important in large chambers, where topology nodes may lie near the center of open space while the alien normally crawls along a wall.

## 2.3 Global routing and local locomotion are separate

Global navigation determines approximately where the alien should travel.

Local locomotion determines how the alien physically executes the route.

```text
Goal
 ↓
Alien Knowledge
 ↓
Global Route
 ↓
Local Locomotion Planner
 ↓
Crawl / Tunnel / Wiggle / Leap
 ↓
Body Controller
```

## 2.4 Reality and alien knowledge are separate

Maintain two navigation representations:

```text
WorldNavigationGraph
AlienKnowledgeGraph
```

`WorldNavigationGraph` represents actual current terrain.

`AlienKnowledgeGraph` represents what the alien currently believes about the terrain.

The alien plans against its knowledge rather than against omniscient world state.

---

# 3. Environment Assumptions

## 3.1 Terrain

Source terrain:

```text
Voxel resolution: approximately 0.06 m
```

Typical cave dimensions:

```text
20–40 m
Typical large cave: ~30 m
```

Terrain changes are:

* localized;
* relatively infrequent;
* mining-based;
* subtractive only.

Therefore terrain can:

```text
open a route
widen a route
improve clearance
create a new leap opportunity
```

but cannot:

```text
close an existing route
create a new obstruction
invalidate a previously collision-free edge
```

This property should be exploited heavily.

---

# 4. Navigation Data Pipeline

Authoritative navigation is generated as:

```text
6 cm Voxel Occupancy
        ↓
~24 cm Navigation Occupancy
        ↓
Clearance Field
        ↓
Candidate Samples
        ↓
Clearance-Priority Decimation
        ↓
Sparse Topology Graph
```

Exact resolutions are tuning values and must not be hard-coded into algorithms.

Recommended defaults:

```text
source_voxel_size       = 0.06 m
nav_cell_size           = 0.24 m
candidate_spacing       = 2.0 m
node_separation         = 3.0 m
edge_search_radius      = 8.0 m
```

Expose all as configuration.

---

# 5. Clearance Field

## 5.1 Definition

For every downsampled navigation cell:

```text
clearance(position) =
    distance from position to nearest solid terrain
```

Use an approximate 3D Euclidean distance transform.

The field does not need voxel-perfect precision because exact traversal feasibility will later be validated by collision shape casts.

## 5.2 Uses

Clearance drives:

* navigation-node generation;
* medial positioning inside tunnels;
* determining normal-body feasibility;
* determining squeezed-body feasibility;
* traversal cost;
* tunnel-centering behavior;
* local candidate ranking.

---

# 6. Creature Clearance Profiles

The alien has at least two effective collision envelopes.

```text
NORMAL_SHAPE
SQUEEZED_SHAPE
```

`SQUEEZED_SHAPE` represents a total body diameter reduction of approximately:

```text
1.0 m
```

Exact shape and dimensions are configurable.

Define:

```gdscript
class_name AlienClearanceProfile

var normal_shape: Shape3D
var squeezed_shape: Shape3D

var normal_radius_equivalent: float
var squeezed_radius_equivalent: float
var safety_margin: float
```

The radius equivalents are used for coarse clearance tests.

Actual feasibility is determined using the collision shapes.

---

# 7. Locomotion Modes

```gdscript
enum AlienLocomotionMode {
    SURFACE_CRAWL,
    TUNNEL_SWIM,
    WIGGLE,
    LEAP
}
```

These are physically distinct modes and must not be treated as interchangeable animations.

---

# 8. Surface Crawl

## 8.1 Definition

The alien crawls while maintaining body contact with a grabbable terrain surface.

Any terrain on the configured grabbable collision layer is valid.

The alien may crawl on:

* floors;
* walls;
* ceilings;
* irregular cave surfaces.

## 8.2 Surface transitions

The alien may transition directly between surfaces when the next surface is within tentacle reach.

Example:

```text
wall → ceiling
wall → nearby opposing wall
floor → wall
```

If the required surface cannot be reached while maintaining contact, the alien must instead consider a leap.

## 8.3 Movement constraints

Surface crawling must account for:

```text
maximum speed
acceleration
turn radius
preferred body orientation
surface continuity
```

The alien should move more like:

```text
octopus + spider
```

than a rigid character walking upright.

Exact tentacle IK is outside the navigation layer.

---

# 9. Tunnel Swim

## 9.1 Definition

When surrounded sufficiently by reachable surfaces, the alien transitions to centered tunnel movement.

The desired body position tends toward the local medial axis of the tunnel.

The clearance field provides an approximation of this axis.

Conceptually:

```text
████████████████
██            ██
██     X      ██
██            ██
████████████████

X = preferred body center
```

## 9.2 Local objective

The local planner should favor positions having:

```text
high local clearance
+
forward progress toward route
```

rather than selecting one particular wall.

## 9.3 Transition criteria

Transition between `SURFACE_CRAWL` and `TUNNEL_SWIM` should be determined by local geometry rather than a hand-authored tunnel flag.

Exact thresholds should be configurable.

---

# 10. Wiggle Traversal

## 10.1 Definition

When:

```text
NORMAL_SHAPE does not fit
```

but:

```text
SQUEEZED_SHAPE fits
```

the route is traversable using `WIGGLE`.

## 10.2 Characteristics

Wiggle movement is:

* substantially slower;
* physically constrained;
* visually deliberate;
* expensive in route planning.

## 10.3 Hard traversal limits

If the squeezed body does not fit:

```text
route = BLOCKED
```

There is no navigation special case based on whether the passage belongs to the player.

A player-only tunnel naturally results from different body dimensions.

---

# 11. Leap Traversal

## 11.1 Physics

A leap is a straight-line zero-gravity trajectory.

```text
position(t) = origin + velocity * t
```

The alien:

* cannot redirect itself once airborne;
* cannot stop in open space;
* has no inherent maximum flight distance;
* continues until it grabs terrain or collides.

## 11.2 Leap requirements

A planned leap requires:

1. a valid launch pose;
2. a collision-free trajectory for the creature body;
3. a useful reachable/grabbable destination;
4. locomotion logic capable of landing/grabbing there.

Use shape casts rather than raycasts.

## 11.3 Dynamic generation

Long-distance leap edges are **not baked globally**.

Leap opportunities are queried dynamically by the local planner.

This avoids O(n²) permanent connections.

## 11.4 Leap preference

The alien should generally prefer a leap when it saves approximately:

```text
10 m of equivalent crawling
```

This should emerge from cost rather than a hard decision rule.

For example:

```text
crawl_cost =
    crawl_distance / crawl_speed

leap_cost =
    preparation_time
    + flight_time
    + grab_time
    + leap_bias
```

Tune `leap_bias` until roughly 10 m of crawl savings makes a leap attractive.

## 11.5 Opportunistic grabs

While airborne, continuously check for reachable grabbable surfaces.

The alien may grab a useful surface before reaching its originally intended destination.

The leap controller owns this behavior, not global pathfinding.

---

# 12. Navigation Node Generation

## 12.1 Candidate lattice

Sample candidate points throughout navigable cave volume using approximately:

```text
2 m spacing
```

Reject candidates whose clearance is below the alien's minimum possible traversal clearance.

## 12.2 Clearance-priority decimation

Sort surviving candidates by:

```text
clearance descending
```

Greedily accept candidates.

Reject a candidate if an already accepted point lies within approximately:

```text
3 m
```

This tends to preserve points near:

* tunnel centers;
* chamber centers;
* large openings.

This graph is therefore a rough sparse medial skeleton.

## 12.3 Node structure

```gdscript
class_name AlienNavNode

var id: int
var position: Vector3
var clearance: float
var chunk_id: Vector3i

var nearby_surface_data
```

`nearby_surface_data` may be calculated lazily.

Nodes do not require semantic labels such as "room" or "tunnel."

---

# 13. Navigation Edges

## 13.1 Candidate selection

For each node, consider nearby nodes within:

```text
edge_search_radius ≈ 8 m
```

A simple initial implementation may retain approximately six useful neighbors.

However, the neighbor count must remain configurable.

Future improvement may preserve neighbors based on directional coverage instead of raw distance.

## 13.2 Validation

Do not validate connectivity with a raycast.

Use shape casts.

Evaluate:

```text
NORMAL_SHAPE
SQUEEZED_SHAPE
```

Classification:

```text
normal cast succeeds
    → NORMAL_VOLUME

normal fails
squeezed succeeds
    → WIGGLE

both fail
    → no edge
```

## 13.3 Edge structure

```gdscript
enum AlienNavEdgeType {
    NORMAL_VOLUME,
    WIGGLE
}

class_name AlienNavEdge

var from_id: int
var to_id: int
var type: AlienNavEdgeType

var distance: float
var min_clearance: float
var base_cost: float
```

Do not permanently encode `LEAP` as ordinary graph edges.

Surface crawl versus tunnel swimming may be chosen locally while consuming a `NORMAL_VOLUME` edge.

---

# 14. Edge Cost

Do not use clearance as the only `AStar3D.weight_scale`.

The preferred conceptual cost is traversal time plus penalties.

```text
edge_cost =
    expected_traversal_time
    + mode_penalty
    + uncertainty_penalty
```

Initial examples:

```text
NORMAL_VOLUME:
    distance / expected_normal_speed

WIGGLE:
    distance / wiggle_speed
    + squeeze_transition_penalty
```

Local planning can further decide whether normal-volume travel becomes:

```text
SURFACE_CRAWL
```

or:

```text
TUNNEL_SWIM
```

Clearance can contribute a moderate comfort/caution penalty but should not dominate the entire system.

---

# 15. AStar3D

Godot `AStar3D` may be used to hold the sparse connectivity graph and perform coarse route searches.

The resulting point path represents:

```text
topological route anchors
```

not mandatory physical center-of-mass waypoints.

Expected graph size for typical levels should be low enough that pathfinding cost is insignificant compared with local geometry work.

---

# 16. Query Endpoint Attachment

A creature position or target position will usually not lie directly on a graph node.

Do not simply call:

```gdscript
astar.get_closest_point()
```

and trust that result.

The nearest graph node may lie through terrain.

Instead:

1. find several nearby candidate nodes;
2. shape-cast between the true endpoint and each candidate;
3. select the nearest feasible candidate.

Apply this to both:

```text
route start
route destination
```

If no destination node is reachable, choose the closest reachable graph location toward the requested goal.

---

# 17. Global Path Query

Conceptual API:

```gdscript
class_name AlienGlobalNavigator

func request_route(
    start: Vector3,
    target: Vector3,
    knowledge: AlienKnowledgeGraph
) -> AlienRoute
```

Result:

```gdscript
class_name AlienRoute

var anchors: PackedVector3Array
var edges: Array[AlienRouteSegment]
var target_position: Vector3
var status: RouteStatus
```

Statuses:

```gdscript
enum RouteStatus {
    COMPLETE,
    PARTIAL,
    UNREACHABLE
}
```

A partial route should terminate at the nearest useful reachable location rather than produce an empty path whenever possible.

---

# 18. Local Route Consumption

The locomotion planner consumes the global route one segment at a time.

It may collapse redundant anchors.

Example:

```text
A → B → C → D
```

may become:

```text
A → D
```

when the locomotion mode can safely execute that shortcut.

Waypoint advancement must be monotonic.

Never move backward to a previous graph waypoint because of nearest-point changes.

---

# 19. Locomotion-Aware Path Smoothing

Path smoothing must not use a generic visibility test.

Define:

```gdscript
func can_skip_to(
    target: Vector3,
    mode: AlienLocomotionMode
) -> bool
```

Mode rules:

### Surface crawl

Requires:

* continuous usable nearby surface;
* compatible turn geometry;
* body clearance;
* no unsupported open-space section.

### Tunnel swim

Requires:

* normal body clearance;
* navigable enclosed volume;
* suitable medial route.

### Wiggle

Requires:

* squeezed-body clearance for entire shortcut.

### Leap

Requires:

* straight collision-free flight;
* valid launch;
* valid grabbable endpoint.

---

# 20. Local Planner

Conceptual component:

```gdscript
class_name AlienLocalPlanner

func plan_next_motion(
    body_state: AlienBodyState,
    route: AlienRoute
) -> AlienMotionCommand
```

It determines:

```text
current locomotion mode
next desired body position
preferred forward direction
preferred body orientation
preferred surface normal
whether to prepare a leap
whether to squeeze
```

---

# 21. Surface Crawl Steering

The crawler should not attempt to generate voxel-perfect paths.

Use local geometry sampling and steering.

Candidate movement directions may be scored according to:

```text
goal progress
surface continuity
body clearance
preferred orientation
turn cost
collision risk
```

Conceptually:

```text
score =
      goal_alignment
    + surface_quality
    + clearance_score
    + orientation_continuity
    - turning_penalty
    - collision_penalty
```

The exact weights are tuning parameters.

---

# 22. Turn Radius and Momentum

The creature has:

```text
maximum crawl speed
acceleration
turn radius
```

The local planner must therefore discourage sudden direction changes.

Turn penalty should depend on:

```text
angle between current velocity and candidate movement
current speed
available turning distance
```

The alien should prefer smooth sweeping movement over equivalent zig-zag routes.

---

# 23. Body Orientation

Global A* does not include orientation as part of node state.

Orientation belongs to local locomotion.

The local controller should seek continuity of:

```text
body forward
body up/reference orientation
surface normal
```

This avoids multiplying global states by orientation while still producing physically coherent movement.

---

# 24. Runtime Terrain Updates

## 24.1 Important invariant

Mining is subtractive.

Therefore:

> An existing valid navigation edge remains valid after mining.

World navigation may become incomplete, but existing graph connectivity does not become physically false.

## 24.2 Terrain update process

When terrain changes:

```text
Voxel modification
      ↓
mark affected nav area dirty
      ↓
update local downsampled occupancy
      ↓
update local clearance values
      ↓
rerun candidate sampling locally
      ↓
rerun local decimation
      ↓
merge new nodes
      ↓
test new connections
```

Do not re-bake the entire graph.

## 24.3 Do not insert the dig center directly

The center of a mining operation is not necessarily a useful navigation skeleton point.

Runtime node creation must use approximately the same candidate and decimation rules as bake-time generation.

This keeps runtime graph quality consistent with baked graph quality.

---

# 25. Chunking

The voxel world should expose chunks.

Navigation updates operate over:

```text
affected chunk
+
whatever neighboring cells/chunks are required by clearance calculations
```

Navigation chunk size may differ from rendering/terrain chunk size if useful.

Each chunk should expose a revision counter:

```gdscript
var terrain_revision: int
```

Although subtractive terrain prevents existing authoritative edges from becoming invalid, revisions are still useful for:

* knowledge freshness;
* cached local geometry;
* cached leap queries;
* debug tooling.

---

# 26. World Navigation Graph

`WorldNavigationGraph` is authoritative.

It always represents currently known game-world geometry after asynchronous terrain updates complete.

Conceptual interface:

```gdscript
class_name WorldNavigationGraph

func get_node(id: int) -> AlienNavNode
func get_neighbors(id: int) -> Array[int]

func find_nearby_nodes(
    position: Vector3,
    radius: float
) -> Array[int]

func find_route(
    start_node: int,
    end_node: int
) -> AlienRoute
```

---

# 27. Alien Knowledge Graph

The alien must not directly use the authoritative world graph for behavioral routing.

The alien maintains remembered topology.

Possible state:

```gdscript
enum KnowledgeState {
    UNKNOWN,
    SUSPECTED,
    PARTIALLY_EXPLORED,
    KNOWN,
    STALE,
    INVALID
}
```

Knowledge records may include:

```gdscript
class_name AlienKnownNode

var world_node_id: int
var state: KnowledgeState
var confidence: float
var last_observed_time: float
var known_terrain_revision: int
```

And equivalent information for edges.

---

# 28. Newly Mined Terrain

When the player mines a new passage:

```text
WorldNavigationGraph
```

may immediately learn:

```text
A → new route → B
```

but:

```text
AlienKnowledgeGraph
```

must not automatically receive that connection.

The alien can continue believing the previous topology until its sensory/inspection systems discover the change.

This is intentional.

---

# 29. Geometry Mismatch Behavior

If the alien reaches an area and local geometry differs significantly from its remembered model:

```text
MOVING
  ↓
GEOMETRY_MISMATCH
  ↓
INSPECTING_GEOMETRY
  ↓
RELEARNING
  ↓
REPLANNING
```

The alien should not instantly consume authoritative navigation information and continue moving.

The delay gives the animation/behavior system an opportunity to show:

* stopping;
* looking/orienting;
* probing with tentacles;
* investigating a new opening;
* cautiously entering;
* updating its knowledge.

---

# 30. Inspection System Contract

Navigation only needs to issue an inspection request.

Example:

```gdscript
class_name AlienInspectionRequest

var position: Vector3
var reason: InspectionReason
var affected_chunk: Vector3i
```

Possible reasons:

```gdscript
enum InspectionReason {
    UNKNOWN_OPENING,
    GEOMETRY_MISMATCH,
    STALE_ROUTE,
    FAILED_TRAVERSAL
}
```

The behavior/animation system decides exactly how the inspection looks.

When inspection completes, it informs the knowledge system which nearby world-navigation data may now be learned.

---

# 31. Replanning

Do not continuously calculate full paths every frame.

Replan on events such as:

```text
navigation goal changes
target estimate moves > threshold
current route becomes behaviorally inappropriate
new topology is learned
inspection completes
locomotion transition requires reconsideration
periodic pursuit timer expires
```

Initial pursuit timer:

```text
~0.5 seconds
```

Initial movement threshold:

```text
~2 m
```

Both configurable.

Path computation may be asynchronous.

---

# 32. Compute Budget

Target maximum enemy navigation/AI budget:

```text
10 ms
```

This should be treated as an upper bound rather than a per-frame target.

Expensive operations should be:

* event driven;
* distributed over frames;
* asynchronous where practical.

Potentially expensive tasks:

```text
local clearance recalculation
local graph patching
large route searches
multiple leap candidate casts
local surface sampling
```

The single-alien constraint permits greater per-agent complexity than conventional crowd navigation.

---

# 33. Higher-Level Navigation Intent

Navigation does not decide what the alien wants.

An external behavior system provides goals.

Example:

```gdscript
class_name AlienNavigationGoal

var position: Vector3
var goal_type: GoalType
var confidence: float
var urgency: float
```

Possible future goals:

```text
investigate stimulus
search location
approach suspected player location
intercept predicted player route
guard exit
ambush
explore unknown opening
```

Navigation answers:

> How could I get there given what I currently believe?

---

# 34. Sensory Stub

Define a common sensory interface now.

```gdscript
enum AlienStimulusType {
    VISION,
    SOUND,
    VIBRATION,
    TOUCH
}

class_name AlienStimulus

var type: AlienStimulusType
var position: Vector3
var strength: float
var confidence: float
var timestamp: float
```

Current implementation may simply return no stimuli:

```gdscript
func get_stimuli() -> Array[AlienStimulus]:
    return []
```

Debug systems should be able to inject synthetic stimuli.

---

# 35. Imperfect Route Selection

Do not create unpredictability with arbitrary bad decisions.

Instead:

1. calculate several plausible routes or route destinations;
2. compare their costs;
3. choose probabilistically among reasonable alternatives.

Example:

```text
Route A = 31
Route B = 34
Route C = 38
Route D = 67
```

The alien may choose A, B, or C.

It should almost never choose D unless another behavior explains that choice.

Higher intelligence narrows selection toward better alternatives.

Lower intelligence increases variation.

---

# 36. Future Interception

Higher intelligence may use travel-time estimates rather than chase current player position.

Conceptually:

```text
player likely exits:
A
B
C

estimate:
player ETA to each exit
alien ETA to each exit

choose favorable interception point
```

This belongs above the core pathfinder.

The navigation graph only provides travel estimates and routes.

---

# 37. Recommended Godot Component Structure

```text
Alien
├── AlienBrain
├── AlienKnowledge
├── AlienNavigator
│   ├── AlienGlobalNavigator
│   ├── AlienLocalPlanner
│   └── AlienLeapPlanner
├── AlienLocomotion
│   ├── SurfaceCrawlController
│   ├── TunnelSwimController
│   ├── WiggleController
│   └── LeapController
├── AlienBody
└── AlienPerception
    ├── VisionSensor       [stub]
    ├── HearingSensor      [stub]
    ├── VibrationSensor    [stub]
    └── TouchSensor        [stub]
```

World:

```text
VoxelWorld
├── VoxelChunks
├── TerrainRevisionTracker
└── AlienNavigationWorld
    ├── NavigationOccupancy
    ├── ClearanceField
    ├── NavigationGraphBuilder
    ├── RuntimeGraphPatcher
    └── WorldNavigationGraph
```

---

# 38. Suggested Core Data Flow

During normal navigation:

```text
AlienBrain
    chooses destination
        ↓
AlienKnowledge
    exposes believed topology
        ↓
AlienGlobalNavigator
    computes coarse route
        ↓
AlienLocalPlanner
    examines next route segment
        ↓
select:
    crawl
    tunnel
    wiggle
    leap
        ↓
AlienLocomotion
    executes movement
```

During mining:

```text
VoxelWorld modified
        ↓
local occupancy changes
        ↓
clearance update
        ↓
local node generation
        ↓
new world graph connectivity
        ↓
AlienKnowledge remains unchanged
```

During discovery:

```text
alien encounters changed geometry
        ↓
inspection
        ↓
knowledge update
        ↓
replan
```

---

# 39. Debug Visualization Requirements

Build navigation debug rendering before advanced behavior.

Minimum overlays:

### World graph

Render:

```text
nodes
graph edges
node clearance
edge type
```

### Knowledge graph

Render separately:

```text
known nodes
unknown world nodes
stale knowledge
known connections
```

### Current route

Render:

```text
global anchors
current anchor index
collapsed/skipped anchors
```

### Locomotion

Render:

```text
current mode
desired movement
preferred surface normal
clearance
normal body volume
squeezed body volume
```

### Leap planner

Render:

```text
candidate trajectory
shape-cast volume
landing candidate
rejection reason
```

### Terrain updates

Render:

```text
dirty chunks
new candidates
accepted nodes
new edges
```

This tooling is considered part of the navigation implementation rather than optional polish.

---

# 40. Failure Conditions to Explicitly Handle

## 40.1 Waypoint oscillation

Route progress index must only move forward unless a full replan occurs.

## 40.2 Crevice grinding

If the alien repeatedly attempts to enter a route near its minimum clearance:

* abort local traversal;
* mark the knowledge edge questionable;
* inspect/replan.

Do not merely push against collision indefinitely.

## 40.3 No graph endpoint

Try multiple nearby nodes rather than trusting nearest-node lookup.

## 40.4 No complete route

Return a useful partial route toward the destination where possible.

## 40.5 Leap launch invalidated locally

Abort before launch and return control to local planning.

Once launched, no mid-flight path correction is possible.

## 40.6 Newly discovered opening

Do not instantaneously route through it.

Trigger inspection/knowledge acquisition first unless current behavior explicitly allows reckless exploration.

---

# 41. Initial Implementation Sequence

## Phase 1 — Navigation representation

Implement:

1. downsampled occupancy;
2. clearance field;
3. candidate lattice;
4. clearance-priority decimation;
5. sparse `AStar3D` graph;
6. normal and squeezed shape-cast edge validation;
7. debug drawing.

Success condition:

> Given arbitrary points in static terrain, the system can correctly identify creature-reachable topology.

## Phase 2 — Basic route following

Implement:

1. endpoint attachment;
2. A* route query;
3. monotonic waypoint following;
4. path smoothing;
5. unreachable/partial paths.

Success condition:

> A debug body can move through cave topology without entering spaces too small for the alien.

## Phase 3 — Surface crawl

Implement:

1. nearby surface sampling;
2. surface-normal tracking;
3. crawl steering;
4. turn-radius constraints;
5. body-orientation continuity.

Success condition:

> The alien can traverse large rooms while remaining attached to cave surfaces.

## Phase 4 — Tunnel swim

Implement:

1. confined-space detection;
2. clearance-gradient/medial centering;
3. crawl ↔ tunnel transition.

Success condition:

> The alien naturally centers itself in tunnels.

## Phase 5 — Wiggle

Implement:

1. normal-shape failure;
2. squeezed-shape route validation;
3. squeeze transition;
4. slow crevice movement;
5. exit transition.

Success condition:

> Tight passages are usable only when the alien's compressed body actually fits.

## Phase 6 — Leap

Implement:

1. launch preparation;
2. candidate destination search;
3. straight shape-cast flight validation;
4. leap cost comparison;
5. ballistic movement;
6. landing/grabbing;
7. opportunistic grab.

Success condition:

> The alien uses zero gravity to take meaningful shortcuts across large rooms.

## Phase 7 — Deformable navigation

Implement:

1. dirty-area detection;
2. local clearance updates;
3. local candidate regeneration;
4. graph patching.

Success condition:

> Mining opens new routes without rebaking the cave.

## Phase 8 — Knowledge

Implement:

1. world/knowledge graph separation;
2. known/stale/unknown states;
3. topology discovery;
4. geometry mismatch detection.

Success condition:

> The alien can possess incorrect or incomplete terrain knowledge.

## Phase 9 — Inspection

Implement:

1. inspection state;
2. tentacle-probe hooks;
3. delayed knowledge acquisition;
4. post-inspection replan.

Success condition:

> Freshly changed terrain produces visible investigation rather than instant omniscient rerouting.

---

# 42. Primary Invariants

These should remain true throughout implementation.

### Invariant 1

The global graph represents connectivity, not exact physical movement.

### Invariant 2

A route is never considered physically valid solely because two graph nodes are connected.

The locomotion layer validates execution.

### Invariant 3

The alien cannot deliberately traverse unsupported open space except through `LEAP`.

### Invariant 4

Once a leap begins, its trajectory cannot be redirected.

### Invariant 5

Body size determines route accessibility.

Player-only tunnels require no special navigation flags.

### Invariant 6

Subtractive terrain cannot invalidate an existing authoritative navigation edge.

### Invariant 7

Terrain changes may make the world graph incomplete until local patching occurs.

### Invariant 8

Updating the world graph does not automatically update alien knowledge.

### Invariant 9

The alien plans using what it believes, not what the game globally knows.

### Invariant 10

Exact tentacle movement and IK do not belong in global pathfinding.

---

# 43. Acceptance Scenarios

The system should eventually pass the following gameplay tests.

### Scenario A — Ordinary tunnel

Alien enters a tunnel large enough for its body.

Expected:

```text
surface crawl
→ tunnel swim
→ centered traversal
→ surface crawl
```

### Scenario B — Tight tunnel

Normal body does not fit but compressed body does.

Expected:

```text
approach
→ squeeze
→ wiggle
→ emerge
→ decompress
```

### Scenario C — Player-only escape route

Player enters tunnel narrower than alien's squeezed body.

Expected:

```text
alien approaches
→ determines route unusable
→ does not clip/grind through opening
→ replans/searches
```

### Scenario D — Large room

Alien's target lies on the opposite side of a chamber.

Crawling route:

```text
30 m
```

Valid leap:

```text
20 m
```

Expected:

```text
prepare
→ leap
→ grab opposite surface
```

assuming configured costs make the ~10 m saving worthwhile.

### Scenario E — Small shortcut

Crawl route:

```text
21 m
```

Leap:

```text
18 m
```

Expected:

```text
continue crawling
```

assuming leap overhead outweighs 3 m saved.

### Scenario F — Newly mined alien-sized tunnel

Player creates a new wide passage.

Expected:

```text
world graph gains route
alien does not automatically know
alien later discovers opening
alien inspects it
knowledge updates
alien may subsequently use route
```

### Scenario G — Newly mined player-only tunnel

Player mines a passage only the player fits through.

Expected:

```text
world topology recognizes open space
alien navigation never creates a valid squeezed traversal connection
alien cannot follow
```

### Scenario H — Long leap

A straight collision-free trajectory crosses a large chamber.

Expected:

```text
distance alone does not prohibit leap
```

because the alien has no maximum leap distance.

### Scenario I — Mid-flight wall proximity

Alien passes close enough to a useful wall while leaping.

Expected:

```text
leap controller may select opportunistic grab
→ transition to surface crawl
```

### Scenario J — Stale knowledge

Alien expects old geometry but encounters newly excavated space.

Expected:

```text
detect discrepancy
→ stop/inspect
→ update knowledge
→ replan
```

rather than instantly understanding the new cave layout.

---

# 44. Final System Boundary

The navigation system owns:

```text
terrain-derived navigability
clearance
connectivity
route calculation
route feasibility
locomotion-mode selection
local path steering
leap planning
knowledge of terrain
navigation-related inspection triggers
```

It does not own:

```text
player detection
vision
hearing
vibration sensing
touch sensing
combat decisions
search strategy
ambush strategy
tentacle IK
animation implementation
```

Those systems interact with navigation through explicit goals, stimuli, and locomotion/inspection commands.

The intended architectural boundary is:

```text
"What does the alien want to investigate?"
             ↓
          AI Brain
             ↓
"Where does it believe that is?"
             ↓
       Alien Knowledge
             ↓
"How can it get there?"
             ↓
         Navigation
             ↓
"How does its body execute that?"
             ↓
        Locomotion / IK
```
