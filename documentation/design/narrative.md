# Narrative

Story content for the game, in production-facing formats (teleplay-style scene
scripts, VO copy). `documentation/design/narrative.yaml` is reserved for a
structured/machine-readable version of the same material, for whenever a scene
needs to be data-driven rather than hand-authored; it is intentionally empty
until something needs that.

See also [Environmental Storytelling, Hazards, and the Clinger](environmental-storytelling.md),
which proposes the corpse suit-telemetry lines that reuse this scene's ELEVATOR SYSTEM voice.

## Elevator Intro — Teleplay

### What this is

The asteroid level's opening — `levels/asteroid_level/intro/` — is a shipped,
tested 42-second cutscene with baked camera choreography and exactly one line
of dialogue (`"Access denied. Meet your quota to escape."`, played as a timed
effect, not a character line). This script expands it into a full briefing that
teaches the player, through story rather than a tutorial popup, about the
shared life-support cube, personal oxygen and suit power, mining, and why
disturbing whatever else lives down there is a bad idea.

It reuses the shipped scene's blocking, timing, and copy wherever they already
exist, and proposes new material only where the existing cutscene is silent.
Format key used throughout:

- **[EXISTING]** — this beat, its timing, and any camera/animation are already
  shipped (`elevator_intro_knobs.gd`, `elevator_intro.cutscene.tres`). Only the
  dialogue on top of it is new.
- **[NEW]** — proposed staging that does not exist yet. Would need new
  animation/audio work, built the same way the shipped gesture and press beats
  are: a hand-offset target solved by two-bone IK, per the precedent in
  `elevator_intro_knobs.gd`'s `GESTURE_HAND_OFFSET` / `PRESS_*` regions.

Single speaker throughout: **ELEVATOR SYSTEM (V.O.)** — an automated safety/ops
announcement, not a character. It is never named and belongs to no named
company; the placard in the shipped scene is blank on purpose, and the GDD
leaves the employer deliberately unlocked. Delivery is flat, recorded, and
bureaucratic — the horror is in what it says without changing tone. Reference
for voice: the GDD's Treatment paragraph, the closest existing prose to this
game's register.

Total added runtime is roughly **+5 seconds** (one new physical beat); every
other addition is dialogue laid over animation that already exists. Kept
deliberately lean — Design Pillar 5 is "five minutes, fully felt," and this
scene already eats a meaningful slice of that clock.

---

### INT. MINE ELEVATOR — DESCENDING

**[EXISTING — 0.0–3.0, `car_descending`]** *Full screen: the quota terminal's
glass. `EXTRACTION CREW 067`. A debt figure in red. A quota figure under it.*

> **ELEVATOR SYSTEM (V.O.)** *(flat, recorded)*
> Extraction Crew Zero-Six-Seven. Outstanding balance, forty-one thousand
> three hundred sixty-five credits. Today's contribution goal, two thousand.
> Have a productive descent.

**[EXISTING — 3.0–11.5]** *Hard cut to the same screen in 3D; the camera pulls
back off the glass and reveals the car — three miners, suits dark, descending
in silence. **[NEW set dressing, no new animation]** a life support cube sits
racked on the wall beside the doorway, lamp glowing a dim amber.*

> **ELEVATOR SYSTEM (V.O.)**
> Reminder: life-support is shared property. One unit per crew. Tether before
> you drift, or don't — that's between you and your lungs. Hand-crank it if
> the charge reads low.
>
> *(a half-beat, the only thing in this briefing that isn't quite deadpan)*
>
> Cranking is loud. That is not a defect.

**[EXISTING — 11.5–17.5]** *Camera pushes in on MinerB; a gloved hand rises
toward the helmet, and the helmet lights from within.*

> **ELEVATOR SYSTEM (V.O.)**
> Your suit carries its own reserve. It is smaller than you'd like, and it
> does not share. It drains regardless of what you are doing, and it only
> refills on tether. Plan accordingly.

**[EXISTING — 17.5, `hud_online` / 18.7, `hud_settled`]** *Match cut to the
player's own eye. The HUD strikes on like a tube warming up: an oxygen ring,
a suit-charge bar, settling into place.*

> **ELEVATOR SYSTEM (V.O.)**
> Display active. Outer ring, oxygen. Inner bar, suit charge. When both read
> empty, you will not require this briefing again.

**[EXISTING — 20.5, `car_stopped`]** *The car lands. A strobe. BEGIN WORKDAY,
held and gone.*

**[EXISTING — 21.1–25.5, `doors_unlocked`]** *The doors open on the mine. A
beat, looking out into it before anything moves.*

> **ELEVATOR SYSTEM (V.O.)**
> Ore reads as a glint on your lamp before it reads as a shape. Cut what you
> can reach. Do not chase what gets away from you into the dark —
>
> *(no emphasis; this is the whole point of the line)*
>
> it will not miss you. Your air will.

**[NEW — ~25.5–30.5, inserted before the drift]** *A gloved hand finds the
cube's rack beside the doorway. A tether clip, seated with a click. One hard
turn of the crank — a grinding, metallic whine, loud enough in the quiet car
to feel like a mistake. The cube's lamp shifts from amber to green. No VO
here; let the crank carry the beat. This is the teaching moment for the
life-support cube done as action rather than as narration — it dramatizes the
GDD Treatment's own opening image (tether, crank, push off) instead of
describing it.*

**[EXISTING — drift/turn, times shift by the new beat's length]** *The player
pushes off through the doorway, cube trailing on its tether, out into the
open dark of the mine. A turn, back toward the car.*

**[EXISTING — `doors_locked`]** *The doors close.*

**[EXISTING — press beat, VO at contact]** *A hand comes up to the call
panel. Contact. A strobe. The tube of the HUD sags.*

> **ELEVATOR SYSTEM (V.O.)**
> Access denied. Meet your quota to escape.

**[NEW — the gap between the denial and the final pan, ~3 seconds of existing
silence]**

> **ELEVATOR SYSTEM (V.O.)** *(same flat register — this is not a special
> announcement to the system, only to the player)*
> Addendum: indigenous biologics have been logged in deeper strata. Do not
> approach. Do not linger. Do not, under any circumstances, be interesting.

**[NEW — over the existing pan back onto the mine and control handoff,
`workday_begun`]** *Silence, but for the rumble settling still. Then —
distant, low, wet — a sound that is not machinery. It does not repeat.
Control returns to the player, facing the dark.*

---

### Beat & implementation reference

| Beat | Status | Timing | New asset (suggested) |
|---|---|---|---|
| Debt/quota cold open | dialogue new | 0.0–3.0 (existing) | `vo_elevator_briefing_quota.wav` |
| Life-support cube reminder | dialogue new + set dressing | ~6–11.5 (existing) | `vo_elevator_briefing_lifesupport.wav` |
| Suit power reminder | dialogue new | ~12–17.5 (existing) | `vo_elevator_briefing_suitpower.wav` |
| HUD boot narration | dialogue new | 17.5–20.5 (existing) | `vo_elevator_briefing_hud.wav` |
| Mining tip | dialogue new | 21.1–25.5 (existing) | `vo_elevator_briefing_mining.wav` |
| Tether/crank dramatization | new beat | ~+5s, inserted pre-drift | new animation; no VO |
| "Access denied…" | unchanged | 36.0 (existing) | already shipped: `vo_elevator_access_denied.wav` |
| Wildlife addendum | dialogue new | ~37–40 (existing gap) | `vo_elevator_briefing_fauna.wav` |
| Distant creature call | new beat, no dialogue | ~40–42+ (existing pan/handoff) | `sfx_elevator_fauna_distant.wav` (name/folder TBD — no sfx-specific precedent confirmed yet) |

Naming follows the shipped precedent (`vo_elevator_access_denied.wav`):
`vo_[scene]_[beat].wav`, routed to the `Dialogue` bus like the existing line.

### Open items for whoever implements this

- **No subtitle/caption system exists.** Every new line above is written to be
  audio-only, matching the shipped line's precedent
  (`common/cutscene/cutscene_hud.gd` has no text-display hook). If accessibility
  or an audio-budget crunch makes captions necessary, that's a separate,
  larger piece of work than this script.
- **`documentation/design/narrative.yaml` is still empty on purpose.** A
  structured version of this script (for tooling, localization, or a future
  dialogue system) is a follow-up task, not part of this one.
- **The tether/crank beat is staged, not engineered.** Exact hand offsets,
  elbow poles, and camera poses are a job for whoever builds it against the
  real rig, the same way the shipped gesture and press beats were tuned — see
  `levels/asteroid_level/intro/README.md`'s "Three things that will surprise
  you" section before attempting it.
- **Runtime moves from 42.0s to roughly 47s** if the new beat is built as
  written. Worth a gut-check against Pillar 5 once it's playable, not just
  read.
