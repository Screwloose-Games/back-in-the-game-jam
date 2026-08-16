extends SceneTree

## Structural rules. Nothing here runs the creature; it inspects what the source actually
## says.
##
##   godot --headless --path <root> \
##     --script res://gameplay/creature/behavior/tools/verify_behavior_static.gd
##
## These are the checks the GUT suite structurally cannot make, because they are about the
## SHAPE of the module rather than its behaviour. A tree/ file that has quietly grown a
## reference to CreatureSuspicion, or an action that calls submit_disconfirmation to make a
## hotspot resolve crisply, passes every unit test -- and has lost the property those tests
## exist to protect.
##
## Everything runs on the first _process() tick rather than in _initialize(). Nodes added
## during SceneTree._initialize() never receive _ready(), so a check written there measures
## the harness instead of the module.

const MODULE: String = "res://gameplay/creature/behavior"
const DIRECTOR: String = "res://gameplay/director"

## THE RULE THAT MAKES THE FRAMEWORK REUSABLE RATHER THAN REUSABLE-SHAPED.
##
## `tree/` is a behavior tree, not an alien's behavior tree. A node that names a creature
## subsystem cannot be lifted into anything else, and "reusable" that is never checked against
## a second user is a claim rather than a property. The context is the only thing that crosses
## the boundary, and it is declared outside this directory.
const DOMAIN_TOKENS: Array[String] = [
	"CreatureSuspicion",
	"CreatureNavigation",
	"CreaturePerception",
	"SuspicionHotspot",
	"PlayerSuspicionCandidate",
	"EncounterDirective",
	"BehaviorConfig",
]

## Belief has exactly three doors -- evidence, disconfirmation, and the clock -- and Behavior
## is not one of them. An action that reached in and lowered a number would resolve hotspots
## crisply and work visibly better, which is precisely why no behavioural test would flag it.
const BELIEF_TOKENS: Array[String] = [
	"submit_evidence",
	"submit_disconfirmation",
	"reduce_suspicion",
	"clear_hotspot",
	"mark_investigation_complete",
]

## Behavior reasons from what the creature believes. The Director is the only system allowed
## to know the truth, precisely because it is the only one forbidden from acting on it -- so a
## group lookup or a player transform here is the alien finding people for reasons the design
## never sanctioned. The facade is exempt for `nests`, which are level geometry rather than
## players, and is checked separately.
const WORLD_TOKENS: Array[String] = [
	"get_nodes_in_group", "global_position", "get_world_3d", "RayCast3D", "Area3D"
]

## Physics. Nothing in this module may query the world: Navigation and Perception each own a
## probe, and Behavior reaches the world only through them.
const PHYSICS_TOKENS: Array[String] = [
	"intersect_ray", "intersect_shape", "direct_space_state", "PhysicsRayQueryParameters3D"
]

## Wall clocks. Behavior's clock is fed from the delta it is handed. Anything here ignores
## get_tree().paused and Engine.time_scale, so an alien would keep deciding in a paused game,
## and no test could drive it.
const CLOCK_TOKENS: Array[String] = [
	"Time.get_", "OS.get_ticks", "Engine.get_physics_frames", "Engine.get_process_frames"
]

## Only actions may command. A condition that commanded would fire once per frame forever,
## because the tree re-evaluates every condition from the root every tick.
const COMMAND_TOKENS: Array[String] = [
	"set_goal", "clear_goal", "request_activity_scan", "request_geometry_scan", "goal.request"
]

## The facade legitimately reads the scene to collect nests and to resolve the body position,
## both of which are level geometry rather than player state. The sandbox plants nests and
## walks the body on a keypress -- debug scaffolding outside the decision layer, and `/sandbox/`
## is not covered by `_is_harness`. Exempting these two by name is what lets the rule stay
## absolute for everything that DECIDES anything.
const WORLD_EXEMPT: Array[String] = ["creature_behavior.gd", "behavior_sandbox.gd"]

## This file names every banned token, in code rather than in a comment, in order to ban them
## -- so comment stripping cannot save it and it has to exclude itself.
const SELF_FILE: String = "verify_behavior_static.gd"

var _failures: int = 0
var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	_check_layout()
	_check_uid_sidecars()
	_check_tree_is_domain_free()
	_check_no_belief_writes()
	_check_no_world_reads()
	_check_no_physics()
	_check_no_wall_clock()
	_check_only_actions_command()
	_check_scene_loads()
	_check_config_invariants()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	quit(1 if _failures > 0 else 0)
	return true


func _check_layout() -> void:
	var before: int = _failures
	var expected: Array[String] = [
		"creature_behavior.gd",
		"behavior_config.gd",
		"behavior_context.gd",
		"behavior_goal.gd",
		"creature_state.gd",
		"tree/bt_node.gd",
		"tree/behavior_tree.gd",
		"hfsm/creature_hfsm.gd",
		"hfsm/behavior_state.gd",
		"hfsm/states/unalerted_state.gd",
		"hfsm/states/investigating_state.gd",
		"hfsm/states/hunting_state.gd",
		"hfsm/states/retreating_state.gd",
		"world/creature_nest.gd",
		"world/nest_memory.gd",
		"sandbox/behavior_sandbox.gd",
		"sandbox/behavior_sandbox.tscn",
		"README.md",
	]
	for relative: String in expected:
		if not FileAccess.file_exists(MODULE.path_join(relative)):
			_fail("layout", "%s is missing" % relative)
	for relative: String in ["encounter_directive.gd", "encounter_report.gd", "README.md"]:
		if not FileAccess.file_exists(DIRECTOR.path_join(relative)):
			_fail("layout", "director/%s is missing" % relative)
	_pass_if("layout", before, "%d expected files present" % (expected.size() + 3))


## This repo commits .uid sidecars alongside every script. A missing one is not cosmetic:
## Godot regenerates it with a fresh id, and every scene referencing the script by uid then
## points at nothing.
func _check_uid_sidecars() -> void:
	var before: int = _failures
	var scripts: PackedStringArray = _all_scripts()
	for path: String in scripts:
		if not FileAccess.file_exists(path + ".uid"):
			_fail("uid", "%s has no .uid sidecar" % path.get_file())
	_pass_if("uid", before, "%d scripts have their .uid sidecar" % scripts.size())


## The one that matters most. See DOMAIN_TOKENS.
func _check_tree_is_domain_free() -> void:
	var before: int = _failures
	for path: String in _files(MODULE, ".gd"):
		if not path.contains("/tree/") or _is_harness(path):
			continue
		var code: String = _read_code(path)
		for token: String in DOMAIN_TOKENS:
			if code.contains(token):
				_fail(
					"tree",
					(
						"%s names %s; a tree that knows what an alien is cannot be reused"
						% [path.get_file(), token]
					)
				)
	_pass_if("tree", before, "the behavior tree framework names nothing from the creature")


func _check_no_belief_writes() -> void:
	var before: int = _failures
	for path: String in _all_scripts():
		if _is_harness(path):
			continue
		var code: String = _read_code(path)
		for token: String in BELIEF_TOKENS:
			if code.contains(token):
				_fail(
					"belief",
					(
						"%s names %s; the creature investigates and Perception observes the result"
						% [path.get_file(), token]
					)
				)
	_pass_if("belief", before, "nothing in the module writes belief")


func _check_no_world_reads() -> void:
	var before: int = _failures
	for path: String in _all_scripts():
		var file: String = path.get_file()
		if _is_harness(path) or WORLD_EXEMPT.has(file) or file == "creature_nest.gd":
			continue
		var code: String = _read_code(path)
		for token: String in WORLD_TOKENS:
			if code.contains(token):
				_fail(
					"world",
					(
						"%s names %s; Behavior decides from belief, never from the truth"
						% [file, token]
					)
				)
	_pass_if("world", before, "no part of the decision layer reads the world directly")


func _check_no_physics() -> void:
	var before: int = _failures
	for path: String in _all_scripts():
		if path.get_file() == SELF_FILE:
			continue
		var code: String = _read_code(path)
		for token: String in PHYSICS_TOKENS:
			if code.contains(token):
				_fail(
					"physics",
					(
						"%s names %s; Behavior reaches the world through Navigation and Perception"
						% [path.get_file(), token]
					)
				)
	_pass_if("physics", before, "nothing in the module touches the physics server")


func _check_no_wall_clock() -> void:
	var before: int = _failures
	for path: String in _all_scripts():
		if path.get_file() == SELF_FILE:
			continue  # This file names them in order to ban them.
		var code: String = _read_code(path)
		for token: String in CLOCK_TOKENS:
			if code.contains(token):
				_fail(
					"clock",
					(
						"%s reads %s; the injected delta is the module's only time"
						% [path.get_file(), token]
					)
				)
	_pass_if("clock", before, "nothing in the module reads a wall clock")


## fsm.md: actions are the only nodes permitted to command anything. A condition that
## commanded makes the reactive re-tick unsound, because every condition is re-evaluated
## from the root every frame.
func _check_only_actions_command() -> void:
	var before: int = _failures
	for path: String in _files(MODULE, ".gd"):
		if _is_harness(path) or not path.contains("/conditions/"):
			continue
		var code: String = _read_code(path)
		for token: String in COMMAND_TOKENS:
			if code.contains(token):
				_fail(
					"conditions",
					(
						"%s names %s; a condition that commands fires once per frame forever"
						% [path.get_file(), token]
					)
				)
	_pass_if("conditions", before, "only actions command anything")


## Loading, INSTANTIATING and ATTACHING A SCRIPT are three different failures, and the third
## is the one that catches this check out: a .tscn whose script fails to parse still loads,
## still instantiates, and still returns a perfectly valid Node -- Godot prints the parse error
## and hands back a SCRIPTLESS node. The scene then reports as fine and does absolutely nothing
## when you run it. That is exactly what happened to suspicion while its sandbox was written.
func _check_scene_loads() -> void:
	var before: int = _failures
	var scenes: PackedStringArray = _files(MODULE, ".tscn")
	if scenes.is_empty():
		_fail("scenes", "no scenes found; the sandbox should be one of them")
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("scenes", "%s did not load" % path)
			continue
		var node: Node = packed.instantiate()
		if node == null:
			_fail("scenes", "%s loaded but did not instantiate" % path)
			continue
		if FileAccess.get_file_as_string(path).contains('type="Script"'):
			if node.get_script() == null:
				_fail(
					"scenes",
					(
						"%s names a script but instantiated without one -- it failed to parse"
						% path.get_file()
					)
				)
		node.free()
	_pass_if("scenes", before, "%d scenes load, instantiate and keep their script" % scenes.size())


func _check_config_invariants() -> void:
	var failures: PackedStringArray = BehaviorConfig.new().invariant_failures(
		PerceptionConfig.new()
	)
	for line: String in failures:
		_fail("config", line)
	if failures.is_empty():
		_pass("config", "a default BehaviorConfig agrees with a default PerceptionConfig")


# ----- helpers -----


## tests/ and tools/ are the verification harness, not the module. The invariants suite has
## to name a banned method to assert its absence, which is the same trap this file's own
## self-exclusion exists for. The wall-clock and physics rules still apply everywhere.
func _is_harness(path: String) -> bool:
	return path.get_file() == SELF_FILE or path.contains("/tests/") or path.contains("/tools/")


## Source with comments stripped, so a check for a banned token does not fire on the
## docstring explaining why the token is banned. That is not hypothetical: the wall-clock and
## domain-free rules both lived in the GUT suite first and both failed on their own prose.
func _read_code(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var stripped: String = ""
	for line: String in text.split("\n"):
		var at: int = line.find("#")
		stripped += (line if at < 0 else line.substr(0, at)) + "\n"
	return stripped


func _all_scripts() -> PackedStringArray:
	var found: PackedStringArray = _files(MODULE, ".gd")
	found.append_array(_files(DIRECTOR, ".gd"))
	return found


func _files(root: String, extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	_walk(root, extension, found)
	return found


func _walk(folder: String, extension: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var path: String = folder.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk(path, extension, found)
		elif entry.ends_with(extension):
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("[%-10s] PASS  %s" % [tag, message])


## PASS only if this check added no failures. The unconditional version prints PASS directly
## underneath its own FAIL lines, which is the kind of summary that gets skimmed and believed.
func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		_pass(tag, message)
