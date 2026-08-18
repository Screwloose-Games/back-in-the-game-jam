extends SceneTree

## director.md's "Design invariants", as structural rules over the source.
##
##   godot --headless --path <root> \
##     --script res://gameplay/director/tools/verify_director_static.gd
##
## These are the checks the GUT suite structurally cannot make, because they are about what
## the module is ALLOWED TO SAY rather than about what it does. A Director that grew a
## `set_goal` call would hand the alien a position it never earned and would work visibly
## better, which is precisely why no behavioural test would flag it.
##
## THE BANS ARE ON VERBS, NOT ON NOUNS, wherever a type name is legitimate. `CreatureSuspicion`
## is a type the Director is explicitly granted three reads of, so banning the noun would ban
## the sanctioned interface along with the forbidden one -- the same distinction
## `verify_perception_static.gd` makes when it notes that "SuspicionEvidence is a legitimate
## type name, so the bans have to be on the verbs".
##
## PERCEPTION IS THE ONE EXCEPTION, and deliberately. director.md: "The Director does not touch
## hearing range, vision cone, sense weights or any other sensing parameter. Not 'should not' --
## the interface does not exist." So the noun is banned too: no file in this module may so much
## as name CreaturePerception.
##
## Everything runs on the first _process() tick rather than in _initialize(). Nodes added
## during SceneTree._initialize() never receive _ready(), so a check written there measures
## the harness instead of the module.

const MODULE: String = "res://gameplay/director"

## Belief has exactly three doors -- evidence, disconfirmation, and the clock -- and the
## Director is not one of them. After a forced disengagement the creature still fully believes
## you are there; the cooldown works by shifting Behavior's thresholds, not by editing belief.
const BELIEF_TOKENS: Array[String] = [
	"submit_evidence",
	"submit_disconfirmation",
	"submit_evidence_batch",
	"reduce_suspicion",
	"clear_hotspot",
	"mark_investigation_complete",
]

## "The Director never issues navigation destinations. Behavior owns goals." It never even
## reads a route: the two metrics it needs ride up on EncounterReport, because a level-scoped
## Director reaching into one creature's route follower is a dependency the design forbids.
const NAVIGATION_TOKENS: Array[String] = [
	"set_goal",
	"clear_goal",
	"plan_route",
	"CreatureNavigation",
	"NavigationServer3D",
	"NavigationAgent3D",
	"distance_remaining",
]

## "The Director never adjusts perception. Sensing is difficulty, not pacing." The noun is in
## here on purpose -- see the class docstring.
const PERCEPTION_TOKENS: Array[String] = [
	"CreaturePerception", "PerceptionConfig", "set_alertness_context", "receive_noise"
]

## "The Director never transitions the HFSM. It publishes a directive; Behavior honours it, at
## a moment of Behavior's choosing." Reading a facade for debug is not transitioning it, so the
## verbs are banned and CreatureBehavior is not.
const HFSM_TOKENS: Array[String] = [
	"reset_to", "evaluate_transitions", "consume_disengage", "force_state", "set_state"
]

## Wall clocks. The injected delta is the module's only time. Anything here ignores
## get_tree().paused and Engine.time_scale, and no test could drive it.
const CLOCK_TOKENS: Array[String] = [
	"Time.get_", "OS.get_ticks", "Engine.get_physics_frames", "Engine.get_process_frames"
]

## Physics. The Director reaches the world through nothing at all -- it is handed real player
## positions and emits bias.
const PHYSICS_TOKENS: Array[String] = [
	"intersect_ray", "intersect_shape", "direct_space_state", "PhysicsRayQueryParameters3D"
]

## THE INVARIANT THIS FILE IS REALLY FOR. "The Director may know the truth, and may only emit
## bias." One file is allowed to read where people are; nothing else in the module may say
## these words at all, and `verify_behavior_static.gd`'s WORLD_EXEMPT names the same file from
## the other side.
const WORLD_TOKENS: Array[String] = [
	"get_nodes_in_group", "global_position", "get_world_3d", "RayCast3D", "Area3D"
]
const TRUTH_KEEPER: String = "director_party.gd"

## And the other half of it: truth goes INTO that file and only a Vector3 and an
## Array[Node3D] come out. It may not know what a directive is, what an encounter is, or that
## menace exists -- so there is no route by which a real position could reach the creature
## through it.
const TRUTH_KEEPER_TOKENS: Array[String] = [
	"EncounterDirective",
	"EncounterTrack",
	"EncounterDirector",
	"menace",
	"permit_hunt",
	"escalation_bias",
	"force_disengage",
]

## The one file that assembles a whole creature from nothing and drives it by hand. It plants
## nests, connects Perception to Suspicion, moves a stand-in player on a keypress and resets
## the HFSM on R -- all of which is the job of a LEVEL rather than of the Director, and
## `/sandbox/` is not covered by _is_harness.
##
## EXEMPTING IT COSTS THE ASSEMBLY RULES NOTHING, because what it names are CONNECTIONS and
## debug scaffolding rather than decisions. It is NOT exempt from the wall-clock or physics
## rules, which stay absolute across the whole module.
const ASSEMBLY_EXEMPT: Array[String] = ["director_sandbox.gd"]

## This file names every banned token, in code rather than in a comment, in order to ban them
## -- so comment stripping cannot save it and it has to exclude itself.
const SELF_FILE: String = "verify_director_static.gd"

var _failures: int = 0
var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	_check_layout()
	_check_uid_sidecars()
	_check_the_module_never_writes_belief()
	_check_the_module_never_issues_a_destination()
	_check_the_module_never_touches_perception()
	_check_the_module_never_transitions_the_hfsm()
	_check_no_wall_clock()
	_check_no_physics()
	_check_only_one_file_knows_the_truth()
	_check_the_truth_keeper_emits_nothing_but_geometry()
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
		"encounter_directive.gd",
		"encounter_report.gd",
		"director_config.gd",
		"encounter_track.gd",
		"encounter_pacing.gd",
		"director_party.gd",
		"encounter_director.gd",
		"debug/director_debug_panel.gd",
		"sandbox/director_sandbox.gd",
		"sandbox/director_sandbox.tscn",
		"tools/verify_director_static.gd",
		"tools/verify_director_runtime.gd",
		"tools/verify_director_runtime.tscn",
		"README.md",
	]
	for relative: String in expected:
		if not FileAccess.file_exists(MODULE.path_join(relative)):
			_fail("layout", "%s is missing" % relative)
	_pass_if("layout", before, "%d expected files present" % expected.size())


## This repo commits .uid sidecars alongside every script. A missing one is not cosmetic:
## Godot regenerates it with a fresh id, and every scene referencing the script by uid then
## points at nothing.
func _check_uid_sidecars() -> void:
	var before: int = _failures
	var scripts: PackedStringArray = _files(".gd")
	for path: String in scripts:
		if not FileAccess.file_exists(path + ".uid"):
			_fail("uid", "%s has no .uid sidecar" % path.get_file())
	_pass_if("uid", before, "%d scripts have their .uid sidecar" % scripts.size())


func _check_the_module_never_writes_belief() -> void:
	_ban(
		"belief",
		BELIEF_TOKENS,
		ASSEMBLY_EXEMPT,
		"Suspicion has three doors and the Director is not one of them",
		"nothing in the module writes belief"
	)


func _check_the_module_never_issues_a_destination() -> void:
	_ban(
		"navigation",
		NAVIGATION_TOKENS,
		ASSEMBLY_EXEMPT,
		"Behavior owns goals; the two route metrics ride up on the report",
		"the module issues no destinations and reads no routes"
	)


func _check_the_module_never_touches_perception() -> void:
	_ban(
		"perception",
		PERCEPTION_TOKENS,
		ASSEMBLY_EXEMPT,
		"sensing is difficulty and pacing is not; the interface does not exist",
		"nothing in the module can reach a sense"
	)


func _check_the_module_never_transitions_the_hfsm() -> void:
	_ban(
		"hfsm",
		HFSM_TOKENS,
		ASSEMBLY_EXEMPT,
		"the Director publishes a directive and Behavior honours it when it chooses",
		"nothing in the module moves a creature between states"
	)


func _check_no_wall_clock() -> void:
	_ban(
		"clock",
		CLOCK_TOKENS,
		[],
		"the injected delta is the module's only time",
		"nothing in the module reads a wall clock"
	)


func _check_no_physics() -> void:
	_ban(
		"physics",
		PHYSICS_TOKENS,
		[],
		"the Director is handed positions and emits bias; it queries nothing",
		"nothing in the module touches the physics server"
	)


## THE HIGHEST-VALUE CHECK IN THIS FILE. See WORLD_TOKENS.
func _check_only_one_file_knows_the_truth() -> void:
	_ban(
		"truth",
		WORLD_TOKENS,
		ASSEMBLY_EXEMPT + [TRUTH_KEEPER],
		"only %s may read where anybody actually is" % TRUTH_KEEPER,
		"exactly one file in the module knows the truth"
	)


## The other half of the same invariant. Truth in, geometry out.
func _check_the_truth_keeper_emits_nothing_but_geometry() -> void:
	var before: int = _failures
	var path: String = MODULE.path_join(TRUTH_KEEPER)
	var code: String = _read_code(path)
	for token: String in TRUTH_KEEPER_TOKENS:
		if code.contains(token):
			_fail(
				"truth-keeper",
				(
					(
						"%s names %s; the file allowed to know where people are must not know what a"
						+ " directive is, or a real position could reach the creature through it"
					)
					% [TRUTH_KEEPER, token]
				)
			)
	_pass_if(
		"truth-keeper",
		before,
		"%s emits a Vector3 and a node list, and nothing else" % TRUTH_KEEPER
	)


## Loading, INSTANTIATING and ATTACHING A SCRIPT are three different failures, and the third
## is the one that catches this check out: a .tscn whose script fails to parse still loads,
## still instantiates, and still returns a perfectly valid Node -- Godot prints the parse
## error and hands back a SCRIPTLESS node. The scene then reports as fine and does absolutely
## nothing when you run it.
func _check_scene_loads() -> void:
	var before: int = _failures
	var scenes: PackedStringArray = _files(".tscn")
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("scenes", "%s did not load" % path.get_file())
			continue
		var node: Node = packed.instantiate()
		if node == null:
			_fail("scenes", "%s did not instantiate" % path.get_file())
			continue
		if node.get_script() == null:
			_fail("scenes", "%s instantiated WITHOUT its script attached" % path.get_file())
		node.free()
	_pass_if("scenes", before, "%d scenes load, instantiate and keep their script" % scenes.size())


func _check_config_invariants() -> void:
	var before: int = _failures
	var failures: PackedStringArray = DirectorConfig.new().invariant_failures(BehaviorConfig.new())
	for failure: String in failures:
		_fail("config", "the shipped defaults trip an invariant: %s" % failure)
	_pass_if("config", before, "a bare DirectorConfig sits correctly against a bare BehaviorConfig")


## One banned-token sweep, since eight checks are the same loop with a different list.
func _ban(tag: String, tokens: Array[String], exempt: Array, why: String, ok: String) -> void:
	var before: int = _failures
	for path: String in _files(".gd"):
		var file: String = path.get_file()
		if file == SELF_FILE or _is_harness(path) or exempt.has(file):
			continue
		var code: String = _read_code(path)
		for token: String in tokens:
			if code.contains(token):
				_fail(tag, "%s names %s; %s" % [file, token, why])
	_pass_if(tag, before, ok)


## Tests and tools assemble a whole creature in order to check one, so both of them
## legitimately name every subsystem the module itself may not. `verify_director_runtime.gd`
## builds a perception, a suspicion and a navigation and drives them; that is the harness, not
## the decision layer. Note `/sandbox/` is deliberately NOT here -- the sandbox is exempted by
## name instead, so adding a second one does not silently inherit the exemption.
func _is_harness(path: String) -> bool:
	return path.contains("/tests/") or path.contains("/tools/")


## Source with comments stripped, so a check for a banned token does not fire on the docstring
## explaining why the token is banned. That is not hypothetical -- most of the prose in this
## module names the things it refuses to do.
func _read_code(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var stripped: String = ""
	for line: String in text.split("\n"):
		var comment: int = line.find("#")
		stripped += (line if comment < 0 else line.substr(0, comment)) + "\n"
	return stripped


func _files(extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	_walk(MODULE, extension, found)
	return found


func _walk(folder: String, extension: String, found: PackedStringArray) -> void:
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while entry != "":
		var path: String = folder.path_join(entry)
		if directory.current_is_dir():
			_walk(path, extension, found)
		elif entry.ends_with(extension):
			found.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass_if(tag: String, before: int, message: String) -> void:
	if _failures == before:
		print("[%-13s] PASS  %s" % [tag, message])
