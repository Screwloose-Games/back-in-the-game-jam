# The output block

What the skill terminates with. `references/worked-example.md` has it filled in against a
real beat.

Every heading is load-bearing. If one cannot be filled in, that is the finding -- an empty
`WHAT WOULD CHANGE OUR MIND` means there is no hypothesis yet, and an empty `MOCK / SCRIPT /
REMOVE` means Rule 4 has not been applied.

```markdown
## CORE FUN HYPOTHESIS

We are testing whether ______ causes target players to ______.
False if ______.

Answers GDD open question #N. Beat: <loop>.<step>.

## WHY THIS IS THE MINIMUM HYPOTHESIS

- **One uncertainty:** ... (and what is *not* uncertain, so the scope is visible)
- **One causal mechanism:** ... -> ... -> ...
- **Primary player response:** ... (a behaviour, not a feeling)
- **Failure is diagnosable because:** ... (what is switched off, and what a null
  result therefore names)

## TARGET PLAYER

Who, how many, what they are told, and what they are not told.
Whether audience fit is being tested here -- and if it is, that is a different
hypothesis.

## MINIMUM PROTOTYPE

**Given** the player already understands ...,
**When** the player ...,
**Then** ... occurs,
**And we observe whether** ... occurs.

## MOCK / SCRIPT / REMOVE

- **Mock** -- ... (prefer a tuning value; a number in the diff beats code to delete)
- **Fix** -- ... (held constant across every run, so the observation means one thing)
- **Script** -- ...
- **Remove** -- ...

Every surviving item answers "what uncertainty does this help resolve?"

## PASS

The observable result that means continue investing, with a threshold.
-> capture evidence, then `loop.py signoff <step> --pass`, or `Verdict: promote`.

## REVISE

The result that means the causal link is real and a term is wrong.
-> `--fail --note "REVISE: ..."`, or `Verdict: open` with a new date.
Change exactly one thing.

## REJECT

The result that means the mechanism is not the answer.
-> `--fail --note "REJECT: ..."`, or `Verdict: cut` / `harvest`.
The mechanism goes; the beat stays unless someone decides otherwise.

## TEST VALIDITY

Confirm before interpreting anything above:
- Did they perform the interaction at all?
- Did they understand the situation?
- Did they understand the available action?
- Did they perceive the consequence, and attribute it to what they did?

Any no makes the run INVALID. `Verdict:` unchanged, date moves once with the
reason on the line. A second invalid run is a REJECT.

## WHAT WOULD CHANGE OUR MIND

The sentence you would be uncomfortable reading back, naming the sunk cost you
would otherwise rationalise from.

## HYPOTHESIS BACKLOG

The ranked rest, or a pointer to `references/backlog.md`.
```

## Where it goes

**Running in the real scene tree** -- the default. There is no new directory and no
`PROTOTYPE.md`. The block becomes the pre-playtest note, so `signoff --note` has something to
quote, and the beat's `feedback:` line in `asteroid.loops.yaml` is sharpened to name the
predicted response. Re-run `python tools/loop/loop.py prove <step>` afterwards so
`playtests/<step>.md` regenerates -- it is generated and says *"Do not hand-edit."*

**Running in `prototypes/`** -- the four fields come **first and unchanged**, because
`loop.py audit` and a human skim both depend on them being at the top. The block goes
underneath:

```markdown
# <name>

**Question:** If <one interaction>, will <one predicted player response>?
**Beat:** <step>
**Verdict by:** 2026-09-05
**Verdict:** open

<the output block>
```

`Verdict by:` is a date, and it is today plus days -- not "soon". It is the timebox, and it
survives the session that a kitchen timer does not.
