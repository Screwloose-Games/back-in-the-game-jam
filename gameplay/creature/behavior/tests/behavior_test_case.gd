extends GutTest

## Shared fixture for the suites that exercise an assembled creature.
##
## Not collected as a test script itself -- GUT's prefix is `test_`, and this file
## deliberately does not have it. The framework-only fixture is `bt_test_case.gd`.
##
## ALL FOUR FACADES ARE REAL. There is no fake CreatureNavigation and there must not be: the
## whole point of BehaviorGoal is the real goal path, and a fake would leave the one thing
## worth proving unproven. Navigation runs headless because everything it owns is built in
## `_init()` and `_ready()` -- the only caller of `get_world_3d()` -- never runs for a node
## that was never added to a tree. The world seam is the two FAKE PROBES, which is where the
## other two modules put theirs.
##
## NOTHING IS EVER ADDED TO A TREE, and that constrains two things. `_ready()` never fires,
## so CreatureBehavior enters its initial state from `advance()` instead. And nothing may
## read `global_position` off a detached Node3D: the engine logs
## "Condition !is_inside_tree() is true" and GUT counts that as an unexpected error and
## FAILS THE TEST. The body here is a detached Node3D whose `position` is written directly,
## which is exactly what CreatureBehavior._body_position() reads.

const FakeNavigationProbe := preload(
	"res://gameplay/creature/navigation/tests/fake_navigation_probe.gd"
)
const FakePerceptionProbe := preload(
	"res://gameplay/creature/perception/tests/fake_perception_probe.gd"
)
const TICK: float = 1.0 / 60.0
## A single open room big enough to route across. Bounded, because unbounded void has
## unlimited clearance and every candidate in it survives the bake.
const ROOM := AABB(Vector3(-30.0, -6.0, -30.0), Vector3(60.0, 12.0, 60.0))

var _behavior: CreatureBehavior = null
var _config: BehaviorConfig = null
var _suspicion: CreatureSuspicion = null
var _perception: CreaturePerception = null
var _navigation: CreatureNavigation = null
var _body: Node3D = null
var _directive: EncounterDirective = null
var _transitions: Array = []
var _actions: Array = []


func before_each() -> void:
	_config = BehaviorConfig.new()
	_directive = EncounterDirective.neutral()

	var suspicion_config := SuspicionConfig.new()
	# Forced to 0.0 so a rebuild happens every tick. In play it is throttled; in a test,
	# "submit then tick then assert" has to mean exactly that.
	suspicion_config.hotspot_update_interval = 0.0
	_suspicion = autofree(CreatureSuspicion.new())
	_suspicion.config = suspicion_config

	var perception_config := PerceptionConfig.new()
	perception_config.geometry_perception_enabled = false
	_perception = autofree(CreaturePerception.new())
	_perception.config = perception_config
	_perception.probe = FakePerceptionProbe.new()
	_perception.hearing.rng = RandomNumberGenerator.new()
	_perception.hearing.rng.seed = 99

	# The two-line coupling the perception README documents, and the only wiring between
	# those modules.
	_perception.evidence_observed.connect(_suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)

	_body = autofree(Node3D.new())
	_behavior = autofree(CreatureBehavior.new())
	_behavior.config = _config
	_behavior.suspicion = _suspicion
	_behavior.perception = _perception
	_behavior.body = _body
	_behavior.director = null

	_transitions = []
	_actions = []
	_behavior.state_changed.connect(
		func(from: int, to: int, reason: StringName) -> void:
			_transitions.append([from, to, reason])
	)
	_behavior.action_changed.connect(func(action: StringName) -> void: _actions.append(action))

	# A zero-length tick, which is what `_ready()` would have done for a creature in a scene:
	# it binds the goal handle, subscribes to Perception and Suspicion, and enters UNALERTED.
	# Without it a fixture that emits evidence before its first real tick is talking to a
	# creature that has not started listening, and `has_visual_contact` never fires.
	_behavior.advance(0.0)


## Attaches a real CreatureNavigation over a baked open room. Opt-in, because a bake costs
## more than most transition assertions need.
func _add_navigation() -> CreatureNavigation:
	var probe := FakeNavigationProbe.new()
	probe.add_room(ROOM)
	_navigation = autofree(CreatureNavigation.new())
	_navigation.config = NavigationConfig.new()
	_navigation.probe = probe
	_navigation.bake_now(ROOM)
	_behavior.navigation = _navigation
	return _navigation


func _nests(positions: Array) -> void:
	_behavior.set_nest_positions(PackedVector3Array(positions))


## The directive Behavior reads. Mutated in place, because it is the same object every tick
## and a Director would be publishing into it.
func _direct() -> EncounterDirective:
	_behavior.director = _StubDirector.new(_directive)
	return _directive


## Simulated seconds, in real-sized steps.
func _advance(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_behavior.advance(TICK)


func _tick() -> void:
	_behavior.advance(TICK)


func _place(at: Vector3) -> void:
	_body.position = at


## Walks the body straight to a point over `seconds`, ticking as it goes. No physics and no
## locomotion -- the body is a position, which is all Behavior ever reads.
func _walk_to(target: Vector3, seconds: float) -> void:
	var steps: int = maxi(int(roundf(seconds / TICK)), 1)
	var from: Vector3 = _body.position
	for step: int in steps:
		_body.position = from.lerp(target, float(step + 1) / float(steps))
		_behavior.advance(TICK)


func _hear(at: Vector3, loudness: float = 1.0, category: StringName = &"drill") -> void:
	_perception.receive_noise(NoiseEvent.make(at, loudness, category))


## A sighting, which is the only evidence that names a player AND carries confidence -- so it
## is the only way to reach the hunt guards short of a touch.
##
## EMITTED THROUGH PERCEPTION'S SIGNAL RATHER THAN PUSHED STRAIGHT INTO SUSPICION, because
## two things listen to it. Suspicion is wired to it in before_each, and so is Behavior --
## `has_visual_contact` is stamped from exactly this signal, since Perception is forbidden
## from holding history and there is no line-of-sight query Behavior is allowed to make.
## Calling `submit_evidence` directly reaches one consumer and silently starves the other.
##
## Driving real vision instead would mean an alertness above the gate, a bound probe and a
## registered target -- a fixture about Perception, in a suite about Behavior.
func _see(player: Node, at: Vector3, strength: float = 1.0) -> void:
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION, at, 0.25, strength, 1.0, _perception.clock
	)
	evidence.source_player = player
	evidence.source_confidence = 1.0
	_perception.evidence_observed.emit(evidence)


func _player(named: String) -> Node3D:
	var player: Node3D = autofree(Node3D.new())
	player.name = named
	return player


func _state() -> CreatureState.State:
	return _behavior.state()


func _reasons() -> Array:
	var found: Array = []
	for entry: Array in _transitions:
		found.append(entry[2])
	return found


## Anything with `exchange`. CreatureBehavior duck-types the Director because
## EncounterDirector does not exist yet, and this is the whole of what it needs.
class _StubDirector:
	extends Node

	var directive: EncounterDirective = null

	func _init(p_directive: EncounterDirective) -> void:
		directive = p_directive

	func exchange(_creature: Node, _report: EncounterReport) -> EncounterDirective:
		return directive
