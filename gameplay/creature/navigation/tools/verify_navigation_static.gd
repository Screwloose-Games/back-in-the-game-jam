extends SceneTree

## Structural rules. Nothing here runs the alien; it inspects what the source and the
## scenes actually say.
##
##   godot --headless --path <root> \
##     --script res://gameplay/creature/navigation/tools/verify_navigation_static.gd
##
## These are the checks the GUT suite structurally cannot make, because they are about
## the SHAPE of the module rather than its behaviour. A module that has quietly grown a
## shape cast in nav_graph_builder.gd, or a VoxelTool reference in route_planner.gd,
## still passes every unit test -- and has lost the property those tests were written to
## protect.
##
## Everything runs on the first _process() tick rather than in _initialize(). Nodes
## added during SceneTree._initialize() never receive _ready(), so a check written there
## measures the harness instead of the module.

const MODULE: String = "res://gameplay/creature/navigation"

## World queries. ONLY navigation_probe.gd may name any of these.
##
## THE HIGHEST-VALUE RESTRICTION IN THIS FILE. It is what lets every other file be
## tested with no physics server AND NO VOXEL EXTENSION -- which matters more here than
## it did for perception, because addons/zylann.voxel is a GDExtension that is not
## present in the CI image and is currently not present in the working tree either.
##
## `intersect_ray` earns its place the hard way. `surface_along` and `is_solid` are the
## module's only rays, and a ray is the cheapest world query there is -- which is exactly
## why a controller reaching for one directly is the most likely way this seam erodes.
const WORLD_TOKENS: Array[String] = [
	"intersect_shape",
	"intersect_ray",
	"cast_motion",
	"direct_space_state",
	"PhysicsShapeQueryParameters3D",
	"PhysicsRayQueryParameters3D",
	"PhysicsDirectSpaceState3D",
	"VoxelTool",
	"VoxelBuffer",
	"VoxelTerrain",
]
const WORLD_OWNER: String = "navigation_probe.gd"
## The only files that may call get_world_3d, and therefore the only Nodes in the module
## proper: CreatureNavigation is per-creature, NavigationSource is per-level. Listed rather
## than inferred, so a third is a decision somebody makes on purpose.
const FACADES: Array[String] = ["creature_navigation.gd", "navigation_source.gd"]

## The graph is a plain data structure and must stay one. A NavGraph that could reach a
## probe or a builder could re-measure the world, and Invariant 9's whole mechanism --
## that a believed graph and a real graph are the same type -- would be gone.
const GRAPH_FILES: Array[String] = [
	"nav_graph.gd",
	"nav_node.gd",
	"nav_edge.gd",
	"nav_astar.gd",
	"nav_chunk_revisions.gd",
	"nav_patch_result.gd",
]
const GRAPH_BANNED: Array[String] = [
	"NavigationProbe",
	"NavGraphBuilder",
	"CreatureNavigation",
	"NavKnowledgeGraph",
	"NavKnownNode",
	"NavKnownEdge",
]

## Invariant 8, enforced from the other side. Knowledge learns from observations it is
## handed and from a world graph it is handed; a knowledge layer that could reach a probe
## or a builder would be able to LOOK, and the alien would be omniscient by a shorter
## route than the one Invariant 9 blocks.
const KNOWLEDGE_BANNED: Array[String] = [
	"NavigationProbe", "NavGraphBuilder", "NavGraphPatcher", "CreatureNavigation"
]
## The two files in graph/ that ARE allowed to measure the world, because building and
## patching a graph is exactly the job of turning probe answers into one. Listed rather
## than inferred so that adding a third is a decision somebody makes on purpose.
const GRAPH_TOOLS: Array[String] = ["nav_graph_builder.gd", "nav_graph_patcher.gd"]

## Planning never triggers a bake. Section 24.2 patches the graph on terrain change, not
## on a route query, and a planner that could rebuild would hide a stale graph behind a
## frame spike instead of reporting a partial route.
const ROUTE_BANNED: Array[String] = ["NavGraphBuilder", "NavigationSandboxGeometry"]

## Wall clocks. Every duration in this module is fed from the delta it is handed.
## Time.get_ticks_msec() ignores get_tree().paused and Engine.time_scale, and cannot be
## driven from a test.
const CLOCK_TOKENS: Array[String] = [
	"Time.get_", "OS.get_ticks", "Engine.get_physics_frames", "Engine.get_process_frames"
]

## This module replaces Godot's navigation rather than wrapping it. A stray agent means
## two navigation systems quietly disagreeing about where the alien should be.
const ENGINE_NAV_TOKENS: Array[String] = [
	"NavigationServer3D", "NavigationAgent3D", "NavigationRegion3D", "NavigationMesh"
]

## Silently unsupported on the GL Compatibility renderer this project targets. They do
## not error -- they simply never appear, so a scene using one looks correct in the
## editor and ships without it.
const FORBIDDEN_RENDER: Array[String] = ["sdfgi_", "ssao_", "ssil_", "ssr_", "volumetric_fog_"]

## This file names every banned token, in code rather than in a comment, in order to ban
## them -- so comment stripping cannot save it and it has to exclude itself.
const SELF_FILE: String = "verify_navigation_static.gd"

var _failures: int = 0
var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	_check_layout()
	_check_uid_sidecars()
	_check_world_seam()
	_check_graph_is_pure_data()
	_check_route_does_not_bake()
	_check_knowledge_never_measures()
	_check_no_wall_clock()
	_check_no_engine_navigation()
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


## The files sections 4, 12-19 and 37 ask for, under the names this module uses for
## them. See the README for why they are Nav* rather than the spec's Alien*.
func _check_layout() -> void:
	var before: int = _failures
	var expected: Array[String] = [
		"creature_navigation.gd",
		"navigation_source.gd",
		"navigation_probe.gd",
		"navigation_config.gd",
		"clearance_profile.gd",
		"locomotion_profile.gd",
		"nav_locomotion.gd",
		"nav_inspection_request.gd",
		"locomotion/nav_body_state.gd",
		"locomotion/nav_motion_command.gd",
		"locomotion/nav_surface_sample.gd",
		"locomotion/nav_surface_reading.gd",
		"locomotion/nav_surface_field.gd",
		"locomotion/nav_crawl_candidate.gd",
		"locomotion/nav_avoidance.gd",
		"locomotion/nav_progress_monitor.gd",
		"locomotion/surface_crawl_controller.gd",
		"locomotion/tunnel_swim_controller.gd",
		"locomotion/wiggle_controller.gd",
		"locomotion/nav_leap_candidate.gd",
		"locomotion/nav_leap_planner.gd",
		"locomotion/leap_controller.gd",
		"locomotion/nav_local_planner.gd",
		"graph/nav_node.gd",
		"graph/nav_edge.gd",
		"graph/nav_graph.gd",
		"graph/nav_astar.gd",
		"graph/nav_graph_builder.gd",
		"graph/nav_chunk_revisions.gd",
		"graph/nav_patch_result.gd",
		"graph/nav_graph_patcher.gd",
		"knowledge/nav_knowledge_state.gd",
		"knowledge/nav_known_node.gd",
		"knowledge/nav_known_edge.gd",
		"knowledge/nav_knowledge_update.gd",
		"knowledge/nav_knowledge_graph.gd",
		"knowledge/nav_inspector.gd",
		"route/nav_route.gd",
		"route/nav_route_segment.gd",
		"route/route_planner.gd",
		"route/route_follower.gd",
		"route/nav_route_chooser.gd",
		"debug/navigation_debug_draw.gd",
		"debug/navigation_locomotion_draw.gd",
		"sandbox/navigation_sandbox.tscn",
		"tools/verify_navigation_runtime.tscn",
		"tools/verify_navigation_csg.tscn",
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


## Source is read WITH COMMENTS STRIPPED, because navigation_probe.gd's own docstring
## names every banned token in order to ban it, and a raw text search cannot tell that
## apart from using one.
func _check_world_seam() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		if file == SELF_FILE:
			continue
		var code: String = _read_code(path)
		for token: String in WORLD_TOKENS:
			if code.contains(token) and file != WORLD_OWNER:
				_fail(
					"seam", "%s names %s; only %s may query the world" % [file, token, WORLD_OWNER]
				)
		# get_world_3d is the one line that binds a probe, and it belongs to the facades
		# because they are the only Nodes in the module proper. There are exactly two:
		# CreatureNavigation, which is per-creature, and NavigationSource, which is
		# per-level. A third would be a third thing that thinks it owns a world.
		if code.contains("get_world_3d") and not _is_facade_or_harness(path):
			_fail("seam", "%s calls get_world_3d; only a facade binds a probe" % file)
	_pass_if("seam", before, "only %s queries the world" % WORLD_OWNER)


## Every file in graph/ is either pure data or a declared tool.
##
## THE PREVIOUS FORM WALKED GRAPH_FILES, WHICH IS A WHITELIST AND THEREFORE A HOLE: a new
## file dropped into graph/ was exempt from the purity rule by virtue of nobody having
## added it to the list, which is precisely the file most likely to break the rule. The
## check now enumerates the directory and demands every member be classified.
func _check_graph_is_pure_data() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if not path.contains("/graph/"):
			continue
		var file: String = path.get_file()
		if not GRAPH_FILES.has(file) and not GRAPH_TOOLS.has(file):
			_fail(
				"graph",
				(
					(
						"%s is in graph/ but is neither pure data nor a declared tool; "
						+ "add it to GRAPH_FILES or GRAPH_TOOLS and say which it is"
					)
					% file
				)
			)
	for name: String in GRAPH_FILES:
		var code: String = _read_code(MODULE.path_join("graph").path_join(name))
		for token: String in GRAPH_BANNED:
			if code.contains(token):
				_fail(
					"graph",
					(
						"%s names %s; the graph must not know where it came from, or Invariant 9 has nowhere to stand"
						% [name, token]
					)
				)
	_pass_if("graph", before, "the graph is data and nothing else")


func _check_route_does_not_bake() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if not path.contains("/route/"):
			continue
		var code: String = _read_code(path)
		for token: String in ROUTE_BANNED:
			if code.contains(token):
				_fail(
					"route",
					"%s names %s; planning must never trigger a bake" % [path.get_file(), token]
				)
	_pass_if("route", before, "route planning consumes a graph and never builds one")


## Invariant 8. See KNOWLEDGE_BANNED.
func _check_knowledge_never_measures() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if not path.contains("/knowledge/"):
			continue
		var code: String = _read_code(path)
		for token: String in KNOWLEDGE_BANNED:
			if code.contains(token):
				_fail(
					"knowledge",
					(
						"%s names %s; knowledge is told about the world and never asks it"
						% [path.get_file(), token]
					)
				)
	_pass_if("knowledge", before, "the knowledge graph cannot measure the world")


func _check_no_wall_clock() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		if file == SELF_FILE:
			continue
		# tools/ only. Timing a bake is exactly what a verifier is for, and nothing else
		# -- including tests/ and the sandbox -- has any business reading a wall clock.
		if path.contains("/tools/"):
			continue
		var code: String = _read_code(path)
		for token: String in CLOCK_TOKENS:
			if code.contains(token):
				_fail(
					"clock", "%s reads %s; durations come from the delta handed in" % [file, token]
				)
	_pass_if("clock", before, "nothing in the module reads a wall clock")


func _check_no_engine_navigation() -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		if path.get_file() == SELF_FILE:
			continue
		# tests/ is excluded, and only here. test_navigation_invariants.gd asserts that
		# CreatureNavigation exposes no NavigationAgent3D, which it can only do by naming
		# one -- the same trap this file's own exclusion exists for. The seam and clock
		# checks still cover tests/, because a test doing real physics or reading a wall
		# clock would be a genuine problem.
		if path.contains("/tests/"):
			continue
		var code: String = _read_code(path)
		for token: String in ENGINE_NAV_TOKENS:
			if code.contains(token):
				_fail(
					"engine_nav",
					(
						"%s names %s; this module replaces Godot's navigation rather than wrapping it"
						% [path.get_file(), token]
					)
				)
	_pass_if("engine_nav", before, "no file reaches for Godot's own navigation")


## Loading, INSTANTIATING and ATTACHING A SCRIPT are three different failures.
##
## The third is the one worth checking. A .tscn whose script fails to parse still loads,
## still instantiates, and still returns a perfectly valid Node -- Godot prints the parse
## error and hands back a scriptless node. The scene then reports as fine and does
## absolutely nothing when you run it.
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


## Godot does NOT infer vertex_color_use_as_albedo. Without it the whole overlay renders
## FLAT WHITE, the wiggle-versus-normal edge colouring disappears entirely, and section
## 39's most useful signal is gone while the overlay still looks busy and plausible.
## EVERY overlay, not one named file.
##
## This check used to name `navigation_debug_draw.gd`, which was fine while there was one
## overlay and became a hole the moment there were two: a second ImmediateMesh could ship
## lit and flat white, and the check it was supposed to be covered by would keep passing.
## Discovering it by looking at a white tangle is exactly the failure the rule exists to
## prevent, so the rule now finds its own subjects.
func _check_overlay_uses_vertex_colour() -> void:
	var before: int = _failures
	var checked: int = 0
	for path: String in _files(".gd"):
		if not path.contains("/debug/"):
			continue
		var code: String = _read_code(path)
		if not code.contains("ImmediateMesh"):
			continue
		checked += 1
		var file: String = path.get_file()
		if not code.contains("vertex_color_use_as_albedo"):
			_fail("overlay", "%s never sets vertex_color_use_as_albedo" % file)
		if not code.contains("SHADING_MODE_UNSHADED"):
			_fail("overlay", "%s draws lit lines; debug lines must be unshaded" % file)
	if checked == 0:
		_fail("overlay", "no overlay found; section 39's rendering is part of the module")
	_pass_if("overlay", before, "%d overlay material(s) render their vertex colours" % checked)


func _check_config_invariants() -> void:
	var failures: PackedStringArray = NavigationConfig.new().invariant_failures()
	for line: String in failures:
		_fail("config", line)
	if failures.is_empty():
		_pass("config", "a default NavigationConfig satisfies every invariant")


# ----- helpers -----


func _is_facade_or_harness(path: String) -> bool:
	return FACADES.has(path.get_file()) or _is_harness(path)


func _is_harness(path: String) -> bool:
	return path.contains("/tools/") or path.contains("/sandbox/") or path.contains("/tests/")


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
	print("[%-10s] PASS  %s" % [tag, message])


## PASS only if this check added no failures. The unconditional version prints PASS
## directly underneath its own FAIL lines, which is the kind of summary that gets
## skimmed and believed.
func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		_pass(tag, message)
