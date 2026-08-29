# Player responses, and how to see them

One **primary** response decides pass, revise or reject. The six below are **secondary**:
they explain a result, and they never overturn one. Read this while preparing a session,
not while designing the hypothesis.

## The rule that governs all of them

> **Behaviour outweighs self-report when the two conflict.**

Not because players lie -- because they are answering a different question. Asked "did that
feel good?", a player answers about the last thirty seconds, in front of the person who built
it, and wants to be helpful. What they did with their hands answered the real question while
they were still busy playing.

So each response below is given as a behaviour first. The self-report line is the thing that
will contradict it, and lose.

## The six

### Comprehension -- did they understand what happened?

**Behaviour:** they repeat the interaction deliberately within the first minute, at a moment
that makes sense. Wrong-time repetition is fumbling, not comprehension.

**Contradicting self-report:** *"Yeah, I got it."* Almost universal, and almost worthless. Ask
instead: *"What just happened?"* and *"What made that happen?"* -- attribution is the half
that fails.

**Why it comes first:** comprehension is not a secondary response at all when it fails. It is
the validity check, and a failure makes the run INVALID rather than a reject.

### Agency -- did they feel like the cause?

**Behaviour:** they change approach on the second attempt. A player who thinks the outcome
was theirs varies something; a player who thinks it was the game's repeats identically or
stops.

**Contradicting self-report:** *"I don't know what I did."* Sometimes true and decisive.
Sometimes said by someone who then reproduces the outcome three times running -- believe the
hands.

### Satisfaction -- was the payoff worth the cost?

**Behaviour:** the pause after the outcome. A satisfied player stops for a beat and looks at
what they did. An unsatisfied one is already moving.

**Contradicting self-report:** the most inflated of the six, because it is the one players
think you want to hear. Weight it lowest of all.

### Curiosity -- did it raise a question they want answered?

**Behaviour:** unprompted exploration off the critical path -- pointing the sense hook at
something you did not place, going the wrong way on purpose.

**Contradicting self-report:** *"I wondered what was over there"* said about a place they
never went. Wondering is free; going costs something.

### Mastery -- is there a skill worth having?

**Behaviour:** measurable improvement across attempts on a dimension nobody named. Faster,
cheaper, fewer corrections.

**Contradicting self-report:** *"I think I'm getting the hang of it."* Check the numbers. Two
identical attempts and a confident report is a flat skill curve.

**Caveat:** mastery needs repetitions, and most minimum prototypes are one interaction. If
mastery is what you are testing, that is a primary response and the prototype needs a
different shape.

### Replay intent -- do they want another one?

**Behaviour:** they start again without being asked, or ask whether they can. The strongest
signal on this list, and the one closest to core fun.

**Contradicting self-report:** *"I'd definitely play more of this."* Said to be kind, at the
end, to the person who made it. Only the unprompted restart counts.

## Running the session

- **Five players.** Enough that four-of-five is a threshold and one outlier does not decide
  it; few enough to run in an afternoon.
- **One sentence of instruction**, written down before the first run and identical for all
  five. Every extra sentence is a mock of the comprehension you are not testing -- which is
  fine, as long as it is the *same* mock each time.
- **No coaching after the first sentence.** The urge to help is the single biggest threat to
  validity here, and it is strongest when the design is failing. If you find yourself
  explaining, the run is already INVALID; note it and stop.
- **Record the run**, or at minimum the timestamps. `PASS` needs evidence attached before
  `signoff --pass` will accept it (`tools/loop/loop_cli/signoff.py:102`), and
  `documentation/design/loop/evidence/` does not exist in the tree yet -- so capture it while
  the mocks are still in place.
- **Ask afterwards, never during.** Two questions, in this order: *"What happened?"* then
  *"What made it happen?"* Both are comprehension checks. Opinions come last, if at all.

## Writing the primary response

It has to be observable in a recording by someone who was not there:

- *"the first heading change after the pulse is toward the contact bearing"* -- observable.
- *"voluntarily starts a second run without being asked"* -- observable.
- *"finds the tension enjoyable"* -- not observable, and no session settles it.

If the primary response cannot be written this way, the hypothesis is not finished, and no
amount of playtesting will finish it.
