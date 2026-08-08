@tool
extends EditorPlugin

## Wires this clone's git hooks to the versioned .githooks/ directory.
##
## Git deliberately gives a repository no way to install its own hooks on clone
## - if it did, `git clone` would be remote code execution. So the setup step
## cannot be removed, only moved somewhere nobody has to remember. In a Godot
## project the one thing every contributor does without being asked is open the
## project in the editor, so that is what triggers it.
##
## Everything this can reach is one `git config` write inside the current
## checkout. It runs no hook, fetches nothing, and installs nothing - the
## checks themselves live in .githooks/pre-commit, which is reviewed like any
## other file in the repo.
##
## Deliberately not `pre-commit install`: that copies a shim into .git/hooks/
## and the copy goes stale when the hook changes. core.hooksPath points at a
## tracked directory instead, so editing .githooks/pre-commit reaches every
## clone on the next pull with no second setup step.

const HOOKS_PATH := ".githooks"


func _enter_tree() -> void:
	# Deferred so a slow or hung `git` cannot stall the editor coming up. It has
	# never had to run before this frame and it does not have to run in it.
	_wire_hooks.call_deferred()


func _wire_hooks() -> void:
	var project_root := ProjectSettings.globalize_path("res://")

	# No .git means an exported build, a zip download, or a checkout laid out
	# some way this cannot reason about. None of them are errors and none of
	# them want a warning every time the editor opens.
	if not DirAccess.dir_exists_absolute(project_root.path_join(".git")):
		return

	if not DirAccess.dir_exists_absolute(project_root.path_join(HOOKS_PATH)):
		push_warning(
			(
				(
					"repo_hooks: %s/ is missing, so git hooks were left alone. "
					+ "Pull the branch that adds it."
				)
				% HOOKS_PATH
			)
		)
		return

	var current := _run_git(project_root, ["config", "--get", "core.hooksPath"])
	# Already pointed where it belongs. The common case by far - every editor
	# open after the first - so it says nothing and does nothing.
	if current == HOOKS_PATH:
		return

	# Someone has pointed this clone somewhere else on purpose. Overwriting it
	# would be taking a decision that is theirs to take.
	if current != "" and current != HOOKS_PATH:
		push_warning(
			(
				(
					"repo_hooks: core.hooksPath is set to '%s', not '%s'. Left as is - "
					+ "the repo's checks in %s/pre-commit are not running."
				)
				% [current, HOOKS_PATH, HOOKS_PATH]
			)
		)
		return

	var exit_code := OS.execute(
		"git", ["-C", project_root, "config", "core.hooksPath", HOOKS_PATH], []
	)
	if exit_code != 0:
		# git missing from PATH is the ordinary reason. Worth one line, because
		# the commit gate is silently off until it is fixed.
		push_warning(
			(
				"repo_hooks: could not set core.hooksPath (git exited %d); commits are unchecked."
				% exit_code
			)
		)
		return

	print_rich(
		(
			(
				"[color=green]repo_hooks:[/color] git hooks wired to %s/. "
				+ "GDScript is now linted and format-checked on commit."
			)
			% HOOKS_PATH
		)
	)


## Runs git in the checkout and hands back its trimmed stdout, or "" if it
## failed. A non-zero exit is expected here - `config --get` returns 1 for a key
## that is simply not set, which is the first-run case.
func _run_git(project_root: String, arguments: Array[String]) -> String:
	var output := []
	var git_arguments: Array[String] = ["-C", project_root]
	git_arguments.append_array(arguments)
	var exit_code := OS.execute("git", git_arguments, output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()
