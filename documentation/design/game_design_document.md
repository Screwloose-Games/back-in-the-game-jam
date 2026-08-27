---
title: Untitled Zero-G Asteroid Horror Game Design Document
layout: page
published: true
---

> **The source of truth is the Google Doc:**
> <https://docs.google.com/document/d/1GpNiWQcfUk_kKqcb8EJSyjm_tjR9KshUHC0uEmROzFI/edit>
>
> ⚠ **Revision 0.0.3 is pending paste-up.** The Doc is still at 0.0.1, two revisions behind.
> The paste buffer is `Untitled Zero-G Asteroid Horror Game Design Document.md` in this
> directory — edit that file, paste it over the Doc, then delete this note and the buffer,
> and this file is a plain mirror again.

# Untitled Zero-G Asteroid Horror Game Design Document

## Back in the Game Jam

Revision: 0.0.3

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
    - [Stretch Goals — need an owner](#stretch-goals--need-an-owner)
    - [Influences](#influences)
    - [The Elevator Pitch](#the-elevator-pitch)
    - [Treatment](#treatment)
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
  - [Out of Scope](#out-of-scope)

## Overview

### Theme / Setting / Genre

- Themes: isolation, scarcity, disorientation, cosmic horror
- No theme was issued by the jam organizers. We build the game first and retrofit a theme afterward.
- Setting: a mining crew parks outside a large asteroid and rides an industrial elevator down into the cave system inside it. Something already lives in there.
- Genre: 3D first-person zero-gravity co-op survival horror
- Tone: cosmic horror. Less whimsical than Lethal Company. Caves, not facilities.

### Targeted platforms

- **Web — the primary performance target.** The build has to be performant enough to actually
  play in a browser, and that budget bounds cave volume, draw distance and prop density for
  everyone else. This matches the web-first GL Compatibility posture the repo already describes
  in `CLAUDE.md`.
- Windows
- Mac

Settled — not an open question. (Revision 0.0.2 recorded this as "PC", which contradicted both
the kickoff notes and the repo. 0.0.3 corrects it.)

### Project _**scope**_

- **Game Time Scale**

  - **2.5 weeks total. Deadline: August 20th.** Settled — not an open question.
  - Target session length: **~5 minutes** per run

- **Player count**

  - Must be good solo. Solo is not a fallback, it is a first-class experience.
  - Multiplayer target is **2 players**
  - **Networked only.** Settled — not an open question.

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

  - Dylan (Antic) - 3D art
  - Sean - 3D art
  - Steven - Game design lead, early prototyping
  - Michael - Network Programming
  - AJ - Art implementation
  - Nestor Tomaselli - Concept art, animation
  - Jonathan Lewis - Technical direction, pipeline, creature AI
  - Damien - Level Design
  - Ryan Burkhart - Sound Designer
  - Ryan Lemon - Composer
 

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
- Shared power/oxygen box: power, tether, crank, carry and park
- One creature with patrol / investigate / hunt behavior
- Return-to-elevator extraction and score tally
- Two-player networked co-op, fully playable solo

### Stretch Goals — need an owner

These are **out of scope until a specific person owns them.** Nothing else in the design
may assume they ship.

| Stretch goal | Owner | If it does not ship |
|---|---|---|
| Destructible voxel terrain (marching cubes, runtime deformation) | **Unassigned** | Tunnels are static geometry. Digging as a mechanic is cut — no self-stranding, no digging to break line of sight, no player-dug confusion. Ore nodes still work; they just stop being carveable. |
| Procedural terrain / cave generation | **Unassigned** | One hand-authored level with hand-placed ore nodes. This is the cheap option and is likely correct regardless. |

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

Lethal Company in zero gravity. You and a friend ride a mining elevator into an asteroid, strip it for score, and share one hand-cranked power supply while something that lives in the tunnels hunts you.

### Treatment

_The elevator cage shudders to a halt and the gate rattles back onto nothing at all. Ahead of you — below, above, the distinction stops meaning anything the second you push off — is the abnormally mineral-rich dark your scanners picked up from several clicks away. The car's floodlights reach a few metres past the gate and then give up, catching the small openings of several winding tunnels burrowing into the rock. Tethering yourself to your portable life support system, you turn its crank and wince at the grinding, metallic noise. The support system whirs to life with a low droning buzz as you bring it up to full power before grabbing its handholds and pushing it out of the car ahead of you. Your mining tool lags behind you on its own tether as you pass the precipice into a tight tunnel. You are plunged into darkness. The light from the life support system illuminates some of the surrounding tunnel, revealing a hive-like cave system at odds with your sense of orientation. The faint light of your headlamp catches the glint of a {mineral} node a short ways down one of the split paths and you thrust toward it, your tether unravelling as it keeps you connected to oxygen and power. You reach for your mining tool, a high power laser, and seat it comfortably in your hands, pulling the trigger. A brilliant red beam erupts from the end of the tool, casting the walls red, and bites into the seam around the node, boiling the rock away from it in a shower of glowing grit. The loud scifi buzz of the laser echoes through the tunnels as a faint remnant after you release the trigger and the tunnel goes dark, the {mineral} node floating free of its ruined setting. As if in response to your triumph--as if in response to your noise--another sound echoes faintly from the bowels of the tunnels. A distinctly organic sound. You are not alone here._

### What sets this project apart?

- Zero-G first-person horror. Losing your sense of up and down while panicking is unique.
- Life support is a physical object. One shared power/oxygen box, carried or parked, cranked by hand, on a tether.
- No combat. The creature cannot be killed or driven off. Tools only buy time.
- (stretch, if terrain gets an owner) The terrain is deformable, which means it can save
  you and it can trap you.
- Horror is produced by the environment, resource pressure and sound first, and by creature AI second.

## Story and Gameplay

### Story Brief

- A crew takes a contract to strip a large asteroid in a belt.
- The valuable material is deep inside the cave system, so the ship parks outside and the crew rides the mine elevator down.
- Something already lives in the tunnels, and mining disturbs it.
- Story was deliberately left thin at kickoff. Nothing about the crew, employer or creature origin is locked.

### Core Gameplay Mechanics Brief

- Power is the master resource. It is shared, physical, carried, and it runs out.
- Mining generates score, generates noise, and makes you a target.
- The player cannot fight. The player can hide, run, and manage what they can see and hear — and dig, if destructible terrain gets an owner.

### Core Gameplay Mechanics

- **Movement**

  - First person, zero gravity, six degrees of freedom
  - Newtonian physics with personal thrusters
  - Collider has limbs to make complex collisions more likely, spinning the player. Players will bump into walls constantly and that is fine.
  - Disorientation is an intended horror tool, but the player still needs to feel a floor of control
  - Thrust spends **personal breathable air, but only while untethered.** Tethered, thrust
    draws from the box. Cutting loose therefore turns every manoeuvre into an air cost —
    move or breathe, pick one.
  - Thrust is **loud**, and it is a noise source from the first second of a run. There is no
    silent way to travel.
  - (open) Pushing off walls, grapple / tool-based traversal

- **Power and Oxygen**

  - A single shared box carries **both** power and oxygen for the whole crew
  - The box can be **carried or parked.** Carried, it is heavy and slows whoever has it.
    Parked, it stays where it was left. Where you set it down is a real decision.
  - A tether connects players to the box and caps how far anyone can get from it. **Parked,**
    that radius is a fixed leash anchored to one point, and it bounds how far into a branch
    anyone can push. **Carried,** the radius travels with the crew and bounds only how far a
    second player can range from the carrier — solo, it bounds nothing.
  - The box has a hand crank / manual generator. Cranking restores power.
  - Cranking is **loud**. It attracts the creature.
  - The crank is on the box, so a parked box is also the place you have to swim back to when
    power runs low.
  - Power continuously converts into oxygen. Each player has their own oxygen value.
  - No power, personal oxygen begins draining
  - Power also runs lights and tools, so every drain competes with every other drain
  - The player can cut the tether and run. This costs twice — you lose shared life support,
    **and** thrusting untethered starts spending your own air. A real option with a real cost.
  - (stretch / decide) Environmental oxygen nodes / pockets to top up once you have cut loose
  - (stretch / decide) A player can voluntarily power down their own equipment to give a teammate in danger more headroom

- **Mining**

  - Mining tool runs on shared power
  - Mining is loud
  - Ore breaks off nodes and **flings and bounces down tunnels** in zero-G. You have to go get it.
  - Mined ore must be physically carried back
  - Carrying loot occupies you. No digging and no throwing light while your hands are full.
  - Ore converts to **score** at extraction
  - **Ore nodes are hand-placed, not randomized,** with a value gradient by depth: common ore
    near the elevator, the best ore deep in the asteroid. The pull to go deeper is authored.

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
  - Sound carries information: mining, cranking, thrusters, the creature, teammates
  - (open) A second sense to lean on: proximity radar, echolocation/visor shader, or something else. **This is the hook and it is not chosen yet.**
  - (stretch) Consumable light sources, e.g. glow sticks

- **The Creature**

  - Exactly **one** creature
  - Cannot be killed. Cannot be shot. Tools at best buy time.
  - Amorphous black mass. Body can be as simple as a sphere.
  - Ignores the fact that there is no gravity. This is its home and the player is the visitor.
  - **Spawns far from the entrance.** The opening stretch of a run is quiet because the
    creature is a long way off — not because it is absent, and not because the player is
    silent. Thrust is already noise. Distance is what buys the quiet.
  - Behavior, perception and locomotion are specified in [AI](#ai).

- **The Elevator and the Ship**

  - The mine entrance is an **industrial elevator.** A run begins as the player exits the car
    and ends when they return to it. It is the extraction point.
  - The elevator car is **absolute safety for the player.** No threat reaches you inside it.
    It is the only place the tension releases.
  - **(open)** Whether the creature can threaten a player who shelters in the car indefinitely.
    The intent is that camping is not a valid strategy — the player should be safe in there,
    but not free. Mechanism undecided. See open question #9.
  - The ship is parked outside and is where the crew came from. The player does not travel
    to it.

- **Objective and Progression**

  - Objective is **score**. Mine as much as you can and get out alive.
  - If any upgrade ever ships, it must be temporary or consumable, and must buy **time** rather than safety
  - Difficulty must escalate within a single run

- **Multiplayer**

  - Designed single-player first. Must play well multiplayer as well.
  - **Networked only.** Target: 2 players.
  - Everyone has identical capabilities, no classes or loadouts.

### Gameplay Brief

The crew's ship parks outside an asteroid and an industrial elevator carries them down to the mine mouth. Players push off into the cave system with a single power-and-oxygen box on a tether. They mine ore for score while power drains, light fails, and one creature that cannot be killed works its way toward the noise they are making. They carry what they can back to the elevator before something runs out.

### Gameplay

- [ ] Player spawns inside the industrial elevator at the mine entrance
- [ ] Player exits the car into the cave system
- [ ] Player moves in zero-G through tight tunnels
- [ ] Player carries the shared power/oxygen box, parks it, or is tethered to the player who has it
- [ ] Power drains over time; oxygen is generated from power
- [ ] Player locates an ore node
- [ ] Player mines the node; mining makes noise
- [ ] Ore fragments scatter and must be chased down and collected
- [ ] Player carries ore, which prevents using other tools
- [ ] Player cranks the box to restore power; cranking makes noise and pins them in place
- [ ] Noise raises the creature's awareness
- [ ] Creature enters a hunting state and navigates toward the player
- [ ] Player hides or runs to break line of sight (or digs, if deformable terrain ships)
- [ ] Player may cut the tether to escape, at the cost of shared life support and their own air
- [ ] Player returns ore to the elevator
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

- **PATROL** — default. Spawns far from the mine entrance, so the opening stretch of a run is
  quiet by distance rather than by the creature being absent.
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
  - [ ] Parked / deployed state, readable at a distance as "the anchor is here"

- [ ] Tools

  - [ ] Mining tool / drill
  - [ ] Light source
  - [ ] (stretch) Throwable light / glow stick

- [ ] Ore

  - [ ] Ore node (in-wall, large)
  - [ ] Ore fragment (collectible, small)

- [ ] Environment

  - [ ] Asteroid cave interior (voxel terrain)
  - [ ] Cave dressing to signal where things are worth doing
  - [ ] (stretch) Oxygen pocket / bubble node

- [ ] Mine entrance / Elevator

  - [ ] Elevator car interior — spawn point, safe zone, extraction point
  - [ ] Car gate / door
  - [ ] Shaft head where the car meets the mine mouth

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
- [ ] Thruster / movement (loud, diegetic, attracts the creature)
- [ ] Breathing and oxygen warnings
- [ ] Elevator — gate, motor, arrival and departure
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

  - [ ] Power/oxygen box (shared pool, crank input, conversion, carry and park)
  - [ ] Tether (distance constraint, anchored vs carried, cut)
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
4. **The tethered power/oxygen box.** Is dragging it — and choosing where to park it — scary, or just annoying? This is the biggest single risk in the design.
5. **The creature.** Gray box, later. Jonathan starts creature behavior in parallel.

Mining is explicitly **not** an early prototype. Substitute "collect the thing" until the horror loop works.

## Open Questions — Answered by Prototyping

These get resolved by building something, not by discussing them. Every one has an owner.

Numbering is stable — answered questions keep their number rather than being removed, because
the level design briefs cite them by number.

| # | Question | Blocks | Owner |
|---|---|---|---|
| 1 | Does zero-G movement in tight spaces feel good, or merely bad? Does the player keep enough agency while being deliberately disoriented? | Everything. This is prototype #1. | Steven |
| 2 | Which sense is the hook — light, proximity radar, echolocation/visor shader, or sound? | Art load, shader work, level readability | Steven |
| 3 | Is hauling and parking the tethered power/oxygen box scary, or just annoying? | The entire shared-resource pillar | Steven |
| 4 | Does the risk/reward pull of going deeper actually work? | Level layout, ore distribution, run pacing | Steven |
| 5 | Creature detection specifics — what counts as noise, radius per source, attenuation, timeouts | AI implementation | Jonathan Lewis (Sean consults) |
| 6 | Does the creature wall-crawl, or float and navigate around obstacles? | AI complexity, and much harder if destructible terrain ships | Jonathan Lewis |
| 7 | ~~Does thrust consume breathable air (move or breathe, pick one)?~~ **Answered in 0.0.3: yes, but only while untethered.** Tethered thrust draws from the box. | — | Closed |
| 8 | What is the in-run difficulty ramp across 5 minutes? | Pacing | Steven |
| 9 | Can the creature threaten players sheltering in the elevator car, and how? | Whether camping the extraction point is a valid strategy | **Needs an owner** |

## Open Questions

Not prototyping questions — these are decisions, staffing, or naming.

- [ ] Sound designer — Chris is tentative, Dylan to confirm
- [ ] Does destructible voxel terrain get an owner? Until it does, it stays out of scope.
- [ ] Does procedural cave generation get an owner? Same. Baseline is one hand-authored
      level with hand-placed ore nodes.
- [ ] Player collider shape — limbed (per Movement) or capsule (per Code)
- [ ] Game title, team name, and the theme we retrofit

**Settled since revision 0.0.1** — do not reopen without a scope conversation: jam deadline
(2.5 weeks, Aug 20) · networked vs local multiplayer (networked only) · mag boots and gravity
anomalies (out of scope) · target platforms (web is the performance target; Windows and Mac
also ship) · ore placement (hand-placed, value gradient by depth) · mine entrance (an
industrial elevator, with no exterior traversal) · thrust and air (untethered only).

## Out of Scope

Decided, not open. Do not spend time here and do not reopen without a scope conversation.

**This is the only place out-of-scope items are recorded.** If something is out, it is listed
here and nowhere else in this document — no inline notes in the section it affects.

- **Local / couch multiplayer.** Networked only.
- **Magnetic boots.** Players float, permanently.
- **Local gravity anomaly zones.** Same.
- **Exterior traversal.** A run starts and ends at the industrial elevator; the player never
  EVAs across open space. The asteroid-exterior and ship-exterior assets go with it.
- **Ship flying.** The ship is narrative background — not a vehicle, and not a destination.
- Upgrades, meta-progression, currency, any run-to-run persistence
- Multiple asteroids or multiple creature types
- More than two players as a design target — if 3–4 happens to work, fine; it is not a goal
- Combat of any kind. The creature cannot be killed, damaged, or driven off permanently.
