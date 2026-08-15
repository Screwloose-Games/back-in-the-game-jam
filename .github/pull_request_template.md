<!--
There are two more specific templates. GitHub has no picker for pull requests,
so switch by adding ?template= to the compare URL you are on right now:

  ?expand=1&template=prototype.md    a prototype -- "is this loop fun?"
  ?expand=1&template=art_asset.md    art, audio or a 3D model

From the CLI:  gh pr create --template prototype.md

Delete any section below that does not apply. An empty heading is worse than no
heading -- half the PRs in this repo's history have an empty body, which is what
this template exists to fix.
-->

## What changed

<!-- One or two sentences. What is different after this merges? -->

## Why

<!--
Link the issue so the board moves:
  Closes #123    the issue is finished
  Partial #123   a step toward it, issue stays open
If there is no issue, say what prompted the change instead.
-->

## How to verify

<!--
How does a reviewer confirm this works, without guessing?
The scene to open, the command to run, the thing to look at. If it is visual,
a screenshot or a short video is faster to review than a paragraph.
-->

## Notes for the reviewer

<!--
Optional. Anything you would say out loud while walking someone through this:
a tradeoff you are unsure about, something deliberately left undone, a rule you
had to work around. Say it here rather than waiting to be asked.
-->

---

## Checklist

- [ ] I ran the gate for what I touched (see [CONTRIBUTING.md](https://github.com/Screwloose-Games/back-in-the-game-jam/blob/main/CONTRIBUTING.md#before-you-push)) — or CI is green.
- [ ] Every asset I added or changed has its `.import` sidecar in this PR. *(Godot hides these in its own dock — check the OS file explorer.)*
- [ ] I did not hand-edit a generated file. *(`PIPELINE.md`, the `pipeline:subtasks` blocks, `documentation/pipeline/images/` — change `pipeline.yaml` and re-render instead.)*
- [ ] If I changed a convention, I changed the rule that enforces it, not just the file that broke it.
