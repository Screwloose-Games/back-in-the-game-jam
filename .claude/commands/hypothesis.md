---
description: Reduce an idea to one minimum falsifiable hypothesis and design the smallest prototype that can disprove it.
argument-hint: "<an idea, or a beat id, or a prototype directory>"
---

Turn $ARGUMENTS into one hypothesis that could turn out to be wrong. If nothing was
given, ask what is being considered — do not pick one from the spine on the user's
behalf.

Read the `core-fun-hypothesis` skill first. This command is the sequence; the skill
is the judgement.

## 1. Find the real uncertainty

Run `python tools/loop/loop.py next` and `python tools/loop/loop.py audit`, and read
the "Open Questions — Answered by Prototyping" table in
`documentation/design/game_design_document.md`. Between them they hold every question
this game has already admitted to.

If what was asked for is already question #1 to #9 there, say so and use its number.
A new question needs an argument for why it is new.

First, though, the disqualifying question: **is this uncertain, or merely unbuilt?**
Merely unbuilt is a beat. Say so and point at `/next-step` rather than wrapping known
work in an experiment.

## 2. Score, and name the loser

`foundational importance × uncertainty × cost of being wrong`, 1-5 each. Show the
arithmetic — a score nobody can see is an opinion with a number stuck on it. The
highest is the current experiment; everything else goes in the ranked backlog and
gets written down, not discarded.

`loop.py next` picks the beat to build. The score picks the question to answer. They
disagree right now, and when they do, say which one you are doing.

## 3. Reduce it until it can fail

Run the five gates. Any that trip get named **by number**, out loud, with the
compliant alternative in the same message:

> This hypothesis is not minimum. It violates Rules 1 and 3: you are testing the
> radar and the outline shader together, so a failure would not say which sense
> failed. The minimum version is …

If the user overrules you, challenge once and concede in the same message. Twice is
nagging.

## 4. Design the smallest thing that can disprove it

Climb the ladder — paper, clickable mock, scripted interaction, simplified
implementation, actual system — and say why you passed each rung. Then write the
prototype as Given / When / Then / And we observe whether.

List what is mocked, what is fixed, what is scripted, what is removed. Prefer mocking
with a tuning value: it reads as a number in the diff rather than as code somebody
will forget to take out.

## 5. Write the interpretation before anything is built

Pass, revise and reject, all three defined now. The validity check. The one sentence
about what would change our mind, naming the sunk cost you would otherwise
rationalise from. These are worthless written afterwards, and there is no way to tell
afterwards which it was.

## 6. Record it where the repo already looks

- **In the game** (the default): sharpen the step's `feedback:` in
  `documentation/design/loop/asteroid.loops.yaml`, then
  `python tools/loop/loop.py prove <step>` so the playtest script regenerates.
- **In `prototypes/`**: a `PROTOTYPE.md` beside the scene — the four fields first and
  unchanged, the output block underneath.

Either way `Verdict by:` is a date, and it is today plus days, not "soon".

## 7. Stop

You cannot run the playtest and you cannot write the verdict. Report the hypothesis,
the prototype, the interpretation rules, and what the experiment costs — including
any sign-off it will expire. The human plays it; `/signoff` records what they saw.
