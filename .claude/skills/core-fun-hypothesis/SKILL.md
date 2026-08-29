---
name: core-fun-hypothesis
description: Reduce a game idea to one minimum falsifiable hypothesis about this Godot game and design the cheapest experiment that can prove it wrong - one uncertain interaction, one predicted player response, one observable test, one failure condition. Use when starting a prototype, when writing or repairing a PROTOTYPE.md Question line, when a design argument cannot be settled by talking, when a beat's feedback line is still a guess, or when someone proposes building a system in order to find out whether an idea is fun.
---

# Core fun as a falsifiable hypothesis

`.claude/rules/prototypes.md` opens with the whole of this file's premise -- **a prototype is
a question with code attached** -- and requires every prototype to write that question down.
Nothing writes it. `python tools/loop/loop.py audit` prints 22 rows under `prototypes/` and
every one says `undeclared`, which is what a gate with nothing behind it looks like.

This file is what goes behind it. It reduces an idea until exactly one thing about it is
uncertain, then designs the smallest artefact that can settle that one thing. The reduction
is the work -- an idea that survives it unchanged was already a hypothesis, and almost
nothing is. The question it keeps asking is not *how do we prototype this?* but:

> **What is the most important thing about this game that we do not yet know, and what is
> the cheapest valid experiment capable of proving us wrong?**

A hypothesis is finished when it has this shape and no more of it:

> **One uncertain interaction → one predicted player response → one observable test → one
> failure condition.**

The invariants are in `.claude/rules/prototypes.md`, which loads whenever you touch anything
under `prototypes/` -- it owns the `PROTOTYPE.md` fields, the four verdicts and the expiry
date. This file is the procedure that fills them in.

## Ask this first

> **What would have to happen for us to abandon this idea?**

If there is no answer, there is no hypothesis, and saying so is the honest end of this
skill. Two answers are wrong in ways worth naming:

- ***"Is it fun?"*** names no interaction, predicts no response, and nothing observable
  makes it false. A question that cannot be answered "no" leaves `Verdict:` on `open`
  forever, which is precisely the state all 22 directories are in.
- ***"We'll know once the system is built."*** That is not an experiment, it is the thing
  an experiment exists to avoid paying for.

And one prior question, because it disqualifies more ideas than the gates do: **is this
uncertain, or merely unbuilt?** Merely unbuilt is a beat -- `python tools/loop/loop.py next`
names one and `/next-step` builds it. Wrapping known work in an experiment pays the
experiment's overhead and returns nothing.

## The five gates

A hypothesis is **not minimum** if any of these is true:

1. More than one mechanic or interaction is being tested.
2. More than one primary player response determines success.
3. Failure could reasonably be blamed on multiple unrelated systems.
4. The prototype requires systems that are not causally necessary.
5. Success would still leave substantial ambiguity about why it worked.

When one is violated, **name the number**. "Too broad" is not a finding; it gives the
designer nothing to cut. Then supply the compliant alternative in the same message --
criticism without a repaired hypothesis is a veto, and a veto is not a design contribution:

> This hypothesis is not minimum. It violates Rules 1 and 3: you are testing the radar
> pulse *and* the visor outline shader together, so a failure would not say which sense
> failed.
>
> Minimum-compliant: *[the repaired form].*

Gates 3 and 5 are the two that get waved through, and they cost the most. Rule 3 is about
**diagnosability** -- a result you cannot attribute is not evidence. Rule 5 is its mirror on
the winning side: a pass you cannot explain cannot be built on, because you do not know what
to preserve. A hypothesis whose success would leave a GDD open question exactly as open as
it was has failed Rule 5 by definition.

`references/worked-example.md` runs one idea from its first framing through a near miss to
the repaired hypothesis and the output block it produces.

## Choosing which hypothesis

Most ideas contain several. Score each, 1-5 per factor:

> foundational importance × uncertainty × cost of being wrong

**Foundational importance** -- how much of the rest depends on this being true.
**Uncertainty** -- how far you are from knowing; something you are 90% sure of scores low
even when it matters enormously. **Cost of being wrong** -- what has to be thrown away if
you find out late instead of now.

Show the arithmetic. A score nobody can see is an opinion with a number stuck on it.

The highest becomes the current experiment; every other one goes into a ranked backlog and
stays visible, because the discarded ones are the reason the chosen one is chosen.

**The backlog is not a new list.** `documentation/design/game_design_document.md` already has
*"Open Questions — Answered by Prototyping"*, numbered #1-#9 with stable numbering. A
hypothesis is an **instalment against one of those numbers** -- cite it (`Answers GDD open
question #2`), or argue why it is a new one. `references/backlog.md` holds the scored rows.

Two tie-breaks. A hypothesis under a `must` beat outranks one under a `could`, which is the
ordering `.claude/rules/loop-spine.md` already enforces. And every hypothesis must terminate
in a `Beat:` -- if it cannot, the rule has already answered you: it is *"a prototype whose
answer has nowhere to go."*

## One primary player response

Name **one primary response**. It alone decides pass, revise or reject, and it has to be
something a person does, not something they feel:

- *"changes heading toward the contact before the node is visible"* -- observable, decisive.
- *"finds it satisfying"* -- not observable, and no playtest settles it.

Track secondary responses as diagnostics only -- comprehension, agency, satisfaction,
curiosity, mastery, replay intent. They explain a result; they never overturn one.

> Primary: commitment -- the first heading change after the pulse is toward the contact.
> Secondary: comprehension, perceived agency, satisfaction.

**Behaviour outweighs self-report when the two conflict.** A player who says the hook felt
useful and then swims straight past the node it flagged has told you the truth twice, and
the second one counts. `references/player-responses.md` gives each secondary response, the
behaviour that signals it, and how to observe it without coaching.

**The spine has usually written this already -- sharpen it, do not duplicate it.** Every step
in `asteroid.loops.yaml` carries a `feedback:` field describing what the player should
perceive, and `/next-step` calls it the acceptance criterion: *"a beat the player cannot
perceive is not delivered."* `locate`'s already reads *"The node reads as valuable before you
commit to it"* -- one predicted response about one mechanic. A second prediction beside it
gives one beat two acceptance criteria that drift apart. Edit `feedback:` in place, then run
`python tools/loop/loop.py prove <step>` so `playtests/<step>.md` regenerates; it is
generated and says *"Do not hand-edit."*

## Prerequisites

For every prerequisite, ask:

> Does this need to be true for the hypothesis to be tested?

If **no** -- it is not a prerequisite. Remove it; Rule 4 exists for exactly this.

If **yes**, one of two things follows:

- **Already established** -- mock it, fix it, script it. A settled question does not get
  re-litigated inside someone else's experiment.
- **Still uncertain** -- it is a separate hypothesis, and it comes *first*. It outranks the
  current one however it scored, because the current experiment cannot produce a readable
  result until it is settled.

This is the step that saves the most time and gets skipped the most. An uncertain
prerequisite left switched on is Rule 3 arriving later, at greater cost.

## The minimum prototype

> **Build the smallest artefact that can make the causal hypothesis succeed or fail,
> replacing every unrelated system with mocks, fixed values, scripted outcomes, or manual
> facilitation.**

Take the earliest rung that can still falsify the hypothesis, and say why you passed each
one you passed:

```
paper or manual → clickable mock → scripted interaction → simplified implementation → the actual system
```

Most hypotheses about a *decision* -- is this trade-off interesting, is this cost legible --
settle two or three rungs earlier than anyone expects, because the decision is real long
before the simulation behind it is. Hypotheses about *feel* are the honest exception: nothing
below "simplified implementation" tells you whether zero-G thrust is satisfying.

Then interrogate every remaining piece:

> What uncertainty does this help resolve?

No good answer, remove it. Answer it out loud for anything that took real time -- that is
where the unnecessary work hides, because effort already spent is the hardest thing to delete.

### Where it runs, and what is switched on

Two questions, and conflating them is what makes this argument go in circles. **Where the code
lives** is answered by `.claude/rules/prototypes.md` -- prefer the real scene tree. **What is
switched on** is answered by the minimum-prototype rule above.

So mock inside the game. A tuning value set to zero is the cheapest mock here:
`radar_power_per_pulse` is `@export_range(0.0, 20.0, 0.05)` on `PlayerTuning`
(`player.tuning.gd:342`), so zero is already legal. A mock made of numbers is a diff a person
can read and revert; a mock made of code is what gets committed by accident and found two
weeks later.

A new directory under `prototypes/` is for when mocking in the game would cost more than the
experiment. It owes a `PROTOTYPE.md` from its first commit.

## The experiment

Write it in this shape:

```
Given  the player already understands [required context]
When   the player performs [minimum causal interaction]
Then   [observable consequence] occurs
And    we observe whether [predicted player response] occurs
```

`Given` is the mocked, granted, established world -- everything Rule 4 let you delete. `When`
is the one interaction. `Then` is what the game does, and it must be observable to you. `And`
is the one thing you are measuring, and it must be observable in the player.

A short sequence is allowed when the experience inherently requires one --
**observe → decide → consequence** is the common case, because a decision that was never
informed is not a decision. Every step must still serve the same single hypothesis. Two
steps testing two things is Rule 1 wearing a sequence.

## Before it runs

**The target player.** Name them. Someone who has played Lethal Company predicts different
behaviour from someone who never has, and a result read against the wrong one is noise. If
audience fit is *itself* what you are unsure about, that is a separate hypothesis -- do not
let it ride along inside this one, where it will be indistinguishable from a design failure.

**The anti-rationalisation record.** Before the prototype runs, answer:

> What evidence would cause us to change our mind?

Write it into `PROTOTYPE.md` in full, and **name the sunk cost you would otherwise
rationalise from**:

> If three of five players commit to a contact only after it is visible, we stop calling the
> radar the sense hook -- even though `systems/radar/` is the most finished sense we have and
> is already owned by this beat.

Written before, it is a commitment. Written after, the same sentence is a rationalisation, and
there is no way to tell them apart later -- which is why the timing, not the wording, is the
load-bearing part.

## Reading the result

**The validity check comes first**, before any verdict:

> Did the player understand the situation, the available action, and the resulting
> consequence sufficiently for their reaction to actually test the hypothesis?

If not, the run is **INVALID**. It is not a failed hypothesis and must not be recorded as
one -- you tested your explanation, not your design.

Then one of three:

- **PASS** -- evidence sufficient to continue investing.
- **REVISE** -- the causal relationship looks promising, but something about the interaction
  or the payoff needs altering.
- **REJECT** -- the player understood and experienced the mechanic correctly, and the
  predicted response consistently failed to emerge.

All three are defined **before** anything is built. Defined afterwards they are a reading of
the result, not a test of it.

## Recording the verdict

> PASS, REVISE and REJECT are what you **decide**. `open`, `promote`, `harvest` and `cut` are
> what you **write down**. One decision, one record; a fourth word goes in a note, never in a
> new field.

| Outcome | `PROTOTYPE.md` `Verdict:` | In-game equivalent | What happens next |
|---|---|---|---|
| **PASS** | `promote` | `signoff <step> --pass --note "PASS: ..."` | Translate it into `systems/`, `prefabs/` or the level, add the paths to the step's `delivery.owns`, delete the prototype. |
| **REVISE** | stays `open`, **new** `Verdict by:`, `Question:` rewritten with the altered term | `--fail --note "REVISE: ..."` | Change exactly one thing and re-run. A revision that changes two things has stopped being an experiment. |
| **REJECT** | `cut`, or `harvest` if one part earns a place elsewhere | `--fail --note "REJECT: <mechanism> is not the answer"` | Delete it. *"A prototype that answered 'no' has done its whole job."* |
| **INVALID** | stays `open`, date moved **once**, reason on the line | `--fail --note "INVALID: ..."` | Fix the comprehension problem and re-run. |

Four things this table is doing on purpose:

- **REJECT kills the mechanism, not the beat.** `signoff --cut` sets `delivery.status: cut`
  and retires the beat from the spine. `locate` is `tier: must` -- it has to exist however
  the sense hook turns out. Only a decision to drop the beat itself writes `--cut`.
- **REVISE and REJECT both land on `--fail`**, and that is right: `/signoff` already says a
  `--fail` *"leaves the beat at `ready` with the note recorded ... it is still built, and it
  still needs a human."* The note carries the discrimination. A second REVISE with an
  unchanged prediction is a REJECT in disguise.
- **A date moves once.** An INVALID run consumed calendar time and produced no evidence, so
  it earns one new date with the reason on the line. A second INVALID is not another
  comprehension problem to fix -- a mechanic two sets of players could not read has told you
  something about the mechanic, and the outcome is REJECT.
- **PASS is expensive.** `promote` means becoming subject to every rule the game code is
  subject to, and `godot-prefabs` puts it as *"Promoting means translating, never moving."*
  If you are not willing to pay that this week, the honest verdict is `harvest`.

A **REJECT points at the spine, not at the code.** If the response never emerges, the step's
`feedback:` promise is what is wrong, and amending it belongs in the same change --
`.claude/rules/design-docs.md` asks for the passage marked as amended, the argument stated,
what did *not* change said, and the consequence followed into anything that leaned on the old
claim. The Stop-hook drift check will not catch this one; it matches changed code against
docs that name it.

## When the designer overrules you

You can be overruled, and sometimes you should be -- the designer knows things about the game
that are not written down. Challenge **once**, then build what they asked for:

> Keeping live traffic simulation violates Rule 4. The hypothesis only concerns whether
> choosing the architectural intervention is satisfying; real simulation adds implementation
> cost and another possible cause of failure.
>
> Minimum-compliant: show fixed before-state metrics, allow the architectural decision, then
> reveal predetermined after-state metrics.
>
> You can keep the simulation if you believe its behaviour is itself part of what you need to
> test.

Name the gate by number, give the compliant design, concede in the same message. Then stop
arguing -- a second challenge is nagging and buys nothing -- and record on the `Question:`
line what was kept and why, so the next reader knows the scope was chosen rather than
overlooked, and a muddy result has somewhere to point.

## This supersedes the vendored advice

`.claude/skills/prototype-fast` is an engine-general vendored skill, pinned in
`skills-lock.json` with a hash and deliberately left unedited so a pack update cannot clobber
a local fix. When the two disagree, this one wins.

It gets Rule 1 independently -- *"If you have two questions, build two prototypes. A
prototype that tests everything tests nothing"* -- and its greyboxing is the
minimum-prototype rule with the ladder left out. Where it is wrong for this repo is the
pitfall *"prototyping in the real codebase"*: `.claude/rules/prototypes.md` says the opposite
and wins, and the two are less opposed than they look once you separate where the code lives
from what is switched on.

**Three names for one decision is the actual risk.** Collapse it:

| `prototype-fast` | This skill | What gets written down |
|---|---|---|
| KEEP | PASS | `Verdict: promote`, or `signoff --pass` |
| REFACTOR | REVISE | `Verdict: open` with a new date, or `signoff --fail` |
| KILL | REJECT | `Verdict: cut`, or `harvest` if a part survives |
| *(no equivalent)* | INVALID | `open`, date moved once, hypothesis untouched |

KEEP / KILL / REFACTOR is retired here -- the four verdicts are the ones a file holds and
`loop.py audit` reads, and they are the only vocabulary with a tool behind it. That
`prototype-fast` has no INVALID is its most expensive omission: under its rules a player who
never understood the mechanic produces a KILL, and the idea dies of a presentation problem.

The promotion procedure itself is already written -- `.claude/skills/godot-prefabs/SKILL.md`
`## Promoting a prototype` -- and is not restated here.

## Gotchas

- **`prototypes/mineral_discovery/` is a husk.** Its `.tscn` names
  `mineral_discovery_prototype.gd`, `mineral_cave.gd` and `mineral_hud.gd`; none of the three
  is in the tree, and `git ls-files` returns nothing for the directory. That is the sense-hook
  question with the code already gone from under it -- an experiment cut without anyone
  writing `cut`, which is the exact failure this file exists to make visible.
- **22 rows, 20 real prototypes, zero questions.** Two of the `undeclared` rows -- `shared/`
  and `tools/` -- are infrastructure that will never have a question. Do not read the other
  twenty as permission: writing the twenty-first question before anybody has dated the
  existing twenty adds to the ratio the rule was written to stop. Date one you did not open.
- **"Hypothesis" already means something else here.** The alien specs use it for the
  creature's internal model of where prey is (`documentation/design/alien/suspicion.md:987`,
  `perception.md:388`). That is the creature's hypothesis; this is the designer's.
- **`loop.py audit` only checks that `PROTOTYPE.md` exists** --
  `tools/loop/loop_cli/audit.py:72`. It never reads the fields. A `declared` row means a file
  is present, not that the question inside it is minimum.
- **`signoff` refuses twice over.** It rejects a `--pass` with no evidence attached
  (`signoff.py:102`), and `documentation/design/loop/evidence/` does not exist in the tree
  yet though the CLI names it; and it rejects any verdict while the step's files are dirty
  (`signoff.py:88`), because the verdict is pinned to a commit. So capture the run while the
  mocks are in place, and decide which mocks ship *before* the playtest.
- **A sign-off expires the moment a commit touches the step's `owns` paths.** Running an
  experiment in the real scene tree therefore costs a re-playtest of every signed-off beat it
  touches, pass or fail. `loop.py own <path>` tells you which. Today that is free -- `0 of 11
  beats signed off` -- and it will not be free next week.
- **`loop.py next` and the score can disagree, and both are right.** `next` orders by tier
  then by the order a player meets the beats, and today proposes `locate`. The score puts
  `first_crank` first, because the spine's own comment calls it *"the single largest hole in
  the MVP -- pillar 4 ... has no code behind it at all"* with `est_hours: 12` behind it.
  `next` picks the beat to build; the score picks the question to answer. Say which you are
  doing.

## Checking your work

```bash
python tools/loop/loop.py audit                    # every prototype: declared or undeclared
python tools/loop/loop.py next                     # the beat the build queue wants next
python tools/loop/loop.py own <path>               # which beat an answer would travel to
python tools/loop/loop.py validate                 # the spine still parses after a feedback edit
python tools/loop/loop.py prove <step>             # regenerate playtests/<step>.md from feedback

grep -n 'Question:\|Beat:\|Verdict' prototypes/*/PROTOTYPE.md   # every open question and its date
```

Read the `Question:` line aloud and finish the sentence *"we will know this is false
when —"*. If you cannot finish it, it is not a hypothesis, and `Verdict:` will stay `open`
forever. **A `Question:` line containing "and" is Rule 1 until proven otherwise.**

The output block this skill terminates with is in `references/output-template.md`, filled in
against a real beat in `references/worked-example.md`, and the standing scored list is in
`references/backlog.md`.
