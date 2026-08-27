# Environmental Storytelling, Hazards, and the Clinger

```text
Level: The asteroid
Maturity: LD7 art-direction input, arriving early into an LD4/LD5 level
State: Ready for Review
Owner: unassigned — needs one before any prop is modelled
Last Updated: August 24

Current Review Question:
The mines are the only biome that carries prior-crew wreckage, and `pocket` carries
almost half of it. Is one dense tableau better than five thin ones, or does the level
need wreckage it can find twice?
```

## Purpose

Past the elevator doors, the asteroid is empty rock. The narrative already asserts a
previous crew — the intro's one-frame interference reads `EXTRACTION CREW 066 /
TELEMETRY ENDED: 3/3` — but nothing in the level corroborates it, and nothing except
the stalker can hurt you.

This document specifies three things that turn out to be one thing: **what wreckage
populates the mines**, **what in that wreckage is dangerous**, and **the small creature
that lives in it**. They are written together because the design's best move is to make
the set dressing and the hazard layer the same objects. A burst life-support cube is
scenery until it arcs; then it is a reason to route around a tunnel.

It sits downstream of [the LD0 brief](levels/ld0-asteroid.md) and dresses that beat
spine — it does not replace it.

## The constraint that governs everything below

Web, GL Compatibility, deliberately short draw distance. **Debris reads as a silhouette
in a lamp cone or it does not read at all.** Every prop below is chosen for its outline
at four metres in the dark, and the kit is kept small so those outlines stay learnable.

---

## 1. Health

There is no damage model today. `PlayerLife.die()` is all-or-nothing, and the
creature's `GRACE` verdict resolves to nothing at all. Hazards need somewhere to bill.

**A health pool, 100 points, adjustable.** Slow regeneration over time. Running out of
oxygen drains health rather than killing outright, which turns the suffocation clock
from a cliff into a slope — a bad decision becomes survivable-but-expensive instead of
fatal, and that is the difference between a run the player learns from and a run they
resent.

Specified for whoever builds it:

- `prefabs/character/player/components/player_health.gd`. Signals `damaged`,
  `healed`, `depleted`. At zero it calls the existing `PlayerLife.die()` rather than
  duplicating the death sequence — `die()` already disables input, plays the cue and
  hands off to `PlayerRespawn` after 1.5 s.
- The component order in `prefabs/character/player/README.md` is load-bearing. Health
  reads physics and never writes it, so it sits after `CollisionResponse` at priority
  100, which owns `move_and_slide`.
- Two new groups on `player_settings.gd`, following the shape of the existing `Oxygen`
  and `Noise` groups:
  - **Health** — `max_health`, `health_regen_per_second`, `health_regen_delay`
  - **Hazards** — one damage figure per source: impact, gas pod, arc, and the
    oxygen-starvation rate
  - Both validated by the existing `invariant_failures()`.
- HUD: a field on `%HudState`, pushed by `player_hud_binding.gd` the same signal-driven
  way oxygen and charge already are. Keep it **quiet** — cracks and frost creeping in
  from the edge of the visor, not a bar. Pillar 5 rejects overlays, and a health bar is
  the most overlay-shaped thing a game can own.

### The stalker ignores all of it

A stalker hit is still an instant kill. It does not consult health, cannot be tanked,
and cannot be budgeted for. This is not an oversight to fix later — it is the point.
Pillar 1 says you are never the powerful thing in the room, and the moment a player can
look at a health bar and conclude they can *survive* the stalker, it stops being the
thing the whole level is arranged around.

Health is for attrition. The stalker is for endings.

---

## 2. Hazards

Five families. Each is hand-placed on a depth gradient matching the ore gradient the
level already uses, so risk and reward climb together and the player is always pricing
one against the other.

### Impact velocity

Zero-G's own hazard. Hit rock hard enough and it costs health; the visor cracks and
oxygen bleeds faster until you are back on tether.

This is the cheapest hazard in the document and the most on-theme: it needs no art, no
placement, and no new detection. `player_collision_response.gd` already emits
`impacted(closing_speed, at)`, and `player_settings.gd` already carries
`impact_reference_speed` (8 m/s) as the speed a full-strength impact noise is measured
against. A health listener on that signal is most of the work.

It makes thrust itself the risk, which is Pillar 3 stated as a mechanic rather than as
a mood.

### Gas pods

Pressurised pockets in the rock. Cutting one — or striking it hard enough — detonates
it: damage, a hard tumble, and a very loud noise.

The mining verb becomes the hazard, which is the most valuable thing on this list,
because it means the player's own competence is what endangers them. None in
`drift_a_m_1`, where the player is still learning what a wall is. Thick around `pocket`
and everywhere deeper.

The noise matters as much as the damage: a detonation is louder than cranking, and it
comes from a position the player did not choose.

### Wreck hazards

The prior crew's leftovers are live.

- An **arcing cable** off a burst life-support cube drains suit charge inside a radius.
  Cross it and the meter you have been carefully managing drops for reasons that are
  not your fault.
- A **still-charged mining laser**, drifting, fires when disturbed. Damage if it hits
  you; a very loud cut if it hits rock.

This is the hinge of the whole document. Without it, the wreckage is decoration the
player learns to fly past inside ninety seconds. With it, every silhouette in the dark
carries a question, and the debris keeps paying rent for the whole run.

### Blockages

Collapsed rock sealing a route. Mining one open is loud, slow, and expensive.

**Optional routes only. Never the critical path.** A blockage is a shortcut you may buy
or a rich pocket you may open, and refusing it is always a complete answer. A run cannot
soft-lock on one, and the player is never obliged to make the loudest noise in the game
in order to continue.

Best placements are the `refuge`-tagged narrows — `strip_a_c3_mn` (3.4 m) and
`winze_north` (3.8 m) — and the mouth of `pocket`. Those are exactly the places where
the reward for the noise is legible before you commit to making it.

### Clinger nests

See §4.

### Recorded as rejected

**Hazards on a run clock.** Escalating danger on a timer regardless of what the player
does punishes caution, and caution is the only real skill this game teaches. The five
minutes should be a shape the player authors by choosing depth, not one the game imposes.

---

## 3. The debris vocabulary

Ten rubble variants already exist and are instanced in **zero** level scenes —
`assets/art/environment/props/sm_rubble01..10` with prefabs at
`prefabs/environment/props/prefab_rubble01..10.tscn`, generated by
`tools/voxel-rubble/build_rubble.py`, untextured, 100–752 tris. They are free volume
and should be doing work today.

On top of them, six new props. A **small repeatable kit** rather than a long tail:
every object is one the player already knows, broken. That is what lets a silhouette do
narrative work at four metres.

| Prop | What it says | Reuse |
|---|---|---|
| `sm_helmet_cracked` | The most legible "a person died here" shape there is | new |
| `sm_mining_laser_broken` | Snapped at the emitter. The player's own tool | silhouette of `prefabs/gameplay/prefab_mining_laser.tscn` |
| `sm_life_support_cube_wreck` | Panels sprung, lamp dark — and the player is carrying its twin | silhouette of `prefabs/gameplay/prefab_life_support_cube.tscn` |
| `sm_tether_cut` | A severed line with the clip still seated, drifting | new |
| `sm_miner_corpse` | Suited, intact, slack | pose `assets/art/character/sk_player_character.gltf`; no new skeletal asset |
| `sm_clinger` | Dormant and active variants | new |

The cube wreck is the strongest object in the kit, because recognition does the work.
The player has spent the whole run tethered to one of these, cranking it by hand. Seeing
one burst open reframes the object they are depending on, and it costs one mesh.

### On body parts — a live disagreement, not a settled call

Loose limbs were discussed and this document recommends against them.

The register the game has already established is bureaucratic and cold. The intro says
`TELEMETRY ENDED` rather than "deceased," and explicitly avoids a skull icon because
"the euphemism is colder." An intact suited body that is simply, permanently *still*
belongs to that register. A dismembered one belongs to a different game — and it costs
five assets instead of one.

If the team wants gore, the cheap version is a cracked visor with something dark behind
it. That reads at distance, keeps the euphemism, and reuses a prop already on the list.

This is recorded as a disagreement rather than a decision. It should be settled by the
art lead, not by this document.

### Physics

**Mostly dressing, a few real.** Cheap non-colliding drifters supply the volume; real
`RigidBody3D` pieces go only where the player will actually touch them — the `pocket`
tableau, and any wreck carrying a hazard. Debris that ignores a shove in zero-G reads as
broken, so the pieces at arm's reach have to be honest; the pieces at twenty metres do
not, and the web frame budget cares about the difference.

### Conventions, so nobody has to go find them

- `assets/art/{category}/{object}/`, `sm_` prefix, lowercase with underscores, glTF only,
  metres.
- The `.gltf.spec.yaml` sidecar is required and **unrecognised keys are a hard error**.
  `assets/art/environment/props/sm_rubble01.gltf.spec.yaml` is the model to copy,
  including its habit of opening with a comment explaining the numbers.
- Commit the whole set together: `.gltf`, `.bin`, `.gltf.import` (it carries the `uid://`),
  `.gltf.spec.yaml`, and the container `.tscn`.
- The container scene `sm_<name>.tscn` and the prefab `prefabs/<category>/prefab_<object>.tscn`
  are different files with different jobs. Nothing places a container directly in a level.
- `metadata/placeholder = true` on **both** while the art is stand-in; the pair is audited
  by `tools/placeholder-art/audit_placeholders.py`.
- Generation precedent for procedural props: `tools/voxel-rubble/`, which writes glTF
  directly with no Blender round-trip.

---

## 4. The clinger

Not "facehugger" — that name belongs to another film and drags its whole ruleset in with
it. **Clinger.** In any system text the company calls it `SURFACE FAUNA, MINOR`, which
matches the intro's established habit of reclassifying the alarming into the routine.

**Built.** `prefabs/character/clinger/` and `systems/clinger/`; tuning in the Clinger group
on `player_settings.gd`; placed in the hazard sandbox and twice in the mines. Two things
below were amended rather than implemented as written — the struggle seam, and whether the
mining beam can kill one. Both are marked *Amended* where they occur, and the second one
carries a live consequence for §8.

### What it is not

It is **not** built on `gameplay/creature/**`. That module — a five-state HFSM, a
suspicion board, a hotspot field, spatial memory, an A* navigator with clearance
profiles — is written around the stalker fantasy. Nests, dwell, `RECONSIDERING`, retreat
separation: almost every state and every transition guard would be dead weight on a thing
whose entire life is *wake, crawl, latch*.

A small standalone prefab: an `Area3D` trigger, a crawl, and a four-state script. The
domain-free behaviour-tree framework at `gameplay/creature/behavior/tree/` is liftable if
it helps — `behavior/tools/verify_behavior_static.gd` fails the build if anything under
`tree/` names a creature subsystem, which is precisely the enforcement that makes it safe
to reuse.

### States

Dormant (on a nest, a corpse, or a wall) → woken by sound → crawls toward the source →
lunges → attached → shed.

### It hunts sound, not players

No perception system. It takes a noise position and crawls toward it — slowly, visibly,
on the rock. You can outrun it. You can go quiet and it loses you.

It should read the same noise stream the stalker does. `PlayerNoiseEmitter` and
`PlayerBeamNoiseEmitter` already publish `noise_emitted(strength, at, source)`, bound
into channels by `gameplay/creature/perception/world/player_noise_relay.gd`.

The consequence is the best thing in this document, and it is emergent rather than
authored: **cranking the cube is the loudest deliberate act in the game, so cranking now
draws both creatures — and the small one arrives first.** Every noise decision the player
makes now has a near-term answer and a long-term one. That is a pacing engine the level
gets for free.

### Attached to your face

Occludes most of the visor. Thrust still works; look precision degrades; the lamp is
blocked. Oxygen drains around three times as fast, because it is sitting on the intake.

### Attached to the cube

It drains the cube's charge — `LifeSupportCube.spend()` already exists for exactly this
shape of call. The tether stops replenishing, and everyone's oxygen clock starts.

Pillar 4 exactly: a convenience billed to the group. It also gives a solo player something
to defend rather than only something to flee, and it makes the parked box a place you have
to keep looking back at.

### Getting it off

Mash any already-bound action. **No QTE overlay, no meter, no prompt** — Pillar 5 is
explicit that nothing gamey competes with the build-up, and a struggle prompt is the most
gamey object available.

The feedback is physical instead. Each press peels the thing a few degrees off the glass,
and you can see how much visor you have won back. That is a meter made of the creature.

*Amended in build.* **No new action was added.** `player_input.gd` gained a `struggled`
signal and a `struggle_listening` flag, and reads the whole `InputMap` behind a short
deny-list — pause, the mouse-capture toggle, the debug keys and push-to-talk keep their own
meaning. A single named binding would have collided with `thrust_up` and would have made
"mash any key" a lie on a gamepad.

The `enabled` guard is the seam this section is right about, and it is read **above** it:
whatever takes the suit away also makes every branch below unreachable, and mashing has to
stay readable exactly then.

The clinger does not lock the input at all. Thrust still works while you are wearing one,
which is what this section already asks for, and it sidesteps a trap worth recording:
`PlayerInput.enabled`'s setter is `value and not locked`, so anything still holding `locked`
when `PlayerLife._revive()` runs swallows the revive in silence and the player spectates for
the rest of the session. The grip releases on `died` and `respawned` regardless, and
`tests/verify_clinger.gd` pins it.

Nothing reparents anything and nothing takes `HeadCamera`: the creature reads a transform
off `Head` and drives its own body from it, one tick after the suit has moved.

### Failing is never dying

Do nothing and it never kills you. It just keeps draining.

The real cost is that thrashing is **loud** — it paints you for the stalker. A player who
panics and mashes escapes fast and arrives somewhere worse; a player who stays calm loses
more oxygen and stays invisible. That is a better punishment than a death screen, it welds
the small creature to the big one, and it makes the correct play genuinely hard to
perform.

Alternative considered and rejected: a lethal timer. It would make the clinger compete with
the stalker for the same narrative job, and the stalker should not have competition.

### It can be killed — amended

*Amended in build, against what this document originally said.* The clinger has hit points
(`clinger_hp`, three seconds of held beam) and the mining laser kills it. A dead one drifts
off the rock and despawns after `clinger_death_despawn_time`. A shed one does not leave: it
circles you on the walls and attacks again when `clinger_attack_cooldown` clears.

The argument for it, recorded so the reversal is reviewable rather than merely done: a
creature that can only ever be endured is a tax, not an encounter. Without a price the
player can choose to pay, the correct play against every clinger is identical, and Pillar 3
wants the player pricing one bad option against another.

**The price keeps it honest, and it is the same one the level already charges.** Those three
seconds of beam are `PlayerBeamNoiseEmitter` reporting at full `mining_noise_strength` —
the loudest sustained thing in the game. Killing a clinger calls the stalker. That is the
trade, it needed no code to exist, and it is the same shape as the emergent pacing engine
this document is pleased with two sections up.

Nothing else moved. It still cannot kill you: `clinger_health_drain_per_second` is checked
against `CLINGER_MIN_SURVIVAL_SECONDS` in `invariant_failures()`, so a slider cannot quietly
turn one into an ending. The lethal timer stays rejected. And `clinger_jump_range` is
checked against `mining_range` for the reason that makes the whole thing coherent — a
creature that leaps from further than the beam reaches would be a hazard with no answer.

### The first one is seen before it is felt

A dormant clinger on a corpse's face at `pocket` — visible, motionless, harmless. The
player gets to circle it, light it, and decide it is dead.

See it on a dead man. Then feel it on yourself.

### Co-op

A partner pulls one off you faster than you can shed it. Noted as design-forward rather
than shippable: `_start_creature()` in `levels/asteroid_level/asteroid_level.gd` is
solo-only today, and `PlayerNetworkGameplay.DISABLED_ONLINE_COMPONENTS` already stands
down `Grab`, `Interactor` and `Life` online.

---

## 5. Placement

Every location below is a real space in
[the blockout annotations](level_full_blockout_annotations.md), so this survives contact
with the level file.

### `mine_mouth` — nothing

(−91, −33, 35.) The car must read as absolute safety; LD0 makes that a requirement and
names its silhouette the most important landmark in the level. Wreckage here undercuts it
before the player has anything to compare it to.

One exception: a scrap of cut tether on the lip of `drift_a_m_1`, at the edge of the
floodlights. Small enough to be missed, and worth more on a second run than a first.

### `drift_a_m_1` — the first debris, and only one piece

(24 m, the deliberately choiceless first tunnel.) The broken mining laser, drifting slow.

This teaches *the shapes out here are man-made* before it teaches *people died out here*,
and the gap between those two lessons is where the dread lives. No hazards in this tunnel
at all — it is the one stretch where the player is still learning what a wall is.

### `a_c2_m` — the first body, at the first choice

(−67, −37, 33, the first T junction.) Placed so the lamp finds it while the player is
deciding which way to go. A choice made over a corpse is a different choice.

The first fake-out lives here too: the body rotates slowly to face you as you pass. It is
inert. It is just conservation of angular momentum and your own wake. It works anyway.

### `strip_a_c3_mn` — the refuge that isn't

(3.4 m, `refuge`-tagged.) A burst life-support cube wedged in the narrows, arcing.

This placement carries the document's most important environmental argument, so it should
be legible without a word of text: **the narrow tunnels are safe from the stalker and not
safe from the small thing.** The refuge tags exist because the creature cannot fit. Nothing
stops a clinger. Teaching that here — in the first place the player thinks to hide — is
what stops the two creatures from collapsing into one threat.

The first optional blockage sits at the far end of the same strip.

### `pocket` — the tableau

(−55, −61, 15. The annotations call it "the most rewarding room in the mines and, to some
extent, its most dangerous.")

Two bodies. A cut tether. A dormant clinger on one face. Gas pods in the walls. And the
tier-1 ore they died holding, still drifting where it was cut free.

This is the document's answer to the LD0 brief's open review question — *can one static
layout produce the MVP test, scared twice and loot abandoned once?* **This room is where
the level manufactures the second decision.** Everything about it is arranged so that the
correct play and the tempting play are different plays, and so that the reason to leave is
visible at the same moment as the reason to stay.

### Ravine, hive, biome links — clean

No prior-crew wreckage past the mines. Hazards continue and intensify; the human debris
stops.

The mines are as far as anyone got. That is the whole story, and it is told by the absence.

### The scatter tool

`prefabs/environment/minerals/mineral_scatter.gd` is an `@tool` wall-dresser that raycasts
against the rock hull, holds placements off the surface, and — critically — tracks a
`_scatter_transform` so it can tell a generated deposit from a hand-adjusted one and never
clobber the second. A debris scatter tool should be a copy of that shape, including the
group-ownership guard.

Building it is a follow-up, not part of this document.

---

## 6. Corpse narrative — suit telemetry, not audio logs

The bodies should say something. They should not say it with a pickup verb or a
collectible.

**Approaching a body wakes its suit.** The same flat ELEVATOR SYSTEM V.O. reads its last
telemetry line and nothing else:

> Extraction Crew Zero-Six-Six. Miner C. Telemetry ended.

That is the whole interaction. No prompt, no hold-to-listen, no log screen.

It works because it costs nothing and reuses everything: an established voice, an
established register, and the existing routing convention from `narrative.md`
(`vo_[scene]_[beat].wav`, on the Dialogue bus, alongside the shipped
`vo_elevator_access_denied.wav`). It needs no dialogue system and no captions — and
**there is no caption system**; `common/cutscene/cutscene_hud.gd` has no text hook at all,
so anything written to be read rather than heard is a larger piece of work than it looks.

It also pays off a thread the intro already planted: the one-frame interference showing
`EXTRACTION CREW 066 / TELEMETRY ENDED: 3/3`. The player heard that number in the car.
Now they are finding the three.

Rejected: readable terminal fragments and audio logs, for the same reason the GDD rejects
tutorial popups — they stop the run to be consumed, and Pillar 5 does not permit anything
that competes with the silence.

---

## 7. The first five minutes

Layered onto the shipped 42-second intro. The beat table in
`levels/asteroid_level/intro/README.md` is authoritative for everything before control
handoff and is not restated here.

| Beat | Where | What it teaches |
|---|---|---|
| Intro, doors, denial | the car | Quota, cube, oxygen, HUD — and that the system will not take you back |
| Push-off | `mine_mouth` | Orientation, while nothing is happening |
| Broken laser | `drift_a_m_1` | These shapes are man-made |
| First body, first fake-out, first choice | `a_c2_m` | People died out here, and you are choosing anyway |
| First ore, first noise, first gas pod | east of `a_c2_m` | Cutting is loud, and the rock answers |
| Arcing cube, first blockage | `strip_a_c3_mn` | The narrows are not a refuge from everything |
| The tableau, the dormant clinger | `pocket` | What killed them, and what it will cost to take what they died for |

Subordinate to the LD0 beat list throughout. That document owns the spine; this one
dresses it.

### Jumpscares — mostly fake-outs

Debris lurches. A corpse rotates to face you. A dead lamp flickers on and dies again.
Almost all of it is harmless, and the player should be able to work that out.

That is the point. The few scares that are real land because the player has stopped
believing the last four. It is also the cheapest horror in the document — most of it is
one animation on a prop that already exists — and it is the Subnautica influence the GDD
already names: stings that scare you for no reason.

The rule that keeps it honest: **a fake-out never costs the player anything except
adrenaline.** No damage, no dropped ore, no noise the stalker hears. The moment a
fake-out has a price, the player is right to treat every one of them as a threat, and the
whole effect inverts.

---

## 8. Proposed GDD amendment

**This is a proposal, not a decision.** It needs the design lead, and nothing here should
be treated as settled until it has one.

Two entries in the [GDD's Out of Scope section](game_design_document.md) currently forbid
the clinger outright:

> *Multiple asteroids or multiple creature types*

Proposed narrowing: **"multiple stalkers."** One unkillable hunter is the pillar, and the
clinger does not compete with it — it cannot kill, it can be escaped by pressing a button,
and it exists mainly to make the player loud. It reinforces Pillar 1 rather than diluting
it: a second thing you cannot fight is not a second power fantasy.

> *Combat of any kind. The creature cannot be killed, damaged, or driven off permanently.*

Proposed narrowing: **"no combat with the stalker."** Shedding a clinger is escape rather
than combat — nothing dies, nothing is driven off permanently, and the player gains no
weapon, no damage number, and no reason to seek one out.

**This is now a larger ask than that sentence, and the design lead should be told so.** The
build kills clingers with the mining beam (see §4), so something *does* die. What survives
of the original argument: the player still gains no weapon — the laser is a mining tool and
was always going to be aimed at rock — no damage number is ever shown, and there is still no
reason to seek a clinger out, because killing one is louder than walking away from it. What
does not survive is "nothing dies." Narrow the entry deliberately or reverse the build; do
not let this footnote settle it.

The health pool in §1 touches the same entry's spirit and needs the same review. It is
proposed here with the stalker deliberately exempted, which is the whole reason it can be
proposed at all.

Per this repository's convention, out-of-scope items are recorded **only** in that GDD
section. Nothing above should be read as amending it, and this document does not.

---

## 9. Open questions

- **Body parts.** Recommended against in §3; the art lead decides.
- **Ownership.** Neither the clinger nor the health component has an owner, an art budget,
  or an engineering slot. Nothing in this document ships on enthusiasm.
- **GDD open question #9** — whether the creature can threaten a player camping the
  elevator — is still unowned, and its answer may overturn the "keep `mine_mouth` clean"
  call in §5.
- **Online.** The creature does not spawn in a networked session at all, so every co-op
  behaviour described here is design-forward.
- **No debris scatter tool exists.** Until one does, every placement in §5 is by hand.
- **Two clingers, two cubes.** What a clinger does to a second player's cube in co-op is
  unspecified, and "drains the shared charge twice as fast" may be too punishing to be fun.
