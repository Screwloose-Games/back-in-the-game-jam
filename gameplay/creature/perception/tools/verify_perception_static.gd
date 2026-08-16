extends SceneTree

## Structural rules. Nothing here runs the creature; it inspects what the source and
## the scenes actually say.
##
##   godot --headless --path <root> \
##     --script res://gameplay/creature/perception/tools/verify_perception_static.gd
##
## These are the checks the GUT suite structurally cannot make, because they are
## about the SHAPE of the module rather than its behaviour. A module that has
## quietly grown a physics query in vision.gd, or a wall clock in hearing.gd, still
## passes all 123 unit tests -- and has lost the property those tests were written to
## protect.
##
## Everything runs on the first _process() tick rather than in _initialize(). Nodes
## added during SceneTree._initialize() never receive _ready(), so a check written
## there measures the harness instead of the module.

const MODULE: String = "res://gameplay/creature/perception"

## Physics queries. ONLY perception_probe.gd may name any of these -- that one
## restriction is what lets every other file in the module be tested with no
## physics server at all.
const PHYSICS_TOKENS: Array[String] = [
	"intersect_ray",
	"intersect_shape",
	"direct_space_state",
	"PhysicsRayQueryParameters3D",
	"PhysicsShapeQueryParameters3D",
	"PhysicsDirectSpaceState3D",
]
const PHYSICS_OWNER: String = "perception_probe.gd"

## Wall clocks. CreaturePerception.clock is the only time in the module, and it is
## fed from the delta it is handed. Anything here ignores get_tree().paused and
## Engine.time_scale, and cannot be driven from a test.
const CLOCK_TOKENS: Array[String] = [
	"Time.get_", "OS.get_ticks", "Engine.get_physics_frames", "Engine.get_process_frames"
]

## Section 31: perception produces observations, not behavioural commands, and never
## touches navigation. `SuspicionEvidence` is a legitimate type name, so the bans
## have to be on the verbs rather than on the noun.
const COMMAND_TOKENS: Array[String] = [
	"increase_suspicion",
	"start_hunting",
	"set_hotspot",
	"clear_hotspot",
	"NavigationServer3D",
	"NavigationAgent3D",
	"spatial_memory.",
]

## Silently unsupported on the GL Compatibility renderer this project targets. They
## do not error -- they simply never appear, so a scene using one looks correct in
## the editor and ships without it.
const FORBIDDEN_RENDER: Array[String] = ["sdfgi_", "ssao_", "ssil_", "ssr_", "volumetric_fog_"]

## This file names every banned token, in code rather than in a comment, in order to
## ban them -- so comment stripping cannot save it and it has to exclude itself.
const SELF_FILE: String = "verify_perception_static.gd"

var _failures: int = 0
var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	_check_layout()
	_check_uid_sidecars()
	_check_physics_seam()
	_check_no_wall_clock()
	_check_no_commands()
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


## The files perception.md section 4 asks for, under the names it asks for.
func _check_layout() -> void:
	var before: int = _failures
	var expected: Array[String] = [
		"creature_perception.gd",
		"hearing.gd",
		"vision.gd",
		"touch.gd",
		"geometry_perception.gd",
		"perception_config.gd",
		"perception_probe.gd",
		"perception_scan.gd",
		"observations/suspicion_evidence.gd",
		"observations/disconfirmation_observation.gd",
		"observations/geometry_observation.gd",
		"observations/noise_event.gd",
		# Not in section 4, because section 4 describes the creature and this is the level side
		# of it -- the same place `behavior/world/creature_nest.gd` sits. Nothing in the project
		# emitted a NoiseEvent before it existed.
		"world/player_noise_relay.gd",
	]
	for relative: String in expected:
		if not FileAccess.file_exists(MODULE.path_join(relative)):
			_fail("layout", "%s is missing" % relative)
	_pass_if("layout", before, "%d files present, named as section 4 specifies" % expected.size())


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


## THE HIGHEST-VALUE CHECK IN THIS FILE.
##
## Source is read WITH COMMENTS STRIPPED, because perception_probe.gd's own
## docstring names every banned token in order to ban it, and a raw text search
## cannot tell that apart from using one.
func _check_physics_seam() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		if file == SELF_FILE:
			continue
		var code: String = _read_code(path)
		for token: String in PHYSICS_TOKENS:
			if code.contains(token) and file != PHYSICS_OWNER:
				_fail(
					"seam", "%s names %s; only %s may touch physics" % [file, token, PHYSICS_OWNER]
				)
		# get_world_3d is the one line that binds the probe, and it belongs to the
		# facade because the facade is the only Node in the module.
		if code.contains("get_world_3d") and file != "creature_perception.gd":
			_fail("seam", "%s calls get_world_3d; only the facade binds the probe" % file)
	_pass_if("seam", before, "only %s names a physics query" % PHYSICS_OWNER)


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
						"%s reads %s; CreaturePerception.clock is the module's only time"
						% [path.get_file(), token]
					)
				)
	_pass_if("clock", before, "nothing in the module reads a wall clock")


func _check_no_commands() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if path.get_file() == SELF_FILE:
			continue
		# tests/ is excluded, and only here. test_perception_invariants.gd asserts that
		# CreaturePerception has NO method called start_hunting or set_hotspot, which it
		# can only do by naming them -- the same trap this file's own exclusion exists
		# for. The seam and clock checks still cover tests/, because a test helper doing
		# real physics or reading a wall clock would be a genuine problem.
		if path.contains("/tests/"):
			continue
		var code: String = _read_code(path)
		for token: String in COMMAND_TOKENS:
			if code.contains(token):
				_fail(
					"commands",
					(
						"%s names %s; perception produces observations, not commands"
						% [path.get_file(), token]
					)
				)
	_pass_if("commands", before, "no file issues a behavioural or navigation command")


## Loading, INSTANTIATING and ATTACHING A SCRIPT are three different failures.
##
## The third is the one that caught this check out. A .tscn whose script fails to
## parse still loads, still instantiates, and still returns a perfectly valid Node --
## Godot prints the parse error and hands back a scriptless node. The scene then
## reports as fine and does absolutely nothing when you run it.
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
## renders FLAT WHITE, every colour encoding disappears, and it looks like a bug in
## perception rather than in one missing material flag.
func _check_overlay_uses_vertex_colour() -> void:
	var before: int = _failures
	var path: String = MODULE.path_join("debug/perception_debug_draw.gd")
	var code: String = _read_code(path)
	if not code.contains("vertex_color_use_as_albedo"):
		_fail("overlay", "perception_debug_draw.gd never sets vertex_color_use_as_albedo")
	if not code.contains("SHADING_MODE_UNSHADED"):
		_fail("overlay", "the overlay material is lit; debug lines must be unshaded")
	_pass_if("overlay", before, "the overlay material renders its vertex colours")


func _check_config_invariants() -> void:
	var failures: PackedStringArray = PerceptionConfig.new().invariant_failures()
	for line: String in failures:
		_fail("config", line)
	if failures.is_empty():
		_pass("config", "a default PerceptionConfig satisfies every invariant")


# ----- helpers -----


## Source with comments stripped, so a check for a banned token does not fire on the
## docstring explaining why the token is banned. Scene and resource files comment
## with `;`, GDScript with `#`.
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
