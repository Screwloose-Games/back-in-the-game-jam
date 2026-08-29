# Worked example: the sense hook

One idea taken from its first framing, through a near miss, to a hypothesis that can fail.
The beat is real, the numbers are real, and the output block at the end is meant to be
copied.

## The situation

`python tools/loop/loop.py spine --brief` currently says:

```
Spine: 0 of 11 beats signed off.
Next unproven beat: locate (must) -- Find an ore node with whatever the suit can sense in the dark.
```

`mine_and_haul.locate` is `tier: must`, `status: reachable`, and owns `systems/radar/` and
`systems/rendering/`. Its `feedback:` field reads:

> The node reads as valuable before you commit to it -- the sense hook has to carry this,
> because draw distance is deliberately short.

GDD open question **#2** is *"Which sense is the hook — light, proximity radar,
echolocation/visor shader, or sound?"*, blocking *"Art load, shader work, level readability"*.
`documentation/design/levels/ld0-asteroid.md` treats it as a live constraint: the layout has
to stay readable under any of the four.

So the beat is committed, and the mechanism that delivers it is not. That gap is the
hypothesis.

## First attempt

> *"Does the radar make finding ore fun? Build the sense hook properly -- radar pulse plus a
> visor outline shader plus an audio ping -- in the asteroid level with the creature active,
> and see whether players enjoy it enough to push deeper for the better ore."*

**This is not minimum. It violates all five rules:**

- **Rule 1** -- three mechanics are on trial at once (pulse, outline shader, audio ping), and
  the depth/value gradient is a fourth.
- **Rule 2** -- two primary responses decide success: enjoyment, and risk appetite ("push
  deeper"). They can move in opposite directions and there is no rule for what that means.
- **Rule 3** -- the creature is live and the fog is doing work, so a null result is
  attributable to creature pressure, to draw distance, or to any of the three senses.
- **Rule 4** -- the tether, the drill, the power drain, ore physics and the full level are
  switched on, and none is causally necessary to "does a sensed contact read as worth
  travelling to".
- **Rule 5** -- a success leaves GDD #2 exactly as open as it was. If players love it, we
  still do not know which sense did it, and *which sense* is the literal wording of the
  question.

## Second attempt -- the near miss

> *"If the suit's radar pulse and visor outline together mark an ore node in the dark, the
> player will travel to it rather than sweep past."*

Much better. Still not minimum: **Rules 1 and 5.** Two sense channels are on trial
simultaneously, so a pass tells you *a sense hook works* and not *which one* -- and #2 asks
precisely which one. Cutting to one channel costs nothing and buys the whole answer.

This is the instructive failure. It looks like one hypothesis because it names one outcome.
Count mechanisms, not outcomes.

## The repaired hypothesis

> **If the player fires one radar pulse in a dark tunnel and a single contact returns at a
> bearing, they will change heading toward that bearing before the node is visible. False if
> they instead keep sweeping, drift past, or only turn once the node enters draw distance.**

One interaction: the pulse. One predicted response: commitment before sight. One observable:
the first heading change after the pulse, timed against the node crossing the fog line. One
failure condition -- and it is a good one, because *"only turns once the node is visible"*
isolates the sense hook from line of sight, which is the exact confound the beat's own
`feedback:` line warns about.

## Prerequisites, worked

| Prerequisite | Needed? | Established? | Disposition |
|---|---|---|---|
| The player can fire the pulse | yes | yes -- `PlayerRadarDetector` exists, `tests/test_radar_pulse.gd` passes | assume |
| The player knows the pulse finds ore | yes | no | **mock** -- one sentence of manual facilitation before the run |
| The dish shows a bearing, not just proximity | yes | yes -- `RadarPulse.local_offset()` takes the full transform, *"in zero g the suit sits at any attitude, and something ahead of you has to read as ahead however you happen to be oriented"* | assume |
| Ore has a value gradient by depth | **no** | -- | remove; that is GDD #4 |
| Sensing costs power | **no** | -- | mock: `radar_power_per_pulse = 0`. Pricing the sense is `read_the_bill`'s hypothesis. |
| Zero-G movement feels controllable | yes | **uncertain -- GDD #1** | **earlier hypothesis.** Not folded in. |

That last row is the section earning its keep. LD0 already says no dimension proposed at LD2
can be trusted until the zero-G movement question lands. If players cannot steer, a
heading-change measurement means nothing -- so #1 outranks #2 no matter how #2 scored.

## The ladder, rung by rung

| Rung | Verdict |
|---|---|
| Paper / manual | No. The uncertainty is perceptual and temporal -- whether a fading blip at a bearing reads as worth travelling to. Paper cannot present a decay curve. |
| Clickable mock | No. Bearing without an up is the disorientation the question lives inside; a 2D mock removes it. |
| Scripted interaction | No. The player must choose the heading. Scripting the outcome removes the response being measured. |
| **Simplified implementation** | **Yes.** Existing `RadarPulse` + `RadarDetectable`, one straight corridor, one contact, fog pinned. |
| The actual system | No. The value gradient, the power cost, the creature and the drill all come out without touching the causal chain. |

The geometry matters and is worth stating: `radar_range` is 80 m
(`player.tuning.gd:329`) while the core-loop prototype pins fog at `FOG_DEPTH_END := 26.0`.
The radar reaches roughly three times the draw distance, which is the entire reason the beat
can work -- and it is why the contact goes at **40 m**: inside the radar's reach, well
outside the fog line, so "committed before it was visible" is a fact about the recording and
not a judgement call.

## The output block

```markdown
## CORE FUN HYPOTHESIS

If the player fires one radar pulse in a dark tunnel and a single contact returns
at a bearing, they will change heading toward that bearing before the node is
visible. False if they keep sweeping, drift past, or only turn once the node
enters draw distance.

Answers GDD open question #2 (which sense is the hook), for one of its four
candidates. Beat: mine_and_haul.locate.

## WHY THIS IS THE MINIMUM HYPOTHESIS

- **One uncertainty:** whether a proximity return reads as valuable enough to
  commit to. Not whether radar is implementable -- `systems/radar/` already works
  and is unit-tested.
- **One causal mechanism:** pulse fired -> contact returned at a bearing ->
  heading changed.
- **Primary player response:** commitment. The first heading change after the
  pulse is toward the contact's bearing.
- **Failure is diagnosable because** the only sense channel switched on is the
  dish. No outline shader, no audio ping, no helmet lamp beyond the fixed fog. A
  null result names proximity radar and nothing else, which is what #2 asks for.

## TARGET PLAYER

Someone who has played Lethal Company or Deep Rock Galactic, has not played this
build, gets one sentence of instruction and no coaching after that. Five of them.

Audience fit is not being tested here. Whether this audience tolerates a
diegetic-only readout -- LD0's "no tutorial overlays or text popups" -- is a
separate hypothesis, in the backlog.

## MINIMUM PROTOTYPE

**Given** the player knows the pulse finds ore and can steer in zero-G,
**When** they fire one pulse in a straight unlit corridor holding exactly one
contact 40 m away and 30 degrees off their current heading,
**Then** one blip appears on the dish at that bearing and decays over the sweep,
**And we observe whether** their first heading change after the pulse is toward
that bearing, before the node crosses the fog line at 26 m.

## MOCK / SCRIPT / REMOVE

- **Mock** -- power cost of a pulse: `radar_power_per_pulse = 0`. Its range
  already allows zero, so this is a number in the diff, not code to remember to
  delete. Pricing the sense is `read_the_bill`'s hypothesis.
- **Mock** -- ore value: every contact is the same ore. The depth gradient is #4.
- **Fix** -- fog depth pinned at 26 m for all five runs, so "before you commit to
  it" has one meaning across the whole set.
- **Script** -- the corridor: straight, one contact, hand-placed, identical every
  run. Nothing procedural.
- **Remove** -- the creature, the tether, the drill, ore physics, every HUD widget
  but the dish, the outline shader, the audio ping, the elevator, the quota.
- **Remove** -- the second player. Solo is the harder case for a sense hook, and
  the GDD requires the game be fully playable solo anyway.

Every surviving item answers "what uncertainty does this help resolve?" with
"whether a bearing return earns a heading change." Nothing else survived.

## PASS

In 4 of 5 uncoached players, the first heading change after the pulse is toward
the contact bearing and happens before the node crosses the fog line.
-> Capture evidence, then `loop.py signoff locate --pass`. Proximity radar is the
sense hook; #2 closes and the other three candidates leave the backlog.

## REVISE

Players commit, but only after two or three pulses, or only inside 10 m. The
causal link is there and a number is wrong.
-> `--fail --note "REVISE: ..."`. Change exactly one of `radar_range`,
`radar_pulse_speed`, or the blip's decay. Re-run. Two numbers is not an
experiment.

## REJECT

Players fire the pulse, see the blip, can say what it means, and navigate by fog
and geometry anyway -- the blip changes no headings.
-> `--fail --note "REJECT: proximity radar is not the sense hook"`. The beat
stays; it is `must`. The mechanism goes, #2 loses one of four candidates, and the
visor shader becomes the next hypothesis.

## TEST VALIDITY

Checked before any of the three above:

- Did they fire the pulse at all?
- Could they read a bearing off the dish, or only "something is out there"?
- Did they know a blip meant ore?
- Could they steer well enough that a heading change was a choice, not a drift?

Any no makes the run INVALID, not a failure. `Verdict:` stays `open` and
`Verdict by:` moves once with the reason on the line. A second invalid run is a
REJECT: a mechanic two groups could not read is telling you about the mechanic.

## WHAT WOULD CHANGE OUR MIND

If three of five players commit to a contact only after it is visible, we stop
calling the radar the sense hook -- even though `systems/radar/` is the most
finished sense we have, is already owned by this beat, and has passing unit
tests. Sunk implementation is the specific reason we would rationalise this
result, so it is named here rather than argued afterwards.

## HYPOTHESIS BACKLOG

See `references/backlog.md`. This one is row 3.
```

## What this becomes on disk

Because the experiment runs in the real scene tree, there is no new `prototypes/` directory
and therefore no `PROTOTYPE.md`. The record goes in two places instead:

1. The block above, as the pre-playtest note, so `signoff --note` has something to quote.
2. `locate`'s `feedback:` line in `asteroid.loops.yaml`, sharpened from *"reads as valuable"*
   to name the commitment behaviour -- then `python tools/loop/loop.py prove locate` re-runs
   so `playtests/locate.md` regenerates from it.

Had it needed its own directory, the four fields come first and unchanged, and the block goes
underneath:

```markdown
# sense_hook_radar

**Question:** If the player fires one radar pulse in a dark tunnel and a single contact
returns at a bearing, will they change heading toward it before the node is visible?
**Beat:** locate
**Verdict by:** 2026-09-05
**Verdict:** open
```
