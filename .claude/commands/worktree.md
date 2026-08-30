---
description: Create an isolated worktree and branch for a chunk of work, and move this session into it.
argument-hint: "<words for the branch name> | exit | list"
---

Give a chunk of work its own branch and its own checkout, somewhere the main
checkout's uncommitted changes cannot reach, and move this session into it.

Worktrees always go under `C:\Users\jonat\repos\worktrees\<repo>\<slug>` — outside
every working tree, so a worktree never shows up in another repo's `git status` and
never inherits another checkout's uncommitted files.

## Dispatch on $ARGUMENTS

- Empty, `list`, or `status` — run `git worktree list`, say which entry this session
  is in, and stop. Create nothing.
- `exit`, `done`, or `leave` — call `ExitWorktree` with `action: "keep"`. Never
  `remove`: a worktree entered by path cannot be removed by that tool anyway, and
  deleting a branch is the human's call. If they then want it gone, confirm and run
  `git worktree remove <path>` followed by `git branch -d <name>`.
- Anything else — the words are the name. Run the create flow below.

A branch you genuinely want to call `exit` or `list` has to be created by hand. That
is the price of the shorthand and it is worth it.

## Create flow

1. **Slug the name.** Lowercase `$ARGUMENTS`, turn each run of non-alphanumerics
   into a single `-`, strip leading and trailing `-`. `refactor globals` becomes
   `refactor-globals`.

2. **Find the main checkout.** `git rev-parse --path-format=absolute --git-common-dir`
   and take its parent. Use this, not `--show-toplevel`, which gives the wrong answer
   when the session is already inside another worktree. `<repo>` is that directory's
   basename.

3. **Resolve collisions.** The target is `C:\Users\jonat\repos\worktrees\<repo>\<slug>`.
   If that directory exists, or `git rev-parse --verify <slug>` resolves, or
   `git rev-parse --verify refs/remotes/origin/<slug>` resolves, try `<slug>-2`, then
   `-3`, until both the path and the branch name are free. Say which name you settled
   on and why — never rename silently.

4. **Pick the base.** `git fetch origin`, then read the default branch from
   `git symbolic-ref refs/remotes/origin/HEAD`, falling back to `origin/main`. If the
   fetch fails, say so and branch from the local `origin/main` ref rather than
   aborting — a stale base is better than no worktree.

5. **Create it.** `git worktree add -b <name> <path> <base>`. Uncommitted changes in
   the main checkout are untouched and do not follow. This is the point of the
   command.

6. **Copy `.env`** from the main checkout, if it has one. It is the only ignored file
   the tooling needs — `tools/deploy-cloudflare.py` and `tools/publish-itch.py` read
   it. Copy it rather than linking it: it holds live credentials and must stay
   uncommitted in both places. Copy nothing else, and in particular do not copy
   anything untracked under `.claude/` — the skills, commands and rules staying
   behind is deliberate.

7. **Warm the Godot import cache**, only if `<path>/project.godot` exists. Find the
   binary with the repo's own helper rather than hardcoding a path — it already
   handles the `.cmd`/`.bat` shim that mangles arguments, and honours `GODOT_BIN`:

   ```
   python -c "import sys;sys.path.insert(0,'tools');import godot_bin;print(godot_bin.find_godot())"
   <godot> --headless --path <worktree> --import
   ```

   Run it from the worktree and give it a generous timeout: a cold import of this
   project takes minutes. If Godot is not found or the import fails, warn and carry
   on — the editor imports on first open regardless.

8. **Enter it.** Call `EnterWorktree` with `path` set to the new worktree. Step 5
   registered it in `git worktree list`, which is what the tool requires. If it
   refuses the path, do not retry — print the path and say to start a session there
   instead.

9. **Report** the branch name and whether it had to be adjusted, the base commit's
   sha and subject, the worktree path, and what is absent by design: every untracked
   `.claude/` skill, command and rule; `releases/`; `addons/zylann.voxel/`. Say how
   to come back — `/worktree exit`.

## What carries over, and what does not

The git hooks work in a worktree unmodified. `core.hooksPath` is the relative
`.githooks`, which git resolves against each worktree's own root, and `.githooks/` is
tracked — so there is nothing to re-run and no reason to open the editor first.

`tools/loop/loop.py` derives its repo root from its own `__file__`, so `/spine` and
the rest measure the worktree they are run in, not the main checkout.

Until this command's own commit reaches `main`, a worktree branched from `origin/main`
will not contain it. Exiting from inside one still works — say "exit the worktree" and
the built-in tool handles it — but `/worktree exit` itself only resolves from a
checkout that has the file.

This command does not commit, push, or open a PR, and it never removes a worktree or
deletes a branch without being asked.
