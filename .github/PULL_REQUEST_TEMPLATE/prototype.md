<!--
For a prototype under prototypes/ -- something built to answer a question, not
to ship. Wrong template? Swap ?template=prototype.md in the URL for
art_asset.md, or drop the parameter entirely for the general one.

prototypes/README.md: "These are not expected to have production code, reusable
components, or be fully functional." Review this PR on whether it answers its
question, not on code quality.
-->

## The question

<!--
What did you build this to find out? One sentence, phrased so it can be answered.
"Is a tentacle creature chasing you actually scary?" is a question.
"Tentacle creature" is not.
-->

## The answer

<!-- Your honest read, having played it. Pick one and say why. -->

- [ ] **Keep** — it works, and here is what should carry into the real game
- [ ] **Kill** — it does not work, and here is what we learned anyway
- [ ] **Needs another pass** — promising, but one specific thing is unresolved

<!-- Why. A kill is a successful prototype; do not talk yourself into a keep. -->

## Watch it

<!--
Drag a video or GIF in here. For anything about feel -- movement, chase, weight,
timing -- this is the review. A reviewer who has to build and run it to see what
you mean will usually just approve it instead.
-->

## Run it

**Scene:** `res://prototypes/<name>/<name>_prototype.tscn`
**How:** open that scene and run the *current* scene with **F6**. <!-- F5 runs the main scene and you will get the main menu instead. -->

### Controls

| Input | Does |
|---|---|
| <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> | |
| <kbd>Esc</kbd> | free the mouse, reach the tuning panel |
| | |

## Tuning

---

## Checklist

- [ ] Defaults live in `<name>_knobs.gd` as documented `const`s — that file is still the one place a default is written down.
- [ ] Every live-tunable has an `@export_range` in `<name>_settings.gd`.
- [ ] Settings verify cleanly:
      `godot --headless --path <root> res://prototypes/tools/verify_prototype_settings.tscn`
- [ ] `gdformat` and `gdlint` pass on every `.gd` I touched.
