---
paths:
    - "prototypes/**"
---

# Prototypes have to expire

A prototype is a question with code attached. It is exempt from the shared
conventions on purpose (see `CLAUDE.md`), and `prototypes/AGENTS.md` covers how
to wire one up. What this rule covers is the other end: when it stops.

There are 21 directories here and one shipping level. That ratio is what happens
when prototypes have no expiry -- each one was worth starting, and nothing ever
made anybody decide.

## Every prototype declares its question

A new prototype gets a `PROTOTYPE.md` beside its scene, and it is four lines:

```markdown
# <name>

**Question:** Can a tethered box be hauled through a tunnel without the tether
feeling like a bug?
**Beat:** first_crank            <!-- the step in the spine this serves -->
**Verdict by:** 2026-09-05       <!-- a date, not "soon" -->
**Verdict:** open                <!-- open | promote | harvest | cut -->
```

`python tools/loop/loop.py audit` lists the ones with no `PROTOTYPE.md`, which is
the honest way to find out how many questions nobody wrote down.

### The question has to be answerable wrong

`Question:` is one interaction, one predicted player response, and the observation
that would show the prediction false. "Is the mining fun?" is not a question this
file can hold: nothing observable makes it false, so `Verdict:` will never be
anything but `open`, and the date will move forever.

Two questions is two prototypes. A `Question:` joined by "and" is the commonest
way a prototype loses the ability to fail -- when the result is bad, the half that
failed is not identifiable, and there is no honest verdict to write.

## The four verdicts

- **promote** -- the answer is worth keeping. It moves into `systems/`,
  `prefabs/` or the level, gets claimed by the step it serves, and becomes
  subject to every rule the game code is subject to. The prototype directory goes.
- **harvest** -- one part of it is worth keeping. Lift that part, name what you
  took, delete the rest.
- **cut** -- the question is answered and the answer is no, or the question stopped
  mattering. Delete it. A prototype that answered "no" has done its whole job;
  keeping it around is not respect for the work, it is just clutter.
- **open** -- still running, and the date says how long that stays true. A date
  may be moved once, with the reason on the line. A date moved twice is itself a
  verdict: nobody is going to run this experiment.

## Before starting a new one

Ask which beat it serves. A prototype that answers a question no step in
`documentation/design/loop/asteroid.loops.yaml` is waiting on is a prototype whose
answer has nowhere to go -- and with a jam deadline, that is the most expensive
thing in this directory.

Prefer building in the real scene tree. The reason to prototype is that the
question is genuinely unanswered and answering it in the game would cost more
than answering it here. "It is easier to work on in isolation" is not that
reason; it is how the ratio got to 21:1.

## Traffic runs one way

A prototype may use a system. A system may never depend on a prototype -- that is
`systems/README.md`'s rule, and it is what makes promotion a move rather than a
copy.

---

Getting from a design idea to a question of that shape, and to the smallest thing
that can answer it: the `core-fun-hypothesis` skill, or `/hypothesis`.
