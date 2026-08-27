extends Node

## Runs every McpTestSuite in res://tests/ from the command line. Invoke it with:
##
##     godot --headless --path <root> res://tests/run_tests.tscn
##
## As a SCENE named on the command line, not as `--script`. Nodes added during
## SceneTree._initialize() never receive _ready(), which is the same reason every
## verify_*.gd in prototypes/ ships with a .tscn wrapper.
##
## WHY THIS EXISTS ALONGSIDE THE MCP RUNNER. The suites themselves are the ones the
## godot-ai `test_run` tool discovers, and that tool is the pleasant way to run them while
## the editor is open. It also requires the editor to be open, which makes it useless in a
## terminal and useless in CI. This file is fifty lines that give the same suites a process
## exit code.
##
## It calls run_suite() per suite rather than run_suites(), deliberately: run_suites()
## toggles McpLogBuffer.console_echo and snapshots the edited scene root, both of which are
## editor-only concerns that have no meaning here.

const TESTS_DIR := "res://tests"


func _ready() -> void:
	_run()


func _run() -> void:
	var discovery := _discover()
	var suites: Array = discovery["suites"]
	var errors: PackedStringArray = discovery["errors"]

	for message: String in errors:
		printerr("  LOAD  %s" % message)

	if suites.is_empty():
		printerr("no test suites found in %s - nothing was actually verified" % TESTS_DIR)
		get_tree().quit(1)
		return

	# No _reset_suite_state() and no _free_tracked() here, and neither is an oversight.
	# Every suite is a fresh .new() so its suite-level flags already hold their defaults,
	# and run_suite() frees tracked objects after each test itself. Calling either would
	# also trip gdlint's private-method-call rule for no gain.
	var runner := McpTestRunner.new()
	for suite: McpTestSuite in suites:
		suite.suite_setup({})
		if suite._suite_failed:
			printerr(
				"  FAIL  %s <suite_setup>: %s" % [suite.suite_name(), suite._suite_failed_message]
			)
			continue
		runner.run_suite(suite)
		suite.suite_teardown()

	_report(runner.get_results(true), errors.size())


func _report(results: Dictionary, load_errors: int) -> void:
	for entry: Dictionary in results.get("results", []):
		var label := "%s.%s" % [entry["suite"], entry["test"]]
		if entry.get("skipped", false):
			print("  SKIP  %s: %s" % [label, entry["message"]])
		elif entry["passed"]:
			print("  PASS  %s (%d assertions)" % [label, entry["assertion_count"]])
		else:
			printerr("  FAIL  %s: %s" % [label, entry["message"]])

	var failed := int(results.get("failed", 0)) + load_errors
	print(
		(
			"%d suite(s), %d passed, %d failed, %d skipped, %d ms"
			% [
				int(results.get("suite_count", 0)),
				int(results.get("passed", 0)),
				failed,
				int(results.get("skipped", 0)),
				int(results.get("duration_ms", 0)),
			]
		)
	)
	get_tree().quit(1 if failed > 0 else 0)


## Same contract as the MCP handler's discovery: res://tests/test_*.gd, non-recursive,
## every script an McpTestSuite subclass. Resilient - one broken script reports itself and
## leaves the rest runnable.
func _discover() -> Dictionary:
	var suites: Array = []
	var errors := PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		errors.append("%s could not be opened" % TESTS_DIR)
		return {"suites": suites, "errors": errors}

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			var path := "%s/%s" % [TESTS_DIR, file_name]
			var script := (
				ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
			)
			if script == null:
				errors.append("%s failed to load (parse error?)" % file_name)
			elif not script.can_instantiate():
				errors.append("%s cannot be instantiated" % file_name)
			else:
				var instance: Variant = script.new()
				if instance is McpTestSuite:
					suites.append(instance)
				else:
					errors.append("%s is not an McpTestSuite subclass" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	suites.sort_custom(
		func(a: McpTestSuite, b: McpTestSuite) -> bool: return a.suite_name() < b.suite_name()
	)
	return {"suites": suites, "errors": errors}
