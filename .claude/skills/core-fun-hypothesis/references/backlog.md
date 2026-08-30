# The hypothesis backlog

Every question this game has admitted to, scored, with the beat its answer travels to.

This is repo state and it goes stale -- the same thing the other house skills keep in
`references/inventory.md`. It is called a backlog rather than an inventory because an
inventory lists what the repo owns and this lists what it owes.

## It is not a second list

`documentation/design/game_design_document.md` already has *"Open Questions — Answered by
Prototyping"*, numbered #1-#9 with `Blocks` and `Owner` columns. The numbering is stable:
#7 is struck through and marked *"Answered in 0.0.3"* rather than deleted, because the level
briefs cite questions by number.

**A hypothesis is an instalment against one of those numbers, not a new entry.** #2 has four
candidate senses; a hypothesis tests one of them. Answering it does not close #2 unless it
passes -- a reject removes one candidate and the next becomes the current experiment.

If a hypothesis matches no number, that is a finding worth stating: either it belongs to an
existing question and you have not looked hard enough, or the GDD's list has a hole.

## The scored rows

`foundational importance × uncertainty × cost of being wrong`, 1-5 each. Arithmetic shown,
because a score nobody can check is an opinion with a number stuck on it.

| Score | GDD | Question | Beat | Imp | Unc | Cost |
|---|---|---|---|---|---|---|
| **125** | #3 | Is hauling and parking the tethered power/oxygen box scary, or just annoying? | `first_crank` | 5 | 5 | 5 |
| **100** | #1 | Does zero-G in tight spaces feel good, and does the player keep agency while disoriented? | `first_tunnel` | 5 | 4 | 5 |
| **64** | #2 | Which sense is the hook -- light, proximity radar, visor shader, or sound? | `locate` | 4 | 4 | 4 |
| **48** | #4 | Does the risk/reward pull of going deeper actually work? | `deeper_branch` | 4 | 4 | 3 |
| **36** | #8 | What is the in-run difficulty ramp across five minutes? | the run loop | 3 | 4 | 3 |
| **24** | #5 | Creature detection specifics -- noise, radius, attenuation, timeouts | `contact` | 4 | 2 | 3 |
| **24** | #6 | Does the creature wall-crawl, or float and navigate around obstacles? | `contact` | 3 | 2 | 4 |
| **24** | #9 | Can the creature threaten players sheltering in the car? | `extraction` | 3 | 4 | 2 |
| — | ~~#7~~ | ~~Does thrust consume breathable air?~~ **Closed in 0.0.3: yes, untethered only.** | `first_tunnel` | — | — | — |

Two scores are deliberately low on **uncertainty** rather than importance, and the reason is
that the work is already done: #5 is specified at length in
`documentation/design/alien/perception.md` and `suspicion.md`, and #6 is largely settled in
code -- the clinger crawls, leaps and latches, and already gets pushed off surfaces it cannot
crawl. Both still matter; neither is where the unknowns are.

## What this table is telling you

**The highest-scoring question in the game has no prototype and no code.** #3 sits on
`first_crank`, which is `status: not_started`, `est_hours: 12`, and carries the spine's own
verdict: *"the single largest hole in the MVP -- pillar 4 (every convenience costs something
shared) has no code behind it at all."* `prototypes/power_and_lighting/` exists and has never
been promoted.

That is the point of scoring. **#3 does not need twelve hours to be answered** -- "is paying
a shared bill frightening or irritating?" is a decision question, and decision questions
settle near the top of the ladder. One person, a corridor, a power meter that drains on a
fixed schedule, and a crank that costs you your position for eight seconds will tell you more
than the built system will, and cost an afternoon.

`python tools/loop/loop.py next` proposes `locate`, and it is not wrong: it orders by tier
and then by the order a player meets the beats. **`next` picks the beat to build; the score
picks the question to answer.** They are different jobs and they disagree here. Say which one
you are doing before you start.

## Undeclared prototypes

`loop.py audit` prints 22 rows under `prototypes/`, all `undeclared`. Two -- `shared/` and
`tools/` -- are infrastructure and will never carry a question, so the honest count is 20.

Three are worth naming because they are questions that already had code:

- **`power_and_lighting/`** -- #3's prototype, never promoted, no date.
- **`mineral_discovery/`** -- #2's prototype, and a husk: the `.tscn` names three `.gd` files
  that are not in the tree, and git has never tracked the directory. An experiment cut
  without anyone writing `cut`.
- **`core_loop/`** -- its README states its question in prose (*"do they add up to a loop
  worth playing?"*), which is the closest thing to a declared prototype here, and is still a
  Rule 1 violation on its face.

Writing a new question before dating these adds to the ratio the rule was written to stop.
