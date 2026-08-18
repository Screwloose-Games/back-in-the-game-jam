extends GutTest

## Shared fixture for the suites that exercise the assembled CreaturePerception.
##
## Not collected as a test script itself -- GUT's default prefix is `test_`, and this
## file deliberately does not have it.
##
## The fixture builds a facade that was never added to a scene tree, with a scripted
## probe and a pinned RNG, and captures all three output signals. Everything about
## the module except the real physics queries is reachable from here, which is what
## keeps the slow suite small.

const FakeProbe := preload("res://gameplay/creature/perception/tests/fake_perception_probe.gd")
const TICK: float = 1.0 / 60.0

var _perception: CreaturePerception = null
var _config: PerceptionConfig = null
var _probe: RefCounted = null
var _evidence: Array[SuspicionEvidence] = []
var _disconfirmations: Array[DisconfirmationObservation] = []
var _geometry: Array = []


func before_each() -> void:
	_config = PerceptionConfig.new()
	# Off unless a test asks for it, so passive scanning does not flood the geometry
	# channel while something else is under test.
	_config.geometry_perception_enabled = false
	_probe = FakeProbe.new()

	_perception = autofree(CreaturePerception.new())
	_perception.config = _config
	_perception.probe = _probe
	_perception.hearing.rng.seed = 99

	_evidence = []
	_disconfirmations = []
	_geometry = []
	_perception.evidence_observed.connect(func(e: SuspicionEvidence) -> void: _evidence.append(e))
	_perception.disconfirmation_observed.connect(
		func(o: DisconfirmationObservation) -> void: _disconfirmations.append(o)
	)
	_perception.geometry_observed.connect(func(batch: Array) -> void: _geometry.append(batch))


## Drive the facade's own tick entry point. No awaits, no physics, no wall clock --
## `seconds` of simulated time happens synchronously.
func _advance(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_perception.advance(TICK)


func _add_target(at: Vector3) -> Node3D:
	var target: Node3D = autofree(Node3D.new())
	target.position = at
	_perception.targets.append(target)
	return target


func _search_region() -> AABB:
	return AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))


## Somewhere with nothing in it, for the disconfirmation cases.
func _empty_region() -> AABB:
	return AABB(Vector3(20, 0, 20), Vector3(4, 4, 4))
