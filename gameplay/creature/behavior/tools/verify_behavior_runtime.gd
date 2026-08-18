extends Node

## Everything the GUT suite structurally cannot check: the wires between this module and the
## engine, and all four creature systems meeting over real geometry.
##
##   godot --headless --path <root> \
##     res://gameplay/creature/behavior/tools/verify_behavior_runtime.tscn
##
## RUN IT AS A .tscn, NOT AS `--script`. Nodes added during SceneTree._initialize() never
## receive _ready(), so a bare script would run nothing, print nothing and exit 0 --
## indistinguishable from a pass.
##
## THE TWO THINGS ONLY THIS FILE CAN SEE.
##
## First, that `_physics_process` is genuinely wired to `advance()`. The GUT suite drives
## advance() by hand, so every assertion in it passes perfectly against a facade whose
## _physics_process was deleted -- and the alien would then never decide anything in a real
## game.
##
## Second, that driving the tick MUTES the other three facades. Every subsystem runs its own
## _physics_process, so leaving them on double-advances every clock: navigation ages its
## knowledge twice and emits motion_planned TWICE PER FRAME with the same body state, and the
## motor consumes both. A unit test cannot see it because a unit test never lets a frame
## happen. Here it shows up as a clock running at exactly double rate.

## project.godot names bit 1 "hull". PerceptionConfig.world_mask defaults to it.
const WALL_LAYER: int = 1
const ROOM := AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 8.0, 40.0))

var _behavior: CreatureBehavior = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _navigation: CreatureNavigation = null
var _body: Node3D = null
var _failures: int = 0


func _ready() -> void:
	_build_world()
	_build_creature()
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _check_physics_process_drives_the_tick()
	await _check_the_subsystems_are_not_double_advanced()
	await _check_a_real_noise_starts_an_investigation()
	await _check_the_creature_commands_navigation()
	await _check_alertness_follows_the_state()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


## A hollow room, so navigation has somewhere to bake and perception has walls to attenuate
## against. Hand-built rather than generated so the numbers below read straight off it.
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


## The wiring the README documents, and nothing else.
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

	_behavior = CreatureBehavior.new()
	_behavior.config = BehaviorConfig.new()
	_behavior.suspicion = _suspicion
	_behavior.perception = _perception
	_behavior.navigation = _navigation
	_behavior.body = _body
	add_child(_behavior)
	_behavior.set_nest_positions(
		PackedVector3Array([Vector3(12.0, 0.0, 0.0), Vector3(-12.0, 0.0, 0.0)])
	)


## THE CHECK THIS FILE EXISTS FOR. Delete _physics_process from CreatureBehavior and every
## GUT assertion still passes; the alien simply stops thinking.
func _check_physics_process_drives_the_tick() -> void:
	var before: float = _behavior.clock
	for _i: int in 10:
		await get_tree().physics_frame

	if _behavior.clock > before:
		_pass("clock", "_physics_process is wired to advance()")
	else:
		_fail("clock", "CreatureBehavior.clock never moved; nothing is driving the tick")


## Double-advancing is not merely wasteful. Navigation would emit two motion commands per
## frame with the same body state, and the motor would consume both.
func _check_the_subsystems_are_not_double_advanced() -> void:
	var behavior_before: float = _behavior.clock
	var perception_before: float = _perception.clock
	var suspicion_before: float = _suspicion.clock
	for _i: int in 30:
		await get_tree().physics_frame

	var elapsed: float = _behavior.clock - behavior_before
	var perception_elapsed: float = _perception.clock - perception_before
	var suspicion_elapsed: float = _suspicion.clock - suspicion_before
	if absf(perception_elapsed - elapsed) > elapsed * 0.25:
		_fail(
			"mute",
			(
				"perception advanced %.3fs while behavior advanced %.3fs; it is being ticked twice"
				% [perception_elapsed, elapsed]
			)
		)
	elif absf(suspicion_elapsed - elapsed) > elapsed * 0.25:
		_fail(
			"mute",
			(
				"suspicion advanced %.3fs while behavior advanced %.3fs; it is being ticked twice"
				% [suspicion_elapsed, elapsed]
			)
		)
	else:
		_pass("mute", "every clock advances exactly once per frame")


## Jolt and the hearing model decide what the alien hears here, not a fixture. Real
## attenuation, real uncertainty, real hotspot.
func _check_a_real_noise_starts_an_investigation() -> void:
	_perception.receive_noise(NoiseEvent.make(Vector3(0.0, 0.0, 8.0), 1.0, &"drill"))
	for _i: int in 180:
		await get_tree().physics_frame
		if _behavior.state() == CreatureState.State.INVESTIGATING:
			break

	if _behavior.state() == CreatureState.State.INVESTIGATING:
		_pass("investigate", "a real drill through real geometry became a lead")
	else:
		_fail(
			"investigate",
			(
				"still %s after a drill at 8 m: %s"
				% [CreatureState.state_name(_behavior.state()), _behavior.describe()]
			)
		)


## Behavior's whole output. A creature that decides correctly and commands nothing is a
## creature that stands still looking thoughtful.
func _check_the_creature_commands_navigation() -> void:
	if not _behavior.goal.has_goal():
		_fail("goal", "the creature is investigating and has asked navigation for nothing")
		return
	for _i: int in 30:
		await get_tree().physics_frame

	if _navigation.route != null:
		_pass("goal", "the goal reached navigation and a route came back")
	else:
		_fail("goal", "a goal was committed but navigation never planned a route")


## Step 6 of the tick contract, and the one place Behavior writes to Perception. Vision is
## designed to sharpen once the creature is already suspicious.
func _check_alertness_follows_the_state() -> void:
	var config: BehaviorConfig = _behavior.config
	var expected: float = config.alertness_for(_behavior.state())
	if absf(_perception.get_alertness() - expected) < 0.01:
		_pass("alertness", "perception is told how hard to look, from the current state")
	else:
		_fail(
			"alertness",
			(
				"alertness is %.2f but %s expects %.2f"
				% [
					_perception.get_alertness(),
					CreatureState.state_name(_behavior.state()),
					expected
				]
			)
		)


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("[%-11s] PASS  %s" % [tag, message])
