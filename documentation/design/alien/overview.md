# High-Level System Design

The creature AI is divided into five major systems:

1. **Perception** — observes the world.
2. **Spatial Memory** — stores the creature's remembered understanding of geometry.
3. **Navigation** — plans movement through remembered geometry.
4. **Aggression** — interprets evidence about players and determines how interested, suspicious, or committed the creature is.
5. **Behavior** — decides what the creature should do, including encounter pacing through the Director.

The systems deliberately separate **knowledge** from **decision-making**.

The creature does not directly react to authoritative game state such as "the player is here" or "this voxel was destroyed." Instead, it observes evidence, remembers some of that evidence, forms an assessment of the player, and then chooses behavior based on what it currently believes.

At the highest level:

```text
                         ACTUAL WORLD
                players, sound, terrain, physics
                              │
                              │ observations
                              ▼
                       ┌─────────────┐
                       │ PERCEPTION  │
                       └──────┬──────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
         geometry observations       player evidence
                │                           │
                ▼                           ▼
       ┌────────────────┐          ┌────────────────┐
       │ SPATIAL MEMORY │          │   AGGRESSION   │
       └───────┬────────┘          └───────┬────────┘
               │                           │
        remembered geometry          threat / interest
               │                           │
               ▼                           ▼
       ┌────────────────┐          ┌────────────────┐
       │   NAVIGATION   │◄─────────│    BEHAVIOR    │
       └───────┬────────┘ commands └────────────────┘
               │                           │
               │                           │
               │             includes HFSM + Director
               ▼
            MOVEMENT
               │
               ▼
          ACTUAL WORLD
```

A secondary feedback path handles incorrect geometric knowledge:

```text
Navigation discovers that reality
does not match its expectation
              │
              ▼
     Geometry validation request
              │
              ▼
         Perception
              │
              ▼
       Spatial Memory
              │
              ▼
         Navigation
            replans
```

This feedback loop allows the creature to be genuinely surprised by changes to destructible terrain without making the navigation system omniscient.

---

# 1. Perception System

## Responsibility

The Perception system answers:

> **What can the creature currently observe?**

It is the creature's only normal interface to the authoritative game world.

Perception converts physical game state into observations that other AI systems can understand.

It includes senses such as:

```text
Hearing
Vision
Touch
Geometry perception
```

These senses do not make behavioral decisions.

For example, Hearing does not say:

```text
Chase Player 1.
```

It reports something closer to:

```text
A strong sound was perceived near this position.

Source appears associated with Player 1.

Signal strength: 0.73
```

Likewise, geometry perception does not say:

```text
Rebuild the path through this tunnel.
```

It reports:

```text
This region currently appears to contain open space.
```

## Outputs

Perception produces two broad categories of information.

### Player-related evidence

Examples:

```text
heard player
saw player
touched player
heard equipment
last observed position
signal strength
observation confidence
```

This information flows primarily into the **Aggression system**.

### Geometry observations

Examples:

```text
known free space
known solid space
available clearance
unexpected obstruction
unexpected opening
```

These observations flow into **Spatial Memory**.

## Important Boundary

Perception knows about:

```text
actual nearby world state
```

but it does not know about:

```text
Investigating
Hunting
Retreating
navigation goals
encounter pacing
```

Its job ends once observations have been produced.

---

# 2. Spatial Memory System

## Responsibility

The Spatial Memory system answers:

> **What does the creature currently believe the environment looks like?**

Spatial Memory is deliberately different from actual terrain.

The player may destroy terrain without the creature knowing about it.

For example:

```text
ACTUAL WORLD

██████        ██████
       opening


CREATURE MEMORY

████████████████████
          wall
```

Until the creature observes the difference, its memory remains incorrect.

This gives the creature persistent but fallible knowledge of the cave.

## Inputs

Spatial Memory receives:

```text
GeometryObservation
```

from Perception.

A new observation is reconciled with existing memory.

For example:

```text
remembered:
    SOLID

observed:
    FREE

result:
    memory becomes FREE
```

The updated region receives a new revision so dependent systems can detect that remembered geometry changed.

## Outputs

Spatial Memory exposes remembered geometry to Navigation.

Conceptually, Navigation can ask questions such as:

```text
Is this space remembered as traversable?

How much clearance does the creature remember here?

What connections does the creature believe exist?

What is unknown?

What geometry revision produced this navigation information?
```

## Important Boundary

Spatial Memory does not:

```text
inspect live voxel geometry
find paths
move the creature
decide whether the creature should hunt
```

It only maintains the creature's internal world model.

---

# 3. Navigation System

## Responsibility

The Navigation system answers:

> **Given what the creature believes about the environment, how can it reach this destination?**

Navigation receives destinations from Behavior and plans routes using Spatial Memory.

For example, Behavior may request:

```text
Move to the last heard noise.

Move toward the target.

Move to this crevice entrance.

Return to this nesting area.
```

Navigation converts that intent into:

```text
destination
    ↓
remembered navigation graph
    ↓
path
    ↓
waypoints
    ↓
movement intent
```

Navigation does not decide why a destination is important.

## Remembered Geometry, Not Actual Geometry

Strategic path planning is performed against:

```text
Spatial Memory
```

rather than:

```text
live voxel terrain
```

This is essential to the creature's imperfect knowledge.

If the player creates a shortcut that the creature has never seen, Navigation cannot use that shortcut simply because it exists.

Likewise, if the creature remembers a passage that has changed, it may attempt to use the obsolete route.

## Local Reality Checking

Although strategic planning uses remembered geometry, immediate physical movement still interacts with real physics.

The creature therefore cannot walk through a newly created obstruction merely because it remembers the route as clear.

When Navigation encounters a contradiction, it reports:

```text
My expected geometry appears to be wrong here.
```

It does **not** update Spatial Memory itself.

Instead it requests a geometry observation from Perception.

The resulting loop is:

```text
Navigation
    │
    │ expectation mismatch
    ▼
Perception
    │
    │ observe actual geometry
    ▼
Spatial Memory
    │
    │ update belief
    ▼
Navigation
    │
    └── replan
```

## Important Boundary

Navigation knows:

```text
destination
remembered geometry
current path
movement feasibility
```

It does not know:

```text
why the creature is hunting
how suspicious the creature is
why the Director wants disengagement
whether a noise is interesting
```

---

# 4. Aggression System

## Responsibility

The Aggression system answers:

> **Given the creature's evidence about the players, how interested or committed should it be?**

Perception describes observations.

Aggression interprets those observations over time.

This distinction is important.

A sound with strength `0.7` is sensory information.

The consequences of repeatedly receiving strong sounds are psychological/behavioral information:

```text
suspicion increasing
confidence increasing
player becoming compelling
hunt commitment increasing
```

Those belong to Aggression.

## Inputs

Aggression receives player-related observations from Perception.

Examples:

```text
NoiseObservation
VisionObservation
TouchObservation
```

It may maintain information both globally and per player.

For example:

```text
Creature

overall suspicion: 0.68


Player 1

hearing evidence:     0.72
visual evidence:      0.00
contact evidence:     0.00
interest:             0.65
last evidence age:    1.4 sec


Player 2

hearing evidence:     0.20
visual evidence:      0.35
contact evidence:     0.00
interest:             0.31
last evidence age:    3.2 sec
```

## Accumulation and Decay

Aggression persists beyond individual perception events.

For example:

```text
loud noise
    ↓
suspicion increases

another noise
    ↓
suspicion increases further

no evidence
    ↓
suspicion gradually decays
```

This creates continuity between individual sensory observations.

A player does not become completely unknown the instant they stop making noise.

## Target Evidence

Aggression should calculate how compelling each player currently appears.

This can combine:

```text
hearing evidence
vision evidence
touch evidence
recency
existing commitment
```

It does not necessarily decide which player the creature ultimately pursues.

Instead it provides Behavior and the Director with information such as:

```text
Player 1 interest: 0.76

Player 2 interest: 0.42

overall suspicion: 0.81

last credible target position: ...
```

## Important Boundary

Aggression determines:

```text
how strong the creature's interest is
```

but does not determine:

```text
what animation to play
where to navigate
whether the encounter has lasted too long
which HFSM state should execute
```

Those belong to Behavior.

---

# 5. Behavior System

## Responsibility

The Behavior system answers:

> **Given what the creature currently believes, what should it do?**

Behavior contains the high-level creature state machine and the Director.

Its inputs primarily come from:

```text
Aggression
Spatial/target context
Navigation status
Director encounter state
```

Its outputs primarily go to:

```text
Navigation
animation/gameplay actions
```

The core HFSM remains intentionally small:

```text
UNALERTED
     │
     ▼
INVESTIGATING
     │
     ▼
HUNTING
     │
     ▼
RETREATING
```

Behavior uses Aggression to decide when those modes are appropriate.

For example:

```text
low aggression
    → remain territorial

moderate aggression
    → investigate evidence

high aggression
    → hunt

forced disengagement
    → retreat
```

---

# Director

The Director is part of the Behavior system because it affects **what behavior should happen**, rather than what the creature perceives or remembers.

However, it operates at a different level from the creature HFSM.

The HFSM answers:

> What does the creature logically want to do?

The Director answers:

> What should happen to make this a good horror encounter?

That difference is intentional.

## Menace and Encounter Pacing

The Director maintains an encounter-level pressure measurement such as:

```text
menace
```

Menace may rise based on:

```text
time spent hunting
creature/player proximity
short navigation distance
visual contact
sustained chase pressure
```

When the encounter has delivered sufficient pressure, the Director may request disengagement:

```text
HUNTING
    │
    │ Director: force_disengage
    ▼
RETREATING
```

This can occur even when Aggression says the creature still has strong evidence of the player.

The Director therefore provides a game-design override to otherwise logical creature behavior.

---

# Multiplayer Target Selection

The Director also handles final target selection.

Aggression provides values such as:

```text
Player 1 interest = 0.71
Player 2 interest = 0.62
```

The Director converts those scores into a stable behavioral decision.

For example:

```text
current target = Player 1

Player 2 becomes slightly louder.

0.71 vs 0.74

→ remain on Player 1
```

But:

```text
Player 2 suddenly drills nearby.

0.52 vs 0.95

→ switch to Player 2
```

Target stickiness therefore belongs in the Behavior/Director layer rather than Perception or Aggression.

Perception reports evidence.

Aggression evaluates its significance.

The Director decides whether that difference is important enough to change the current encounter.

---

# Dependency Graph

The primary dependency direction is:

```text
                          ┌──────────────┐
                          │    WORLD     │
                          │              │
                          │ Players      │
                          │ Terrain      │
                          │ Physics      │
                          │ Noise        │
                          └──────┬───────┘
                                 │
                                 ▼
                         ┌───────────────┐
                         │  PERCEPTION   │
                         └───────┬───────┘
                                 │
                   ┌─────────────┴─────────────┐
                   │                           │
          geometry observations        player evidence
                   │                           │
                   ▼                           ▼
          ┌────────────────┐          ┌────────────────┐
          │ SPATIAL MEMORY │          │   AGGRESSION   │
          └───────┬────────┘          └───────┬────────┘
                  │                           │
                  │ remembered                │ interest /
                  │ geometry                  │ suspicion
                  ▼                           ▼
          ┌────────────────┐          ┌────────────────┐
          │   NAVIGATION   │◄─────────│    BEHAVIOR    │
          └───────┬────────┘ commands └───────┬────────┘
                  │                           │
                  │                     ┌─────┴─────┐
                  │                     │           │
                  │                    HFSM      Director
                  │
                  ▼
             ┌──────────┐
             │ MOVEMENT │
             └────┬─────┘
                  │
                  ▼
                WORLD
```

There is one deliberate feedback loop:

```text
┌──────────────┐
│  NAVIGATION  │
└──────┬───────┘
       │
       │ "expected geometry does not
       │  match physical reality"
       ▼
┌──────────────┐
│  PERCEPTION  │
└──────┬───────┘
       │
       │ new geometry observation
       ▼
┌────────────────┐
│ SPATIAL MEMORY │
└──────┬─────────┘
       │
       │ remembered geometry changed
       ▼
┌──────────────┐
│  NAVIGATION  │
└──────────────┘
```

This feedback should occur through narrow messages or interfaces rather than allowing Navigation to edit Spatial Memory directly.

---

# Dependency Rules

The following dependencies are allowed:

```text
Perception → actual World

Spatial Memory ← Perception

Aggression ← Perception

Navigation → Spatial Memory

Behavior → Aggression

Behavior → Navigation

Director → Aggression

Director → Navigation metrics

Movement ← Navigation

Navigation → Perception
    only through geometry-validation requests
```

The following dependencies should be prohibited:

```text
Perception → Behavior
Perception → HFSM state changes

Perception → Navigation paths

Spatial Memory → actual terrain

Spatial Memory → Behavior

Aggression → Navigation

Aggression → HFSM transitions

Navigation → Aggression

Navigation → direct Spatial Memory mutation

Movement → Behavior

Terrain destruction → direct Spatial Memory updates
```

The last rule is particularly important.

A player destroying terrain changes the **World**, not the creature's knowledge.

Only Perception can convert that change into knowledge.

---

# Information Flow Example

A complete encounter might proceed like this:

```text
1. Player begins drilling.

WORLD
    ↓

2. Hearing observes loud noise.

PERCEPTION
    ↓

3. Aggression increases suspicion toward Player 1.

AGGRESSION
    ↓

4. Suspicion passes the investigation threshold.

BEHAVIOR
    INVESTIGATING
    ↓

5. Behavior requests movement toward the remembered
   noise position.

NAVIGATION
    ↓

6. Navigation plans using Spatial Memory.

SPATIAL MEMORY
    ↓
NAVIGATION
    ↓

7. Creature approaches but encounters an opening
   where it remembered a wall.

WORLD
    ↓
NAVIGATION detects mismatch
    ↓

8. Navigation requests local geometry validation.

PERCEPTION
    ↓

9. Perception observes the player-created tunnel.

SPATIAL MEMORY
    ↓

10. Memory updates and Navigation replans.

NAVIGATION
    ↓

11. New noises increase aggression further.

AGGRESSION
    ↓

12. Behavior enters HUNTING.

BEHAVIOR
    ↓

13. Director selects Player 1 as the stable target
    and tracks encounter menace.

DIRECTOR
    ↓

14. Hunt continues until menace reaches its pacing
    limit.

DIRECTOR
    ↓

15. Behavior enters RETREATING.

BEHAVIOR
```

No individual system needs to understand that entire sequence.

Each system performs one specific part of the reasoning.

---

# Architectural Principle

The complete architecture can be summarized as:

```text
Perception:
    What do I observe?

Spatial Memory:
    What do I remember about the world?

Aggression:
    How much do I care about the evidence?

Behavior:
    What am I going to do?

Director:
    What should happen for the encounter?

Navigation:
    How do I get there based on what I remember?

Movement:
    What can my body actually do right now?
```

The separation is especially important for the horror experience because it creates different kinds of imperfection.

The creature can:

* **fail to perceive something,**
* **remember obsolete geometry,**
* **have weak evidence of a player,**
* **commit to the wrong target,**
* **choose a reasonable action based on incorrect information,**
* or **discover that its planned route no longer matches reality.**

Those failures are not exceptions to the AI architecture. They are a major part of the intended behavior.

The creature feels intelligent not because it has perfect information, but because it consistently **observes, remembers, evaluates, decides, acts, and revises its beliefs when reality contradicts them.**
