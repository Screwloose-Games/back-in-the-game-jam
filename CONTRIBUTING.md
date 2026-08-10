# Contributing

A game-jam template with a strict asset pipeline. The strictness is not
ceremony — the build is web-first on the GL Compatibility renderer, so a model
that is quietly 10× over budget or a `.wav` at the wrong sample rate costs
everyone frames. Nearly every rule here is enforced by a script, and the script,
the pipeline document and this file are kept in sync on purpose.

If you read one other thing, make it
[`documentation/pipeline/PIPELINE.md`](documentation/pipeline/PIPELINE.md) for
assets or [`.github/workflows/README.md`](.github/workflows/README.md) for what
CI will say about your PR.

## Setup

**Do not run `pre-commit install`.** Hooks are already wired: opening the project
in the Godot editor once points `core.hooksPath` at the tracked `.githooks/`
directory, via `addons/repo_hooks`. `pre-commit install` would drop a shim into
`.git/hooks/` that takes precedence and then goes stale.

`.githooks/pre-commit` degrades gracefully:

| You have | You get |
|---|---|
| `pre-commit` on `PATH` | the full `.pre-commit-config.yaml` — gdlint, gdformat, 3D model validation |
| only `gdlint`/`gdformat` | those two |
| neither | a warning, and the commit goes through |

So `pip install pre-commit` is worth having and is not setup. It builds its own
isolated environments, which means you do **not** need `gdtoolkit`, `numpy`,
`pyyaml` or `jsonschema` on your own `PATH`.

## Before you push

Run the gate for whatever you touched — these are the same commands CI runs:

```
python .github/scripts/validate-model-files.py <model>    # 3D
python .github/scripts/validate-aseprite-files.py <file>  # 2D
python .github/scripts/validate-audio-files.py <file>     # audio
gdformat <file> && gdlint <file>                          # GDScript
```

`gdformat <file>` rewrites; the hook runs `--check`, which reports without
rewriting, so a commit is never silently mutated.

**Local hooks are fast feedback, not enforcement.** `--no-verify` skips them, and
so does never opening the editor. CI is the copy that decides.

## Branches

`snake_case`, named for the thing rather than the person:
`tunnel_lighting`, `crawler_chase`. History is inconsistent about this
(`tunnels`, `proto-object-transport`, `asteriod_prototyping` — typo shipped and
is now permanent), which is exactly the argument for picking one.

Branch off `main`. The validators have no `branches:` filter on purpose, so a PR
into a feature branch is gated just as hard as one into `main`.

## Opening a pull request

There are three templates. **GitHub shows no picker for pull requests** — the
default is applied automatically, and the other two are reached by adding
`?template=` to the compare URL:

| Use | How |
|---|---|
| Anything else | just open the PR — you get the default |
| A prototype | append `?expand=1&template=prototype.md` |
| Art, audio, a model | append `?expand=1&template=art_asset.md` |

```
https://github.com/Screwloose-Games/back-in-the-game-jam/compare/main...YOUR_BRANCH?expand=1&template=art_asset.md
```

From the CLI:

```
gh pr create --template prototype.md
gh pr create --template art_asset.md
```

Link the issue in the body — `Closes #123` when the issue is finished,
`Partial #123` when it is a step toward it. An issue's Subtasks list is the
authoritative acceptance criteria for that asset; the PR templates deliberately
do not duplicate it.

### What review is for

CI already checks naming, formats, budgets, axes and `.import` sidecars, and it
blocks the PR when it is unhappy. Review is for what it cannot check: whether a
model faces the right way in the render CI posts, whether dimensions match the
**issue** rather than the current mesh, and whether a prototype answers the
question it was built to answer.

`.github/CODEOWNERS` requests a review automatically on pipeline and CI paths.
`prototypes/` and `assets/` are deliberately unowned so jam work never waits.

## Conventions worth knowing up front

- **Naming:** `[prefix]_[asset_name]_[descriptor]_[variant]`, lowercase with
  underscores. `sm_` static mesh, `sk_` skeletal, `t_` texture, `prefab_`/`level_`
  scenes. No hyphens, no `.fbx`, no `.mp3`, ever.
- **Facing:** models are built facing +Y in Blender, which exports to −Z — Godot's
  `Vector3.FORWARD`. Deliberately *not* the glTF spec's +Z-front convention;
  matching the engine matters more than matching viewers.
- **Units:** metres. 1 Blender unit = 1 m.
- **Commit `.import` sidecars** with every asset. Godot hides them in its own
  dock — check the OS file explorer.
- **Some files are generated.** `PIPELINE.md`, the `pipeline:subtasks` blocks in
  the issue templates, and `documentation/pipeline/images/` all come from
  `documentation/pipeline/pipeline.yaml`. Hand-edit them and CI fails on drift;
  change `pipeline.yaml` and re-render with `tools/pipeline/pipeline.py`.
- **`prototypes/` and `assets/art/examples/` are exempt** from the conventions on
  purpose. Do not tidy them into line — several of those models exist in order to
  fail.

## The rule behind the rules

**Prefer changing the rule over changing the file that broke it.** If a
convention is wrong, fix it in `pipeline.yaml` and re-render, rather than working
around it in one asset. That is why the pipeline document and the validators are
drift-checked against each other: a convention cannot change in a script without
the document changing in the same PR.
