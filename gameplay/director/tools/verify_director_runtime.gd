extends Node

## Everything the GUT suite structurally cannot check: the wires between this module and the
## engine, and a real Director pacing a real creature over real geometry.
##
##   godot --headless --path <root> \
##     res://gameplay/director/tools/verify_director_runtime.tscn
##
## RUN IT AS A .tscn, NOT AS `--script`. Nodes added during SceneTree._initialize() never
## receive _ready(), so a bare script would run nothing, print nothing and exit 0 --
## indistinguishable from a pass.
##
## THE CHECK THIS FILE EXISTS FOR IS THE MUTE ONE. `CreatureBehavior._mute_subsystems()`
## switches off perception, suspicion and navigation so nothing is double-advanced, and it
## does NOT name the Director -- which is currently true by omission rather than by design. A
## Director that got muted would publish a permanently neutral directive and the creature
## would run correctly and unpaced, which is exactly what it does with no Director at all: no
## error, no warning, and a GUT suite that drives advance() by hand would go on passing every
## assertion in it. So this asserts the clock moves, and moves ONCE per frame rather than
## twice.

## project.godot names bit 1 "hull". PerceptionConfig.world_mask defaults to it.
const WALL_LAYER: int = 1
const ROOM := AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 8.0, 40.0))

var _director: EncounterDirector = null
var _behavior: CreatureBehavior = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _navigation: CreatureNavigation = null
var _relay: PlayerNoiseRelay = null
var _emitter: _Emitter = null
var _body: Node3D = null
var _player: Node3D = null
var _failures: int = 0


func _ready() -> void:
	_build_world()
	_build_player()
	_build_creature()
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _check_physics_process_drives_the_director()
	await _check_the_director_is_not_muted_or_double_ticked()
	_check_the_party_is_found_by_group()
	await _check_the_creature_still_works_with_a_director_attached()
	await _check_the_relay_makes_a_player_audible()
	_check_the_source_still_says_the_director_is_not_muted()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


func _build_world() -> void:
	_add_wall(Vector3(-21.0, 0.0, 0.0), Vector3(2.0, 8.0, 44.0))
	_add_wall(Vector3(21.0, 0.0, 0.0), Vector3(2.0, 8.0, 44.0))
	_add_wall(Vector3(0.0, 0.0, -21.0), Vector3(44.0, 8.0, 2.0))
	_add_wall(Vector3(0.0, 0.0, 21.0), Vector3(44.0, 8.0, 2.0))
	_add_wall(Vector3(0.0, -5.0, 0.0), Vector3(44.0, 2.0, 44.0))
	_add_wall(Vector3(0.0, 5.0, 0.0), Vector3(44.0, 2.0, 44.0))


func _add_wall(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## IN THE GROUPS AND NOTHING ELSE, so both fallbacks are what have to find it: `player` for
## DirectorParty and `noise_emitter` for PlayerNoiseRelay. Wiring either explicitly would
## leave the path a level actually takes untested.
func _build_player() -> void:
	_player = Node3D.new()
	_player.position = Vector3(9.0, 0.0, -3.0)
	_player.add_to_group(&"player")
	add_child(_player)

	_emitter = _Emitter.new()
	_emitter.body = _player
	_player.add_child(_emitter)
	_emitter.add_to_group(PlayerNoiseRelay.EMITTER_GROUP)


func _build_creature() -> void:
	_body = Node3D.new()
	add_child(_body)

	_perception = CreaturePerception.new()
	_perception.config = PerceptionConfig.new()
	_body.add_child(_perception)

	_suspicion = CreatureSuspicion.new()
	var suspicion_config := SuspicionConfig.new()
	suspicion_config.hotspot_update_interval = 0.0
	_suspicion.config = suspicion_config
	add_child(_suspicion)

	_navigation = CreatureNavigation.new()
	_navigation.config = NavigationConfig.new()
	add_child(_navigation)
	_navigation.bake_now(ROOM)

	_perception.evidence_observed.connect(_suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)

	_relay = PlayerNoiseRelay.new()
	_relay.perception = _perception
	add_child(_relay)

	# ADDED BEFORE THE BEHAVIOR, so its own _physics_process runs first in tree order and the
	# directive a creature reads was integrated this frame rather than last. A freshness
	# preference, never a correctness requirement -- see EncounterDirector's class docstring.
	_director = EncounterDirector.new()
	_director.config = DirectorConfig.new()
	add_child(_director)

	_behavior = CreatureBehavior.new()
	_behavior.config = BehaviorConfig.new()
	_behavior.suspicion = _suspicion
	_behavior.perception = _perception
	_behavior.navigation = _navigation
	_behavior.director = _director
	_behavior.body = _body
	add_child(_behavior)
	_behavior.set_nest_positions(
		PackedVector3Array([Vector3(12.0, 0.0, 0.0), Vector3(-12.0, 0.0, 0.0)])
	)


## Delete _physics_process from EncounterDirector and every GUT assertion still passes,
## because the suite drives advance() by hand. The encounter simply stops being paced.
func _check_physics_process_drives_the_director() -> void:
	var before: float = _director.clock
	for _i: int in 10:
		await get_tree().physics_frame

	if _director.clock > before:
		_pass("clock", "_physics_process is wired to advance()")
	else:
		_fail("clock", "EncounterDirector.clock never moved; nothing is driving the Director")


## THE ONE THIS FILE EXISTS FOR. See the class docstring.
func _check_the_director_is_not_muted_or_double_ticked() -> void:
	var director_before: float = _director.clock
	var behavior_before: float = _behavior.clock
	for _i: int in 30:
		await get_tree().physics_frame

	var behavior_elapsed: float = _behavior.clock - behavior_before
	var director_elapsed: float = _director.clock - director_before
	if director_elapsed <= 0.0:
		_fail("mute", "the Director's clock stopped; CreatureBehavior is muting it")
	elif absf(director_elapsed - behavior_elapsed) > behavior_elapsed * 0.25:
		_fail(
			"mute",
			(
				"the Director advanced %.3fs while Behavior advanced %.3fs; it is being ticked twice"
				% [director_elapsed, behavior_elapsed]
			)
		)
	else:
		_pass("mute", "the Director advances exactly once per frame alongside the creature")


## Explicit wiring wins and the group is the fallback; nothing here wires `players`, so the
## group is what has to have found the party.
func _check_the_party_is_found_by_group() -> void:
	if _director.party.size() != 1:
		_fail("party", "the group fallback found %d players, not 1" % _director.party.size())
	elif not _director.party.anchor().is_equal_approx(_player.global_position):
		_fail(
			"party",
			(
				"the anchor is %v, not the player's %v"
				% [_director.party.anchor(), _player.global_position]
			)
		)
	else:
		_pass("party", "roam_anchor is derived from where the player actually is")


## The Director must not deadlock a working alien. It gates hunting, never investigating, and
## a creature that stopped reacting to a real noise because a Director was attached would be
## the single worst failure this module could have.
func _check_the_creature_still_works_with_a_director_attached() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0.0, 0.0, 8.0), 1.0, &"drill"))
	for _i: int in 180:
		await get_tree().physics_frame
		if _behavior.state() == CreatureState.State.INVESTIGATING:
			break

	if _behavior.state() != CreatureState.State.INVESTIGATING:
		_fail(
			"investigate",
			(
				"still %s after a drill at 8 m with a Director attached: %s"
				% [CreatureState.state_name(_behavior.state()), _behavior.describe()]
			)
		)
		return
	# TWO MORE FRAMES BEFORE READING THE PHASE, and the reason is the contract rather than
	# flakiness. The report goes up at step 4 of the behavior tick, so the transition that just
	# happened is not in the Director's hands until the creature files it -- and the Director
	# integrates on its own _physics_process. The phase is always at most one frame behind the
	# state, which is the same trade EncounterReport's two latched fields already make.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var track: EncounterTrack = _director.track_for(_behavior)
	if track == null:
		_fail("investigate", "the creature investigated but was never registered")
	elif track.phase != EncounterDirective.Phase.BUILD:
		_fail(
			"investigate",
			(
				"the creature is investigating but the Director is still %s"
				% EncounterDirective.phase_name(track.phase)
			)
		)
	else:
		_pass("investigate", "a real drill became a lead, and the Director called it a BUILD")


## The wire that did not exist before this module. Nothing else in the project turns what a
## player DOES into something a creature can hear.
func _check_the_relay_makes_a_player_audible() -> void:
	var before: float = _suspicion.get_overall_suspicion()
	_emitter.noise_emitted.emit(10.0, _player.global_position, 1)
	for _i: int in 60:
		await get_tree().physics_frame

	if _suspicion.get_overall_suspicion() > before:
		_pass("relay", "a player mining became belief, with nobody calling receive_noise by hand")
	else:
		_fail("relay", "the relay emitted nothing the creature could hear")


## A SOURCE-LEVEL ASSERTION, because the runtime one above can only see the symptom. If
## somebody adds `director` to CreatureBehavior's mute list, the timing check fires with a
## message about clocks; this one names the line that did it.
func _check_the_source_still_says_the_director_is_not_muted() -> void:
	var path: String = "res://gameplay/creature/behavior/creature_behavior.gd"
	var source: String = FileAccess.get_file_as_string(path)
	var start: int = source.find("func _mute_subsystems")
	if start < 0:
		_fail("mute-source", "CreatureBehavior._mute_subsystems has been renamed or removed")
		return
	var end: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, (end if end > 0 else source.length()) - start)
	if body.contains("director"):
		_fail("mute-source", "_mute_subsystems now names the director; it would stop being ticked")
	else:
		_pass("mute-source", "_mute_subsystems still leaves the Director running")


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("[%-13s] PASS  %s" % [tag, message])


## The shape PlayerNoiseEmitter publishes, without its CharacterBody3D and its nine siblings.
class _Emitter:
	extends Node

	signal noise_emitted(strength: float, at: Vector3, source: int)

	var body: Node3D = null
