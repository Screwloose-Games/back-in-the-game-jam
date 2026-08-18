extends SceneTree

## Structural rules. Nothing here runs the creature; it inspects what the source and
## the scenes actually say.
##
##   godot --headless --path <root> \
##     --script res://gameplay/creature/suspicion/tools/verify_suspicion_static.gd
##
## These are the checks the GUT suite structurally cannot make, because they are about
## the SHAPE of the module rather than its behaviour. A module that has quietly grown a
## `get_nodes_in_group` in hotspot_field.gd, or a wall clock in evidence_memory.gd,
## still passes every unit test -- and has lost the property those tests exist to
## protect.
##
## Everything runs on the first _process() tick rather than in _initialize(). Nodes
## added during SceneTree._initialize() never receive _ready(), so a check written
## there measures the harness instead of the module.

const MODULE: String = "res://gameplay/creature/suspicion"

## THE HIGHEST-VALUE LIST IN THIS FILE, and the analogue of perception's physics seam.
##
## Suspicion is a model of what the creature believes, built entirely from what it was
## told. The moment any file here reads the world directly -- a group, a node path, a
## player's transform -- the alien starts finding people for reasons the design never
## sanctioned. It WORKS BETTER, immediately and visibly, which is precisely why no
## behavioural test would ever flag it and why this has to be a build failure.
const WORLD_TOKENS: Array[String] = [
	"get_nodes_in_group",
	"get_node(",
	"get_node_or_null",
	"get_tree()",
	"global_position",
	"global_transform",
	"get_world_3d",
	"RayCast3D",
	"Area3D",
]

## Physics. Unlike perception, NO file here may name any of these -- there is no probe
## in this module and there is not meant to be one. The thin-cave-wall rule is a
## Callable supplied from outside precisely so that stays true.
const PHYSICS_TOKENS: Array[String] = [
	"intersect_ray",
	"intersect_shape",
	"direct_space_state",
	"PhysicsRayQueryParameters3D",
	"PhysicsShapeQueryParameters3D",
	"PhysicsDirectSpaceState3D",
]

## Wall clocks. CreatureSuspicion.clock is the only time in the module and it is fed
## from the delta it is handed. Anything here ignores get_tree().paused and
## Engine.time_scale, so belief would decay in a paused game, and cannot be driven from
## a test.
const CLOCK_TOKENS: Array[String] = [
	"Time.get_", "OS.get_ticks", "Engine.get_physics_frames", "Engine.get_process_frames"
]

## suspicion.md's closing invariants: Suspicion describes belief, it does not act on
## it. `SuspicionHotspot` is a legitimate type name, so the bans are on the verbs.
const COMMAND_TOKENS: Array[String] = [
	"start_hunting",
	"mark_investigation_complete",
	"NavigationServer3D",
	"NavigationAgent3D",
	"request_activity_scan",
	"request_geometry_scan",
	"receive_noise",
]

## Silently unsupported on the GL Compatibility renderer this project targets. They do
## not error -- they simply never appear, so a scene using one looks correct in the
## editor and ships without it.
const FORBIDDEN_RENDER: Array[String] = ["sdfgi_", "ssao_", "ssil_", "ssr_", "volumetric_fog_"]

## The overlay is a Node3D that reads a player's transform to draw the accusation line,
## and the sandbox drives Perception on a keypress. Both are debug scaffolding outside
## the model, and exempting them is what lets the rule above stay absolute for
## everything that actually decides anything.
const WORLD_EXEMPT: Array[String] = [
	"suspicion_debug_draw.gd", "suspicion_debug_panel.gd", "suspicion_sandbox.gd"
]

## This file names every banned token, in code rather than in a comment, in order to
## ban them -- so comment stripping cannot save it and it has to exclude itself.
const SELF_FILE: String = "verify_suspicion_static.gd"

var _failures: int = 0
var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	_check_layout()
	_check_uid_sidecars()
	_check_no_world_reads()
	_check_no_physics()
	_check_no_wall_clock()
	_check_no_commands()
	_check_no_write_api_bypass()
	_check_scene_loads()
	_check_render_settings()
	_check_overlay_uses_vertex_colour()
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
		"creature_suspicion.gd",
		"suspicion_config.gd",
		"evidence_memory.gd",
		"hotspot_field.gd",
		"player_beliefs.gd",
		"records/suspicion_evidence_record.gd",
		"records/suspicion_hotspot.gd",
		"records/suspicion_disconfirmation.gd",
		"records/player_suspicion_candidate.gd",
		"debug/suspicion_debug_draw.gd",
		"README.md",
	]
	for relative: String in expected:
		if not FileAccess.file_exists(MODULE.path_join(relative)):
			_fail("layout", "%s is missing" % relative)
	_pass_if("layout", before, "%d expected files present" % expected.size())


## This repo commits .uid sidecars alongside every script. A missing one is not
## cosmetic: Godot regenerates it with a fresh id, and every scene referencing the
## script by uid then points at nothing.
func _check_uid_sidecars() -> void:
	var before: int = _failures
	var scripts: PackedStringArray = _files(".gd")
	for path: String in scripts:
		if not FileAccess.file_exists(path + ".uid"):
			_fail("uid", "%s has no .uid sidecar" % path.get_file())
	_pass_if("uid", before, "%d scripts have their .uid sidecar" % scripts.size())


## The one that matters. See WORLD_TOKENS.
func _check_no_world_reads() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		if _is_harness(path) or WORLD_EXEMPT.has(file):
			continue
		var code: String = _read_code(path)
		for token: String in WORLD_TOKENS:
			if code.contains(token):
				_fail(
					"world",
					(
						"%s names %s; Suspicion believes only what it was told"
						% [file, token.rstrip("(")]
					)
				)
	_pass_if("world", before, "no part of the model reads the world directly")


func _check_no_physics() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if path.get_file() == SELF_FILE:
			continue
		var code: String = _read_code(path)
		for token: String in PHYSICS_TOKENS:
			if code.contains(token):
				_fail(
					"physics",
					(
						"%s names %s; the region seam is a Callable so this module needs no probe"
						% [path.get_file(), token]
					)
				)
	_pass_if("physics", before, "nothing in the module touches the physics server")


func _check_no_wall_clock() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if path.get_file() == SELF_FILE:
			continue  # This file names them in order to ban them.
		var code: String = _read_code(path)
		for token: String in CLOCK_TOKENS:
			if code.contains(token):
				_fail(
					"clock",
					(
						"%s reads %s; CreatureSuspicion.clock is the module's only time"
						% [path.get_file(), token]
					)
				)
	_pass_if("clock", before, "nothing in the module reads a wall clock")


func _check_no_commands() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		# The sandbox drives Perception on a keypress, which is Behavior's job played by
		# hand and the whole reason the scene is worth opening.
		if _is_harness(path) or file == "suspicion_sandbox.gd":
			continue
		var code: String = _read_code(path)
		for token: String in COMMAND_TOKENS:
			if code.contains(token):
				_fail(
					"commands",
					"%s names %s; Suspicion describes belief, it does not act" % [file, token]
				)
	_pass_if("commands", before, "no file issues a behavioural or perceptual command")


## suspicion.md: "Behavior should not call methods such as reduce_suspicion(),
## clear_hotspot(), mark_investigation_complete()." The unit suite asserts the facade
## has no such method; this asserts nobody has quietly added one anywhere in the module
## for the facade to forward to later.
func _check_no_write_api_bypass() -> void:
	var before: int = _failures
	var banned: Array[String] = [
		"func reduce_suspicion", "func clear_hotspot", "func mark_investigation_complete"
	]
	for path: String in _files(".gd"):
		if _is_harness(path):
			continue
		var code: String = _read_code(path)
		for token: String in banned:
			if code.contains(token):
				_fail(
					"writes",
					(
						"%s declares %s; belief changes through evidence or not at all"
						% [path.get_file(), token]
					)
				)
	_pass_if("writes", before, "evidence and disconfirmation are the only ways in")


## Loading, INSTANTIATING and ATTACHING A SCRIPT are three different failures. The
## third is the one that catches this check out: a .tscn whose script fails to parse
## still loads, still instantiates, and still returns a perfectly valid Node -- Godot
## prints the parse error and hands back a scriptless node. The scene then reports as
## fine and does absolutely nothing when you run it.
func _check_scene_loads() -> void:
	var before: int = _failures
	var scenes: PackedStringArray = _files(".tscn")
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


func _check_render_settings() -> void:
	var before: int = _failures
	for extension: String in [".gd", ".tscn", ".tres"]:
		for path: String in _files(extension):
			if path.get_file() == SELF_FILE:
				continue
			var text: String = _read_code(path)
			for banned: String in FORBIDDEN_RENDER:
				if text.contains(banned):
					_fail(
						"render",
						"%s uses %s, unsupported on GL Compatibility" % [path.get_file(), banned]
					)
	_pass_if("render", before, "no unsupported render effects anywhere in the module")


## Godot does NOT infer vertex_color_use_as_albedo. Without it the whole overlay
## renders FLAT WHITE, a hotspot the creature is certain about looks exactly like one
## it has already searched, and it reads as a bug in the belief model rather than in
## one missing material flag.
func _check_overlay_uses_vertex_colour() -> void:
	var before: int = _failures
	var code: String = _read_code(MODULE.path_join("debug/suspicion_debug_draw.gd"))
	if not code.contains("vertex_color_use_as_albedo"):
		_fail("overlay", "suspicion_debug_draw.gd never sets vertex_color_use_as_albedo")
	if not code.contains("SHADING_MODE_UNSHADED"):
		_fail("overlay", "the overlay material is lit; debug lines must be unshaded")
	_pass_if("overlay", before, "the overlay material renders its vertex colours")


func _check_config_invariants() -> void:
	var failures: PackedStringArray = SuspicionConfig.new().invariant_failures()
	for line: String in failures:
		_fail("config", line)
	if failures.is_empty():
		_pass("config", "a default SuspicionConfig satisfies every invariant")


# ----- helpers -----


## tests/ and tools/ are the verification harness, not the model, and the rules about
## reading the world and issuing commands are exempted there for the same reason.
##
## test_suspicion_invariants.gd asserts CreatureSuspicion has NO method called
## clear_hotspot, which it can only do by naming it. verify_suspicion_runtime.gd builds
## a corridor out of StaticBody3Ds and drives a real CreaturePerception through it,
## because proving the two modules meet correctly is the entire reason it exists. Both
## are the same trap this file's own self-exclusion exists for.
##
## The wall-clock and physics rules still apply everywhere, including here: a harness
## reading Time.get_ticks_msec() would be a genuine problem.
func _is_harness(path: String) -> bool:
	return path.get_file() == SELF_FILE or path.contains("/tests/") or path.contains("/tools/")


## Source with comments stripped, so a check for a banned token does not fire on the
## docstring explaining why the token is banned. Scene and resource files comment with
## `;`, GDScript with `#`.
func _read_code(path: String) -> String:
	var marker: String = ";" if path.ends_with(".tscn") or path.ends_with(".tres") else "#"
	var text: String = FileAccess.get_file_as_string(path)
	var stripped: String = ""
	for line: String in text.split("\n"):
		var at: int = line.find(marker)
		stripped += (line if at < 0 else line.substr(0, at)) + "\n"
	return stripped


func _files(extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	_walk(MODULE, extension, found)
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
	print("[%-9s] PASS  %s" % [tag, message])


## PASS only if this check added no failures. The unconditional version prints PASS
## directly underneath its own FAIL lines, which is the kind of summary that gets
## skimmed and believed.
func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		_pass(tag, message)
