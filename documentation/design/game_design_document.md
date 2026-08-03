---
title: Untitled Zero-G Asteroid Horror Game Design Document
layout: page
published: true
---

> **The source of truth is the Google Doc:**
> <https://docs.google.com/document/d/1GpNiWQcfUk_kKqcb8EJSyjm_tjR9KshUHC0uEmROzFI/edit>
>
> ⚠ **This file is currently AHEAD of the Doc.** Revision 0.0.2 has not been pasted
> up yet. Paste it over the Doc, then this file is a mirror again and future edits
> belong in the Doc.

# Untitled Zero-G Asteroid Horror Game Design Document

## Back in the Game Jam

Revision: 0.0.2

Source: Design kickoff call, 2026-07-31 (~3 hrs, Discord voice, transcribed)

License

Copyright © Jonathan, Dylan, Sean, Steven, Michael, AJ, Nestor 2026 - Present

- [Untitled Zero-G Asteroid Horror Game Design Document](#untitled-zero-g-asteroid-horror-game-design-document)
  - [Back in the Game Jam](#back-in-the-game-jam)
  - [Overview](#overview)
    - [Theme / Setting / Genre](#theme--setting--genre)
    - [Targeted platforms](#targeted-platforms)
    - [Project _**scope**_](#project-scope)
    - [Design Pillars](#design-pillars)
    - [MVP Definition](#mvp-definition)
    - [Out of Scope](#out-of-scope)
    - [Stretch Goals — need an owner](#stretch-goals--need-an-owner)
    - [Influences](#influences)
    - [The Elevator Pitch](#the-elevator-pitch)
    - [What sets this project apart?](#what-sets-this-project-apart)
  - [Story and Gameplay](#story-and-gameplay)
    - [Story Brief](#story-brief)
    - [Core Gameplay Mechanics Brief](#core-gameplay-mechanics-brief)
    - [Core Gameplay Mechanics](#core-gameplay-mechanics)
    - [Gameplay Brief](#gameplay-brief)
    - [Gameplay](#gameplay)
  - [AI](#ai)
    - [The experience the AI must produce](#the-experience-the-ai-must-produce)
    - [Creature Behavior](#creature-behavior)
    - [Creature Movement](#creature-movement)
  - [Assets](#assets)
    - [3D](#3d)
    - [Textures and Shaders](#textures-and-shaders)
    - [Audio](#audio)
    - [HUD Elements](#hud-elements)
    - [Code](#code)
  - [Pipeline](#pipeline)
  - [Prototyping Plan](#prototyping-plan)
  - [Open Questions — Answered by Prototyping](#open-questions--answered-by-prototyping)
  - [Open Questions](#open-questions)

## Overview

### Theme / Setting / Genre

- Themes: isolation, scarcity, disorientation, cosmic horror
- No theme was issued by the jam organizers. We build the game first and retrofit a theme afterward.
- Setting: a mining crew parks outside a large asteroid and EVAs into the cave system inside it. Something already lives in there.
- Genre: 3D first-person zero-gravity co-op survival horror
- Tone: cosmic horror. Less whimsical than Lethal Company. Caves, not facilities.

### Targeted platforms

- [x] PC — settled, not an open question

### Project _**scope**_

- **Game Time Scale**

  - **2.5 weeks total. Deadline: August 20th.** Settled — not an open question.
  - Target session length: **~5 minutes** per run

- **Player count**

  - Must be good solo. Solo is not a fallback, it is a first-class experience.
  - Multiplayer target is **2 players**
  - **Networked only. There is no local multiplayer.** Settled — not an open question.

- **Hard technical pillars — both slots are now filled**

  - **Committed: networked multiplayer.**
  - **Committed: enemy AI.** There is exactly one creature and the player cannot fight it,
    so the AI has nothing to hide behind. It has to produce a specific player experience on
    its own. See [AI](#ai).
  - Destructible voxel terrain and procedural terrain generation are **stretch goals**,
    not pillars. See [Stretch Goals](#stretch-goals--need-an-owner). With both pillar slots
    committed, they do not enter scope on enthusiasm — only on a named owner.
  - Everything else stays cheap.

- **Core team members**

  - Jonathan Lewis - Technical direction, pipeline, **owns enemy AI** (committed pillar)
  - Dylan (Antic) - 3D art, art direction, project documentation
  - Sean - 3D art, art direction, technical/AI consulting (will not own AI)
  - Steven - Game design lead, early prototyping
  - Michael - Programming (wants network code; first game jam)
  - AJ - Art implementation
  - Nestor Tomaselli - Concept art, art direction, animation (motion design, low-poly 3D, Rive/Lottie)
  - Damien - Game design, Level Design
  - Chris (Waterytart) - Sound Designer
  - Ryan Lemon - Composer
  - Lindsay - observer, not a contributor

- **Availability constraints**

  - Sean is traveling Aug 1 - 9. Evenings only, mornings and lunch for check-ins. Tag him on Discord.
  - Damien may not be available for the second week. Availability and timeframe to be confirmed.

### Design Pillars

1. **You are never the powerful thing in the room.** No weapons that solve problems.
   Tools buy time, create distance, or make noise. The player's only real advantages
   are patience and information.
2. **Scarcity is the antagonist; the creature is the punctuation.** The horror budget
   is spent on environment, resource pressure, darkness, and sound _first_. The creature
   raises the stakes on systems that are already tense on their own. If the creature were
   removed entirely, a run should still be unpleasant in the right way.
3. **Zero-G is a liability, not a superpower.** Floating removes precision, orientation,
   and the ability to put your back against something. Disorientation is a feature. The
   one thing that feels at home here is the thing hunting you.
4. **Every convenience costs something shared.** Light, digging, and breathing all draw
   from one box that somebody has to carry and somebody has to crank. Comfort for one
   player is a bill paid by the group.
5. **Five minutes, fully felt.** Short runs with real dead air in them. Silence is
   content. Nothing gamey competes with the build-up — no card draws, no upgrade popups,
   no tutorial overlays. They dissolve immersion faster than anything else on the list.

### MVP Definition

A single asteroid. One creature. Five minutes.

**The test:** if a player finishes a run having been scared twice, and having decided at
least once to leave loot behind, the MVP works.

**In:**

- Zero-G first-person movement through a tunnel system
- Restricted vision (whichever sense model wins)
- Minable ore nodes with noise consequences and physical chunk retrieval
- Shared power/oxygen box: power, tether, crank
- One creature with patrol / investigate / hunt behavior
- Return-to-ship extraction and score tally
- Two-player networked co-op, fully playable solo

### Out of Scope

Decided, not open. Do not spend time here and do not reopen without a scope conversation.

- **Local / couch multiplayer.** Networked only.
- **Magnetic boots.** Players float, permanently.
- **Local gravity anomaly zones.** Same.
- Ship-flying / exterior traversal loop — the asteroid interior is the game
- Upgrades, meta-progression, currency, any run-to-run persistence
- Multiple asteroids or multiple creature types
- More than two players as a design target — if 3–4 happens to work, fine; it is not a goal
- Combat of any kind. The creature cannot be killed, damaged, or driven off permanently.

### Stretch Goals — need an owner

These are **out of scope until a specific person owns them.** Nothing else in the design
may assume they ship.

| Stretch goal | Owner | If it does not ship |
|---|---|---|
| Destructible voxel terrain (marching cubes, runtime deformation) | **Unassigned** | Tunnels are static geometry. Digging as a mechanic is cut — no self-stranding, no digging to break line of sight, no player-dug confusion. Ore nodes still work; they just stop being carveable. |
| Procedural terrain / cave generation | **Unassigned** | One hand-authored level with randomized ore node placement. This is the cheap option and is likely correct regardless. |

> **Note:** this does **not** affect the art pipeline. Assets are still authored as voxels
> in Goxel and still smoothed with marching cubes at import — see [Pipeline](#pipeline).
> What is stretch here is _runtime destructible terrain_, which is a different system.

### Influences

- Lethal Company
  - Video game
  - Go in, grab loot, get out. Shared-fate co-op tension. The closest structural match.
- Alien: Isolation
  - Video game
  - One unkillable stalker. Hiding rather than fighting. Reference for **feel and craft** — match the experience, not the architecture. See [AI](#ai).
- Deep Rock Galactic
  - Video game
  - Cave mining loop, voxel terrain, first-person team play. We take the loop, not the power fantasy.
- Subnautica
  - Video game
  - Oxygen as horror, open space as horror, sound stings that scare you for no reason.

### The Elevator Pitch

Lethal Company in zero gravity. You and a friend EVA into an asteroid, mine it for score, and share one hand-cranked power supply while something that lives in the tunnels hunts you.

### What sets this project apart?

- Zero-G first-person horror. Losing your sense of up and down while panicking is unique.
- Life support is a physical object. One shared power/oxygen box, carried, cranked by hand, on a tether.
- No combat. The creature cannot be killed or driven off. Tools only buy time.
- (stretch, if terrain gets an owner) The terrain is deformable, which means it can save
  you and it can trap you.
- Horror is produced by the environment, resource pressure and sound first, and by creature AI second.

## Story and Gameplay

### Story Brief

- A crew takes a contract to strip a large asteroid in a belt.
- The valuable material is deep inside the cave system, so the ship parks outside and the crew EVAs in.
- Something already lives in the tunnels, and mining disturbs it.
- Story was deliberately left thin at kickoff. Nothing about the crew, employer or creature origin is locked.

### Core Gameplay Mechanics Brief

- Power is the master resource. It is shared, physical, carried, and it runs out.
- Mining generates score, generates noise, and makes you a target.
- The player cannot fight. The player can hide, run, dig, and manage what they can see and hear.

### Core Gameplay Mechanics

- **Movement**

  - First person, zero gravity, six degrees of freedom
  - Newtonian physics with personal thrusters
  - Collider has limbs to make complex collisions more likely, spinning the player. Players will bump into walls constantly and that is fine.
  - Disorientation is an intended horror tool, but the player still needs to feel a floor of control
  - (test) Oxygen-based thrusting: spend air to move. Breathe or move, pick one.
  - (open) Pushing off walls, grapple / tool-based traversal
  - Magnetic boots and gravity anomaly zones are **out of scope.** Players float, permanently.

- **Power and Oxygen**

  - A single shared box carries **both** power and oxygen for the whole crew
  - The box is carried by a player and limits movement (heavy, slow)
  - A tether connects players to the box and caps how far anyone can get from it
  - The box has a hand crank / manual generator. Cranking restores power.
  - Cranking is **loud**. It attracts the creature.
  - Power continuously converts into oxygen. Each player has their own oxygen value.
  - No power, personal oxygen begins draining
  - Power also runs lights and tools, so every drain competes with every other drain
  - The player can cut the tether and run. This is a real option with a real cost.
  - (stretch / decide) Environmental oxygen nodes / pockets to top up once you have cut loose
  - (stretch / decide) A player can voluntarily power down their own equipment to give a teammate in danger more headroom

- **Mining**

  - Mining tool runs on shared power
  - Mining is loud
  - Ore breaks off nodes and **flings and bounces down tunnels** in zero-G. You have to go get it.
  - Mined ore must be physically carried back
  - Carrying loot occupies you. No digging and no throwing light while your hands are full.
  - Ore converts to **score** at extraction

- **Digging / Deformable Terrain** — **STRETCH. Unowned. Assume it does not ship.**

  - Terrain is voxel-based and can be carved with the mining tool
  - Digging costs power, so you can strand yourself mid-tunnel with a dead tool
  - Digging can only get you so far. It must never be a free escape.
  - Digging can make the tunnel network more confusing, including for the player who dug it
  - (test) Turning off your lights frees up power for more digging, so you dig blind
  - If this does not get an owner, tunnels are static and every bullet above is cut.
    Nothing else in the design may depend on digging.

- **Senses**

  - Vision distance is deliberately short. Light is a resource.
  - Sound carries information: mining, cranking, the creature, teammates
  - (open) A second sense to lean on: proximity radar, echolocation/visor shader, or something else. **This is the hook and it is not chosen yet.**
  - (stretch) Consumable light sources, e.g. glow sticks

- **The Creature**

  - Exactly **one** creature
  - Cannot be killed. Cannot be shot. Tools at best buy time.
  - Amorphous black mass. Body can be as simple as a sphere.
  - Ignores the fact that there is no gravity. This is its home and the player is the visitor.
  - Not present at spawn. The first stretch of a run is quiet on purpose.
  - Behavior, perception and locomotion are specified in [AI](#ai).

- **The Ship**

  - The ship is **absolute safety for the player.** No threat can reach you aboard. It is
    the only place the tension releases.
  - **(open)** Whether the creature can damage the ship while players are inside. The
    intent is that sitting in the ship indefinitely is not a valid strategy — the player
    should be safe in there, but not free. Mechanism undecided.
  - Flying the ship is out of scope. It is a parked extraction point.

- **Objective and Progression**

  - Objective is **score**. Mine as much as you can and get out alive.
  - If any upgrade ever ships, it must be temporary or consumable, and must buy **time** rather than safety
  - Difficulty must escalate within a single run

- **Multiplayer**

  - Designed single-player first. Must play well multiplayer as well.
  - **Networked only. No local multiplayer.** Target: 2 players.
  - Everyone has identical capabilities, no classes or loadouts.

### Gameplay Brief

The crew's ship parks outside an asteroid. Players EVA into the cave system carrying a single power-and-oxygen box on a tether. They mine ore for score while power drains, light fails, and one creature that cannot be killed works its way toward the noise they are making. They carry what they can back to the ship before something runs out.

### Gameplay

- [ ] Player spawns outside the asteroid, near the ship
- [ ] Player enters the cave system via EVA
- [ ] Player moves in zero-G through tight tunnels
- [ ] Player carries the shared power/oxygen box, or is tethered to the player who is
- [ ] Power drains over time; oxygen is generated from power
- [ ] Player locates an ore node
- [ ] Player mines the node; mining makes noise
- [ ] Ore fragments scatter and must be chased down and collected
- [ ] Player carries ore, which prevents using other tools
- [ ] Player cranks the box to restore power; cranking makes noise and pins them in place
- [ ] Noise raises the creature's awareness
- [ ] Creature enters a hunting state and navigates toward the player
- [ ] Player hides or runs to break line of sight (or digs, if deformable terrain ships)
- [ ] Player may cut the tether to escape, at the cost of shared life support
- [ ] Player returns ore to the ship
- [ ] Ore is converted to score
- [ ] Run ends on extraction, death, or resource exhaustion

## AI

**Owner: Jonathan Lewis.** Sean consults but does not own this.

**Enemy AI is a committed hard technical pillar.** There is exactly one creature, it cannot
be killed, and the player has no combat verbs. That means the AI carries the entire threat
of the game by itself — there is no second enemy type, no wave pacing, and no weapon
feedback loop to cover for it. A single creature that behaves poorly is not a rough edge;
it is the game failing.

This reverses the kickoff position, which treated the AI as deliberately modest on the
argument that a crude monster in a well-built environment beats a clever monster in an
empty one. That argument holds for _how much machinery_ the AI needs. It does not hold for
_how well-crafted_ the one creature has to be. Budget is allocated accordingly.

### The experience the AI must produce

The AI is judged against the player's experience, not against its own sophistication. It
has to make the player:

- **Afraid to make noise.** Mining and cranking must feel like decisions with consequences,
  not like free actions.
- **Uncertain whether it heard them.** The gap between "I made a noise" and "something is
  coming" is where the tension lives.
- **Willing to abandon loot.** Per the [MVP test](#mvp-definition), a run works if the
  player leaves something behind at least once.

If it is legible enough to be gamed, or random enough to feel unfair, it has failed —
even if every state transition works exactly as specified.

Reference Alien: Isolation for **feel**. Match its craft, not its architecture.

### Creature Behavior

A three-state machine with raycast vision is the **starting architecture, not the ceiling.**
It is the cheapest thing that can produce the experience above; if tuning it cannot get
there, the architecture escalates rather than the standard dropping. Most of the budget
here should go into perception, timing and tells — not into more states.

Three states:

```
  PATROL ──(noise heard)──► INVESTIGATE ──(player seen)──► HUNT
     ▲                            │                          │
     └──────(timeout)─────────────┴──────(lost player)───────┘
```

- **PATROL** — default. Not present at spawn; the opening stretch of a run is quiet on purpose.
- **INVESTIGATE** — triggered by noise, not by sight. Mining, cranking and thrusters are the
  noise sources. Moves toward the source.
- **HUNT** — triggered by line of sight on a player. Pursues.
- Falls back on a timeout (investigate → patrol) or on losing the player (hunt → investigate).

Noise is routed through a single **Noise Manager** so there is one source of truth for what
the creature can hear.

**(open)** Detection specifics: what counts as a noise event, detection radius per source,
how noise attenuates with distance, how long each timeout runs.

### Creature Movement

- Moves by shooting out tendrils that grab the walls, driven by procedural animation from
  position. Cheap to animate, expensive-looking, and it sidesteps the fact that Goxel
  produces nothing riggable.
- Unaffected by zero-G. It should read as native to a place the players are obviously
  trespassing in.
- **(open)** Does it wall-crawl, or float and navigate around obstacles? Floating with
  raycast obstacle avoidance is the cheap default. Wall-crawling is meaningfully harder,
  and harder again if destructible terrain ships and the walls can change shape mid-run.
  Decide this before creature implementation starts.

## Assets

### 3D

- [ ] Player character

  - [ ] Suit body (simple, minimal appendages)
  - [ ] Thruster pack
  - [ ] Very limited animation set — no full rig

- [ ] Creature

  - [ ] Core body (sphere or amorphous mass)
  - [ ] Tendrils driven by procedural animation / IK
  - [ ] This is where the animation budget goes; it is what the player looks at

- [ ] Power / Oxygen box

  - [ ] Box body
  - [ ] Hand crank
  - [ ] Tether

- [ ] Tools

  - [ ] Mining tool / drill
  - [ ] Light source
  - [ ] (stretch) Throwable light / glow stick

- [ ] Ore

  - [ ] Ore node (in-wall, large)
  - [ ] Ore fragment (collectible, small)

- [ ] Environment

  - [ ] Asteroid cave interior (voxel terrain)
  - [ ] Asteroid exterior
  - [ ] Cave dressing to signal where things are worth doing
  - [ ] (stretch) Oxygen pocket / bubble node

- [ ] Ship

  - [ ] Exterior, parked outside the asteroid
  - [ ] Minimal interior / extraction point

### Textures and Shaders

- [ ] Voxel material set, smoothed via marching cubes
- [ ] Low fidelity, high output. Charming, not ugly, not obviously slapped together.
- [ ] Limited vision / draw distance treatment (fog, falloff, or visor)
- [ ] (open) Echolocation or outline shader, if that becomes the sense hook
- [ ] Player light / headlamp falloff

### Audio

Sound design matters more than music on this project. **Ownership is not yet confirmed** —
Chris is tentative and Dylan is chasing it. Ryan Lemon is secured as composer.

- [ ] Ambience — cave, hull creak, distance
- [ ] Mining loop (loud, diegetic, attracts the creature)
- [ ] Crank loop (loud, diegetic, attracts the creature)
- [ ] Thruster / movement
- [ ] Breathing and oxygen warnings
- [ ] Creature vocalizations and movement — pitched-down animal recordings are on the table
- [ ] False-alarm stingers with no source, Subnautica-style
- [ ] Music — composer secured, layered/reactive approach TBD

### HUD Elements

Keep it minimal. Readouts should be imperfect and diegetic where possible.

- [ ] Oxygen (per player)
- [ ] Power (shared box)
- [ ] Score / ore carried
- [ ] Tether state and distance
- [ ] Creature proximity indicator (only if the radar sense is chosen)
- [x] ~~Creature health bar~~ :_**scope**_ — it cannot be killed

### Code

- [ ] Player Scripts

  - [ ] Zero-G controller (6DOF, Newtonian; collider shape unresolved — Movement says
        limbed, this said capsule. Pick one.)
  - [ ] Stats (oxygen, carry state)
  - [ ] State machine
  - [ ] Tool handling (mine, carry, light, crank)

- [ ] Creature Scripts

  - [ ] Behavior state machine (patrol / investigate / hunt) — see [AI](#ai)
  - [ ] Perception (raycast vision, noise events)
  - [ ] Zero-G navigation
  - [ ] Procedural tendril animation

- [ ] Resource Scripts

  - [ ] Power/oxygen box (shared pool, crank input, conversion)
  - [ ] Tether (distance constraint, cut)
  - [ ] Ore node and ore fragment

- [ ] Terrain Scripts — **STRETCH, unowned.** Baseline is static authored geometry.

  - [ ] (stretch) Voxel volume
  - [ ] (stretch) Marching cubes meshing at runtime
  - [ ] (stretch) Deformation on mining
  - [ ] (stretch) Procedural cave generation

- [ ] Ambient Scripts (runs in the background)

  - [ ] Game State Manager
  - [ ] Level Manager
  - [ ] Noise Manager — single source of truth for what the creature can hear
  - [ ] Audio Manager
    - [ ] SFX Manager
    - [ ] Music Manager
  - [ ] Score Manager

- [ ] Multiplayer — networked only, no local path to build

  - [ ] Session setup
  - [ ] Authority model (player 1 authoritative is acceptable)
  - [ ] Replication of player, box, ore, creature

## Pipeline

- Engine: **Godot**
- Art authored in **Goxel** — voxel modeling, chosen so both artists work in the same tool and the style aligns automatically. New tool for both of them.
- Export format: **GLTF**
- Marching cubes smoothing happens in **Godot**, not in Goxel. (Dylan is chasing a Goxel JS plugin that gives a live smoothed preview; if it works, artists see the final look without leaving the tool.)
- **No Blender round-trip.** Extra hops cost time exactly when time is scarcest, and make reverting decisions expensive.
- **No Mixamo.**
- Goxel cannot set an origin. Convention: origin at the feet / bottom, centered in world, with a known facing direction. Jonathan can automate corrective transforms on import in Godot rather than fixing them by hand.
- First pipeline task: artists export a real asset made in their own workflow (not a downloaded model) and send it to Jonathan so the import path can be nailed down.
- Repo: Jonathan's Godot template, plus a commit with structure and examples. Steven is already committing prototype code.
- Art requests get tracked as a prioritized **bounty board** so anyone can pick work up.
- Art direction lives on the **Miro board**. Anyone can add references; Dylan and Sean hold final say, with Nestor consulting.
- Deliverable before assets: a **mood board**, so engineering can compare its assumptions against where art is heading.

## Prototyping Plan

Owned by Steven, in priority order. The point of each prototype is to answer one question.

1. **Zero-G first-person movement in tight spaces.** Does it feel good? Does the player retain enough agency while being deliberately disoriented?
2. **Senses.** Light, vision distance, noise, possible radar. Which one is the hook?
3. **Risk / reward of going deeper.** Does the pull to push further actually work?
4. **The tethered power/oxygen box.** Is dragging it scary, or just annoying? This is the biggest single risk in the design.
5. **The creature.** Gray box, later. Jonathan starts creature behavior in parallel.

Mining is explicitly **not** an early prototype. Substitute "collect the thing" until the horror loop works.

## Open Questions — Answered by Prototyping

These get resolved by building something, not by discussing them. Every one has an owner.

| # | Question | Blocks | Owner |
|---|---|---|---|
| 1 | Does zero-G movement in tight spaces feel good, or merely bad? Does the player keep enough agency while being deliberately disoriented? | Everything. This is prototype #1. | Steven |
| 2 | Which sense is the hook — light, proximity radar, echolocation/visor shader, or sound? | Art load, shader work, level readability | Steven |
| 3 | Is hauling the tethered power/oxygen box scary, or just annoying? | The entire shared-resource pillar | Steven |
| 4 | Does the risk/reward pull of going deeper actually work? | Level layout, ore distribution, run pacing | Steven |
| 5 | Creature detection specifics — what counts as noise, radius per source, attenuation, timeouts | AI implementation | Jonathan Lewis (Sean consults) |
| 6 | Does the creature wall-crawl, or float and navigate around obstacles? | AI complexity, and much harder if destructible terrain ships | Jonathan Lewis |
| 7 | Does thrust consume breathable air (move or breathe, pick one)? | Movement and resource model both | Steven |
| 8 | What is the in-run difficulty ramp across 5 minutes? | Pacing | Steven |
| 9 | Can the creature damage the ship while players shelter inside, and how? | Whether camping the ship is a valid strategy | **Needs an owner** |

## Open Questions

Not prototyping questions — these are decisions, staffing, or naming.

- [ ] Sound designer — Chris is tentative, Dylan to confirm
- [ ] Does destructible voxel terrain get an owner? Until it does, it stays out of scope.
- [ ] Does procedural cave generation get an owner? Same. Baseline is one hand-authored
      level with randomized ore node placement.
- [ ] Player collider shape — limbed (per Movement) or capsule (per Code)
- [ ] Game title, team name, and the theme we retrofit

**Settled since revision 0.0.1** — do not reopen without a scope conversation: jam deadline
(2.5 weeks, Aug 20) · networked vs local multiplayer (networked only) · mag boots and
gravity anomalies (out of scope) · target platform (PC).
