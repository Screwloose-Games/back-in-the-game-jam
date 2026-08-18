Below is a consolidated design that incorporates the decisions made so far: imperfect perception, spatial suspicion, destructible-terrain memory, HFSM + behavior trees, and Director-controlled encounter pacing.

# Alien Creature AI — Overall Design

## 1. Design Goal

The alien should behave like a dangerous predator operating with **imperfect knowledge**, rather than an AI agent with direct access to authoritative game state.

The player should be able to:

* attract it through noise,
* misdirect it,
* escape its immediate awareness,
* hide from it,
* alter the cave in ways it has not yet discovered,
* cause it to investigate incorrect hypotheses,
* and survive encounters without the creature simply forgetting everything.

At the same time, the creature should appear purposeful.

It should:

* remember evidence,
* accumulate suspicion in areas where activity repeatedly occurs,
* investigate plausible locations,
* reduce suspicion when searches fail,
* remember the geometry it has discovered,
* be surprised when remembered geometry is wrong,
* pursue players aggressively once sufficiently confident,
* wait outside likely hiding places,
* and eventually disengage so encounters have a deliberate horror rhythm.

The architecture achieves this by separating:

> **reality → observation → belief → decision → planning → physical action**

The creature never needs to know the actual complete state of the world.

---

# 2. Behavioral Strategy

The creature continuously runs through a reasoning loop:

```text
OBSERVE
   ↓
REMEMBER
   ↓
FORM SUSPICION
   ↓
CHOOSE BEHAVIOR
   ↓
PLAN
   ↓
ACT
   ↓
OBSERVE RESULTS
   ↓
REVISE BELIEFS
```

Two distinct kinds of memory are maintained.

### Spatial Memory

> What does the creature believe the cave looks like?

### Suspicion

> Where does the creature believe meaningful player activity may currently be happening?

These beliefs are independent and both may be wrong.

For example:

```text
Creature believes:

Tunnel A:
    geometry known
    high suspicion

Tunnel B:
    geometry known
    low suspicion

Tunnel C:
    remembered as blocked
    player has secretly excavated it
```

The creature can therefore make a completely rational decision based on incorrect information.

That is intentional.

---

# 3. Overall Architecture

The major systems are:

1. **Perception**
2. **Suspicion**
3. **Spatial Memory**
4. **Behavior**

   * HFSM
   * per-state behavior trees
5. **Navigation**
6. **Movement**
7. **Director** — level-scoped, outside the creature

High-level flow:

```text
                            ACTUAL WORLD
                    players / noise / terrain
                              / physics
                                  │
                                  ▼
                           ┌────────────┐
                           │ PERCEPTION │
                           └─────┬──────┘
                                 │
                   ┌─────────────┴──────────────┐
                   │                            │
             activity evidence          geometry observations
                   │                            │
                   ▼                            ▼
            ┌────────────┐              ┌────────────────┐
            │ SUSPICION  │              │ SPATIAL MEMORY │
            └─────┬──────┘              └───────┬────────┘
                  │                             │
                  │ beliefs                     │ remembered
                  │ about players               │ geometry
                  ▼                             │
            ┌─────────────────┐                 │
            │    BEHAVIOR     │◄── DIRECTOR     │
            │                 │    directive    │
            │ HFSM            │    down,        │
            │ Behavior Trees  │    report up    │
            │                 │    (per level)  │
            └────────┬────────┘                 │
                     │                          │
                     │ navigation intent        │
                     ▼                          ▼
                  ┌───────────────────────────────┐
                  │          NAVIGATION           │
                  └──────────────┬────────────────┘
                                 │
                          movement intent
                                 │
                                 ▼
                           ┌────────────┐
                           │  MOVEMENT  │
                           └─────┬──────┘
                                 │
                                 ▼
                            ACTUAL WORLD
```

There is also an important feedback loop:

```text
Navigation expects geometry
          │
          ▼
Movement encounters reality
          │
          ▼
Expectation mismatch
          │
          ▼
Perception rescans region
          │
          ▼
Spatial Memory updates
          │
          ▼
Navigation replans
```

---

# 4. System Dependency Graph

The allowed dependencies are:

```text
WORLD
  │
  ▼
PERCEPTION
  │
  ├────────────────────► SUSPICION
  │                       │
  │                       ▼
  │                    BEHAVIOR ◄──── DIRECTOR
  │                   /     \         (level-scoped)
  │                 HFSM     BT
  │                       │
  │                       ▼
  │                   NAVIGATION
  │                       ▲
  │                       │
  └────► SPATIAL MEMORY ──┘
                          │
                          ▼
                       MOVEMENT
                          │
                          ▼
                         WORLD
```

Additional narrow feedback:

```text
NAVIGATION
    │
    │ geometry validation request
    ▼
PERCEPTION
```

### Dependency rules

Allowed:

```text
Perception → World
Perception → Suspicion
Perception → Spatial Memory

Behavior → Suspicion
Behavior → Navigation

Director → Suspicion
    read-only
Director → Navigation metrics
    read-only, carried on Behavior's encounter report
Behavior → Director
    report up, directive down, once per tick

Navigation → Spatial Memory
Navigation → Perception
    only for geometry validation requests

Movement → World physics
```

Prohibited:

```text
Perception → HFSM transitions

Suspicion → Navigation

Suspicion → Behavior state changes

Spatial Memory → live terrain

Navigation → direct Spatial Memory mutation

Terrain destruction → Spatial Memory

Movement → Behavior decisions
```

---

# 5. Perception System

## Purpose

Perception answers:

> **What am I sensing right now?**

Perception is the creature's controlled interface to the authoritative world.

It contains independent senses such as:

```text
Hearing
Vision
Touch
Geometry Perception
```

Perception produces observations.

It does not interpret those observations into behavior.

---

## Hearing

Hearing is the primary player-detection mechanism.

Gameplay systems emit noise events:

```text
NoiseEvent
    position
    loudness
    source
    category
```

Example relative noise levels:

```text
Still             0
Crouch movement   very low
Walking           low
Sprinting         medium
Equipment         medium/high
Cranking          high
Drilling          very high
```

Hearing evaluates factors such as:

```text
source loudness
distance
obstruction
environmental attenuation
```

and produces:

```text
SuspicionEvidence
```

with an estimated location and uncertainty.

Hearing does not report:

```text
player_position = X
```

It reports approximately:

```text
A sound probably originated around X.
```

---

# 6. Vision

Vision is optional and configurable.

When enabled it should initially be:

* short range,
* relatively broad,
* unavailable or weak while calm,
* much more useful once the creature is already suspicious.

Vision produces evidence with substantially lower spatial uncertainty than hearing.

Vision should therefore reinforce or correct existing suspicion rather than automatically cause all creature behavior.

---

# 7. Touch

Touch represents very high-confidence close-range information.

Examples:

```text
direct player collision
near-contact
player entering/leaving a non-creature passable tunnel
```

It normally produces strong and spatially precise evidence.

---

# 8. Geometry Perception

Geometry Perception observes nearby cave geometry.

It produces:

```text
GeometryObservation
```

such as:

```text
this region is open

this region is solid

this passage has this approximate clearance
```

Geometry Perception is particularly important because the world is destructible.

It is the only normal mechanism by which the creature learns that terrain has changed.

---

# 9. Suspicion System

## Purpose

Suspicion answers:

> **Given everything I have perceived recently, where do I currently believe meaningful player activity exists?**

It transforms transient perception into persistent but decaying belief.

Suspicion owns:

```text
Evidence Memory
Spatial Hotspots
Global Suspicion
Player Suspicion
Local Disconfirmation
```

---

# 10. Suspicion Evidence

Every relevant perception produces an evidence record.

Conceptually:

```gdscript
SuspicionEvidence

type
sense

position
uncertainty_radius

initial_strength
confidence

observed_at
decay_rate

source_player
source_confidence
```

Each piece of evidence decays independently.

Therefore:

```text
new drilling evidence
    strong

five seconds later
    weaker

fifteen seconds later
    weak

eventually
    irrelevant
```

This prevents Suspicion from being merely a meter that gets manually incremented and decremented.

---

# 11. Suspicion Hotspots

Spatially related evidence accumulates into hotspots.

Example:

```text
      footstep
          ×

      drilling
          X

        impact
          ×

     ┌───────────┐
     │ HOTSPOT A │
     │    .81    │
     └───────────┘
```

Multiple hotspots may exist simultaneously.

```text
Hotspot A
    eastern cave
    .81

Hotspot B
    generator room
    .43

Hotspot C
    lower tunnel
    .18
```

The creature therefore maintains several competing hypotheses rather than only `last_noise_position`.

The hotspot location is a weighted estimate derived from current evidence.

Strong, recent, high-confidence observations influence it most.

---

# 12. Suspicion and Investigation

Investigation does not simply wait for suspicion to decay.

Searching provides **negative evidence**.

For example:

```text
Creature believes:
    player likely around A

Creature thoroughly searches A.

Perception:
    no supporting evidence found

Suspicion:
    local suspicion around A decreases
```

The earlier observation remains historically valid:

> A noise happened here.

What becomes less credible is:

> Whatever made the noise is still here.

This allows suspicion to be spatially resolved.

Example:

```text
Before search:

      .4
   .6 .8 .6
 .5 .9 .9 .7 .4


After searching left side:

      .4
   .1 .7 .6
 .0 .2 .8 .7 .4
```

The best unresolved location moves deeper into the hotspot.

Behavior can then continue searching systematically.

---

# 13. Global Suspicion

The system derives an overall normalized suspicion value:

```text
0.0 ... 1.0
```

This summarizes how strongly the creature currently believes meaningful activity is occurring.

Behavior can use it for broad HFSM transitions.

For example:

```text
low
    UNALERTED

moderate
    INVESTIGATING

high + credible player evidence
    HUNTING
```

The exact thresholds are Behavior configuration.

Suspicion itself does not change HFSM state.

---

# 14. Player Suspicion

Evidence may also contribute to beliefs about specific players.

Example:

```text
Player 1
    suspicion .82

Player 2
    suspicion .46
```

Evidence may initially be anonymous:

```text
hotspot .71
source unknown
```

and later become associated with Player 1 after sight/contact evidence.

The Director uses these values for multiplayer target arbitration.

---

# 15. Spatial Memory System

## Purpose

Spatial Memory answers:

> **What does the creature currently believe the physical cave looks like?**

The actual terrain and remembered terrain are deliberately allowed to diverge.

For example:

```text
ACTUAL

██████       ██████
       tunnel


MEMORY

███████████████████
        wall
```

If the player destroys the wall while the creature is elsewhere, nothing directly updates the creature.

The creature continues believing the wall exists until it observes otherwise.

---

# 16. Spatial Memory State

Spatial Memory contains remembered geometry such as:

```text
KNOWN_FREE
KNOWN_SOLID
UNKNOWN
```

plus information such as:

```text
clearance
confidence
last observed time
revision
```

The initial cave bake can initialize the creature's starting memory.

After gameplay begins, updates come through Geometry Perception.

---

# 17. Discovering Changed Terrain

Suppose Navigation expects a remembered tunnel to be traversable.

The creature reaches it and actual physics contradicts that expectation.

```text
Navigation:
    expected free

Reality:
    blocked
```

Navigation does not update Spatial Memory.

Instead:

```text
Navigation
    ↓
request geometry validation
    ↓
Perception
    ↓
GeometryObservation
    ↓
Spatial Memory
    ↓
geometry_changed
    ↓
Navigation replan
```

The reverse can happen when the creature discovers a player-created opening.

This creates genuine geometric surprise.

---

# 18. Navigation System

## Purpose

Navigation answers:

> **Given where Behavior wants me to go and what I remember about the cave, how can I reach it?**

Behavior supplies goals such as:

```text
investigate this position

chase this target estimate

move to this tunnel mouth

retreat toward this nest
```

Navigation turns those requests into paths.

---

# 19. Navigation Graph

The cave navigation graph is derived from remembered geometry.

Recommended process:

```text
Remembered voxel occupancy
        ↓
clearance field
        ↓
candidate points
        ↓
decimation toward tunnel centers
        ↓
shape-validated edges
        ↓
AStar3D graph
```

Candidate spacing and graph density can be tuned independently of the behavior system.

The creature collision shape should be used to validate edges rather than raycasts.

---

# 20. Local Navigation Updates

When Spatial Memory changes:

```text
changed region
    ↓
invalidate local graph
    ↓
resample affected region
    ↓
reconnect local nodes
    ↓
replan if necessary
```

The entire cave should not need to rebake for each terrain discovery.

---

# 21. Navigation Uses Belief; Movement Uses Reality

This distinction is critical.

### Navigation

Uses:

```text
remembered geometry
```

### Immediate movement

Uses:

```text
actual collision physics
```

Therefore the alien can plan incorrectly without walking through walls.

This produces:

```text
plan
  ↓
attempt
  ↓
unexpected obstacle
  ↓
investigate geometry
  ↓
learn
  ↓
replan
```

---

# 22. Behavior System

## Purpose

Behavior answers:

> **Given what I believe, what should I do?**

Behavior consists of:

```text
Creature HFSM
        +
per-state Behavior Trees
```

The HFSM handles large, persistent behavioral modes.

Behavior trees handle short-term choices within those modes.

Encounter-level pacing and multiplayer arbitration come from the Director, which is
level-scoped and sits outside the creature. Behavior reads its directive; it does not
contain it.

---

# 23. Creature HFSM

Top-level states:

```text
UNALERTED
INVESTIGATING
HUNTING
RETREATING
```

These modes change the general rules under which the alien operates.

They should therefore remain explicit states rather than being hidden inside one large behavior tree.

---

# 24. Unalerted

Purpose:

> Territorial ambient behavior.

The alien moves between nesting areas rather than following an obvious patrol route.

```text
Choose nest
    ↓
Travel
    ↓
Idle / animate
    ↓
Choose another nest
```

Nest choice may be weighted by distance and recent use.

Transition:

```text
meaningful suspicion
    ↓
INVESTIGATING
```

Extremely strong direct evidence may permit:

```text
UNALERTED → HUNTING
```

---

# 25. Investigating

Purpose:

> Resolve uncertainty.

The investigation behavior tree might resemble:

```text
INVESTIGATING
│
├── Current hotspot resolved?
│      └── select another hotspot
│
├── At search location?
│      └── inspect/search
│
└── Strong unresolved location?
       └── navigate there
```

Two conditions that belong to this mode are deliberately **not** in the tree: the hunt
threshold being reached, and there being no meaningful suspicion left. Both are HFSM
transition guards, evaluated before the tree ticks. A tree selects actions; it never
changes state.

Behavior repeatedly asks Suspicion:

```text
What is the strongest hotspot?

Where inside it is suspicion still unresolved?
```

Perception then determines what the creature actually discovers while searching.

---

# 26. Hunting

Purpose:

> Pursue a credible player target aggressively.

Hunting contains a behavior tree.

Example:

```text
HUNTING
│
├── Can attack?
│      └── Attack
│
├── Target confidently located?
│      └── Chase
│
├── Target likely hiding beyond reach?
│      └── Lurk
│
└── Recent target evidence exists?
       └── Search
```

"Hunt no longer sustainable" is an HFSM transition guard rather than a tree branch, for
the same reason as in §25.

Hunting should retain commitment despite brief perception loss.

The player disappearing from immediate perception does not instantly reset the alien.

---

# 27. Chase

The alien navigates toward its best current target estimate.

Target location may be supported by:

```text
hearing
vision
touch
recent target memory
```

The estimated position should become less trustworthy as evidence ages.

---

# 28. Search During Hunting

Losing direct contact does not necessarily reduce Hunting immediately to ordinary Investigating.

The creature may briefly search around the target's last credible region.

This search uses the same Suspicion infrastructure.

Hunting therefore remains a behavioral commitment while Suspicion describes where the target may have gone.

---

# 29. Tunnel Mouth Lurk

The alien cannot enter tunnels that are too narrow.

If:

```text
target evidence disappears
+
target was recently near a known non-creature passable tunnel
```

the creature may infer that the player is inside.

Behavior:

```text
Approach non-creature passable tunnel
    ↓
Take reachable position nearby
    ↓
Wait / listen / search
    ↓
new evidence?
 ┌───────┴────────┐
yes               no
 ↓                 ↓
CHASE         eventual RETREAT
```

Lurk duration should vary.

A non-creature passable tunnel therefore protects the player physically without clearing the creature's suspicion.

---

# 30. Retreating

Purpose:

> End an active encounter clearly.

The alien selects a destination that:

* increases separation,
* preferably leads toward a nesting region,
* makes the creature audibly/visually leave.

Retreat has a commitment period.

`RETREATING` has exactly one exit, and it is not `HUNTING`:

```text
RETREATING → UNALERTED
```

once enough separation and time are achieved.

There is no path back to `HUNTING` from a retreat, at any suspicion level, for any
evidence type — otherwise the Director cannot reliably terminate encounters, and an
encounter that cannot be terminated has no rhythm.

The visible consequence is real: an alien walking away will ignore a player who attacks
it. That should read as a predator that has lost interest, which is more unsettling than
one that can always be re-provoked. See `fsm.md` for the guard and the caveat.

---

# 31. Director

## Purpose

The Director answers:

> **What should happen for this to remain a good horror encounter?**

It deliberately operates above the creature's logical reasoning, and outside it: the
Director is level-scoped, one per level rather than one per creature, because it owns
encounter-level and party-level facts that no single creature should own.

The alien may logically want to keep hunting.

The Director may decide the encounter has already delivered sufficient pressure.

Full specification: `director.md`.

---

# 32. Menace

The Director tracks:

```text
menace: 0...1
```

Menace rises based on factors such as:

```text
time spent hunting
proximity to player
short path distance
line of sight
attack pressure
lurk pressure
```

At sufficient menace:

```text
force_disengage = true
```

which allows:

```text
HUNTING → RETREATING
```

even if Suspicion remains high.

This produces the intended horror cycle:

```text
quiet
  ↓
warning
  ↓
investigation
  ↓
hunt
  ↓
peak danger
  ↓
disengagement
  ↓
quiet
```

---

# 33. Multiplayer Target Selection

Suspicion provides the Director with player-specific beliefs.

Example:

```text
Player 1: .78
Player 2: .61
```

The Director chooses the actual hunt target.

The current target receives stickiness.

A new player must be **decisively more compelling** to trigger a switch.

Example:

```text
Current:
Player 1 .72
Player 2 .76

→ stay on Player 1
```

But:

```text
Player 1 .55
Player 2 .94

→ retarget Player 2
```

This prevents visible oscillation.

---

# 34. Movement System

Movement is the lowest-level creature-control system.

It receives:

```text
desired direction
desired speed
desired orientation
```

and owns:

```text
acceleration
deceleration
turning
CharacterBody3D movement
collision response
movement animation parameters
```

Movement knows nothing about:

```text
suspicion
players
hotspots
hunting
nests
Director
```

---

# 35. Example Full Encounter

A player begins drilling.

```text
WORLD
    drilling noise
        ↓
PERCEPTION
    strong hearing evidence
        ↓
SUSPICION
    hotspot forms
    overall suspicion rises
        ↓
BEHAVIOR
    UNALERTED → INVESTIGATING
```

Behavior requests the strongest unresolved location.

```text
SUSPICION
    location A
        ↓
BEHAVIOR
        ↓
NAVIGATION
```

Navigation plans using remembered geometry.

While the alien approaches, the player destroys a wall and moves through the new opening.

The alien has not seen this.

```text
ACTUAL WORLD
    opening

SPATIAL MEMORY
    wall
```

The alien reaches the original noise location and finds nothing.

```text
PERCEPTION
    negative evidence
        ↓
SUSPICION
    local suspicion around A decreases
```

Another noise comes from farther into the area.

```text
PERCEPTION
    new hearing evidence
        ↓
SUSPICION
    hotspot shifts
```

The alien approaches the location and discovers the destroyed wall.

```text
PERCEPTION
    geometry observation
        ↓
SPATIAL MEMORY
    wall → open passage
        ↓
NAVIGATION
    local graph updated
```

The alien now uses the tunnel.

Additional evidence raises suspicion enough to establish a credible target.

```text
BEHAVIOR
    INVESTIGATING → HUNTING
```

The Director selects Player 1.

The alien chases.

Player 1 enters a tunnel the alien cannot follow into.

The alien loses direct evidence near the tunnel mouth.

```text
HUNTING
    CHASE → LURK
```

The alien waits outside.

If the player makes noise:

```text
LURK → CHASE
```

Otherwise menace and the lurk timer eventually cause:

```text
HUNTING → RETREATING
```

The player hears the alien leave.

Eventually:

```text
RETREATING → UNALERTED
```

No system contains a script describing this complete encounter.

The behavior emerges from the interaction between independent systems.

---

# 36. Project Structure

Four modules ship today and they share one shape: the facade and the config resource at the
top, domain types in named subdirectories, and the same support directories underneath — so a
fifth is laid out by pattern rather than by argument.

```text
debug/      an overlay (Node3D) and a panel (Control), each taking its facade as a property
sandbox/    somewhere to LOOK at it, for the claims that are only checkable by eye
tests/      the GUT suite, plus a `*_test_case.gd` fixture with no `test_` prefix
tools/      verify_<module>_static.gd, verify_<module>_runtime.tscn, and — where an overlay
            is worth pinning down — capture_sandbox.tscn
README.md   scope, how to run the suites, the deliberate deviations from this document
```

```text
res://gameplay/creature/
│
├── perception/                      29 scripts
│   ├── creature_perception.gd       the facade
│   ├── perception_config.gd
│   ├── hearing.gd  vision.gd  touch.gd  geometry_perception.gd
│   ├── perception_probe.gd          the only door to the physics world
│   ├── perception_scan.gd
│   ├── observations/                noise_event, suspicion_evidence,
│   │                                geometry_observation, disconfirmation_observation
│   └── debug/  sandbox/  tests/  tools/
│
├── suspicion/                       22 scripts
│   ├── creature_suspicion.gd        the facade
│   ├── suspicion_config.gd
│   ├── evidence_memory.gd  hotspot_field.gd  player_beliefs.gd
│   ├── records/                     suspicion_hotspot, suspicion_evidence_record,
│   │                                suspicion_disconfirmation, player_suspicion_candidate
│   └── debug/  sandbox/  tests/  tools/
│
├── behavior/                        the subject of this document
│   ├── creature_behavior.gd         the facade; owns the nine-step tick
│   ├── behavior_config.gd
│   ├── behavior_context.gd          the typed per-tick view every tree node is handed
│   ├── behavior_goal.gd             the one place Behavior commands Navigation
│   ├── creature_state.gd            the four-state enum
│   │
│   ├── tree/                        the framework, and DOMAIN-FREE by static check
│   │   ├── bt_node.gd  behavior_tree.gd
│   │   ├── bt_action.gd  bt_condition.gd
│   │   ├── bt_composite.gd  bt_selector.gd  bt_sequence.gd
│   │   └── bt_decorator.gd  bt_cooldown.gd  bt_inverter.gd
│   │
│   ├── hfsm/
│   │   ├── creature_hfsm.gd  behavior_state.gd  behavior_transition.gd
│   │   └── states/
│   │       ├── unalerted_state.gd      + unalerted_memory.gd
│   │       ├── investigating_state.gd  + investigating_memory.gd
│   │       ├── hunting_state.gd
│   │       └── retreating_state.gd
│   │
│   ├── actions/                     `bt_` prefix, one file per leaf
│   │   ├── bt_idle_at_nest.gd  bt_travel_to_nest.gd
│   │   ├── bt_investigate_location.gd  bt_search_area.gd
│   │   └── bt_do_nothing.gd
│   │
│   ├── conditions/                  `bt_` prefix; SUCCESS or FAILURE only, never
│   │   ├── bt_at_nest.gd            side-effecting, and checked separately
│   │   └── bt_arrived_at_goal.gd
│   │
│   ├── world/                       level markers this module reads
│   │   ├── creature_nest.gd         a Marker3D in a group, and nothing else
│   │   └── nest_memory.gd
│   │
│   └── debug/  sandbox/  tests/  tools/
│
└── navigation/                      77 scripts
    ├── creature_navigation.gd       the facade
    ├── navigation_config.gd  clearance_profile.gd  locomotion_profile.gd
    ├── navigation_probe.gd          the only door to the physics world
    ├── navigation_source.gd         a level-scoped bake shared between creatures
    ├── graph/                       nav_graph, nav_graph_builder, nav_astar, patching
    ├── route/                       route_planner, route_follower, nav_route, chooser
    ├── locomotion/                  surface crawl, tunnel swim, wiggle, leap, avoidance/
    ├── knowledge/                   what the creature believes the graph is
    └── debug/  sandbox/  tests/  tools/
```

There is no `creature.tscn` and no shared `creature.gd`. The four facades are assembled by
whatever owns the creature, and `behavior/README.md`'s "Wiring one up" is the whole of it.
**Spatial Memory and Movement are not built** — see §21 and §34 for what they owe.

Three things earlier drafts of this section recommended, which the build deliberately did not
adopt:

```text
trees/ as a directory      A state builds its own tree in `_init()`. A tree is four lines
                           of composition, not a file.

actions/chase_target.gd    Leaves carry a `bt_` prefix and split into actions/ and
                           conditions/, because the two obey different rules -- an action
                           may command, a condition may never -- and the static verifier
                           checks each directory against its own list.

world/creature_crevice.gd  There is no crevice type. A non-creature passable tunnel is a
                           passage narrower than the alien, and navigation refuses it with
                           no marker, flag or layer anywhere (§29).
```

The Director is not under `creature/`, because it is not part of a creature. Only the two
value types exist; the Director itself is owed.

```text
res://gameplay/director/
│
├── encounter_directive.gd           what the Director asks of one creature, for one tick
├── encounter_report.gd              what Behavior tells it back
├── tests/
└── README.md

    encounter_director.gd, encounter_track.gd and director_config.gd are not built.
    See director.md.
```

---

# 37. System Responsibilities Summary

```text
PERCEPTION
"What just happened that I can sense?"

SUSPICION
"Where do I currently think meaningful activity is?"

SPATIAL MEMORY
"What do I think the cave looks like?"

HFSM
"What broad mode am I in?"

BEHAVIOR TREE
"What action makes sense within that mode right now?"

DIRECTOR
"What should happen to maintain good encounter pacing?"

NAVIGATION
"How do I reach the requested destination using what I remember?"

MOVEMENT
"How does my body physically execute that route?"
```

---

# 38. Core Architectural Principle

The alien should not appear intelligent because it has more information than the player expects it to have.

It should appear intelligent because it **uses limited information consistently**.

It:

```text
senses evidence
    ↓
forms beliefs
    ↓
remembers them
    ↓
acts on them
    ↓
tests them against reality
    ↓
changes its beliefs when proven wrong
```

This allows uncertainty, mistakes, surprise, persistence, search behavior, misdirection, and adaptation to emerge naturally from the architecture.

Those are the behaviors that should make the creature feel like a thinking predator rather than a conventional enemy following the player's true position.
