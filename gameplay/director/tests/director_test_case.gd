extends GutTest

## Shared fixture for the suites that exercise a running Director.
##
## Not collected as a test script itself -- GUT's prefix is `test_`, and this file
## deliberately does not have it, the same way `behavior_test_case.gd` does not.
##
## THE COUPLING REALLY IS TWO STRUCTS, so almost nothing here is a creature. `_creature` is a
## bare Node with an `attack_landed` signal and a `suspicion` field, which is the entire
## surface EncounterDirector touches: it registers by instance id, reads that one field to
## get the read-only belief facade, and subscribes to that one signal. Anything more would be
## testing CreatureBehavior in a suite about the Director.
##
## SUSPICION IS REAL, THOUGH. The house rule across this project is real facades behind fake
## seams, and the Director's three sanctioned reads are worth exercising against the thing
## that actually implements them rather than against a dictionary that agrees with itself.
##
## NOTHING IS EVER ADDED TO A TREE. `_ready()` never fires, so the Director is driven through
## `advance()` directly -- which is the public entry point precisely so a test can. And
## nothing may read `global_position` off a detached Node3D: the engine logs
## "Condition !is_inside_tree() is true" and GUT counts that as an unexpected error and FAILS
## THE TEST. Player stand-ins have their `position` written directly, which is what
## DirectorParty._position_of() reads for a detached node.

const TICK: float = 1.0 / 60.0

var _director: EncounterDirector = null
var _config: DirectorConfig = null
var _suspicion: CreatureSuspicion = null
var _creature: Node = null
## Somebody has to be in the party, or roam_bias is published as zero however bored the
## Director gets -- DirectorParty.anchor() has nowhere to point and the weight is deliberately
## suppressed rather than aimed at the world origin. The empty party is a real case and gets
## its own test; it is not the default one.
var _member: Node3D = null
var _report: EncounterReport = null
var _phases: Array = []
var _targets: Array = []
var _disengages: Array = []
var _lethalities: Array = []


func before_each() -> void:
	_config = DirectorConfig.new()

	var suspicion_config := SuspicionConfig.new()
	# Forced to 0.0 so a rebuild happens every tick. In play it is throttled; in a test,
	# "submit then tick then assert" has to mean exactly that.
	suspicion_config.hotspot_update_interval = 0.0
	_suspicion = autofree(CreatureSuspicion.new())
	_suspicion.config = suspicion_config

	_creature = autofree(_FakeCreature.new())
	_creature.suspicion = _suspicion

	_member = autofree(Node3D.new())
	_member.name = "PartyMember"
	_member.position = Vector3(20.0, 0.0, 0.0)

	_director = autofree(EncounterDirector.new())
	_director.config = _config
	_director.players = [_member]
	_director.register(_creature)

	_report = _make_report(CreatureState.State.UNALERTED)

	_phases = []
	_targets = []
	_disengages = []
	_lethalities = []
	_director.encounter_phase_changed.connect(
		func(_c: Node, from: int, to: int) -> void: _phases.append([from, to])
	)
	_director.target_changed.connect(
		func(_c: Node, from: Node, to: Node) -> void: _targets.append([from, to])
	)
	_director.disengage_requested.connect(
		func(_c: Node, reason: int) -> void: _disengages.append(reason)
	)
	_director.lethality_changed.connect(
		func(_c: Node, value: int) -> void: _lethalities.append(value)
	)


## One tick of the real contract, in the order CreatureBehavior actually produces it.
##
## SUSPICION IS ADVANCED HERE because nothing else would. In play that is step 3 of the
## behavior tick, and it is what rebuilds hotspots and decays evidence -- without it
## `submit_evidence` still updates player beliefs synchronously, so target arbitration would
## appear to work while `get_overall_suspicion()` sat at zero forever and every rule that
## reads it silently never fired.
func _tick() -> void:
	_suspicion.advance(TICK)
	_director.advance(TICK)
	_director.exchange(_creature, _report)


## Simulated seconds, in real-sized steps.
func _advance(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_tick()


func _track() -> EncounterTrack:
	return _director.track_for(_creature)


func _directive() -> EncounterDirective:
	return _track().directive


func _make_report(state: CreatureState.State) -> EncounterReport:
	var report := EncounterReport.new()
	report.state = state
	return report


## Puts the fixture into a hunt of a given intensity. `route_distance` defaults to arm's
## length, which is the full-pressure case the menace calibration is quoted against.
func _hunt(
	route_distance: float = 0.0,
	seen: bool = true,
	in_reach: bool = false,
	lurking: bool = false,
	reachable: bool = true
) -> void:
	_report = _make_report(CreatureState.State.HUNTING)
	_report.route_distance = route_distance
	_report.has_visual_contact = seen
	_report.attack_window_open = in_reach
	_report.lurking_at_tunnel_mouth = lurking
	_report.target_reachable = reachable
	_file()


func _state(state: CreatureState.State, at: Vector3 = Vector3.ZERO) -> void:
	_report = _make_report(state)
	_report.position = at
	_file()


## Files the new report at once, rather than leaving it for the next `_tick()`.
##
## THE ORDER INSIDE A TICK IS advance() THEN exchange(), which is the real contract: the
## Director integrates on its own _physics_process and the creature files its report from
## step 4 of the behavior tick. So a report merely ASSIGNED here would not be seen until the
## tick after next, and every test would be reasoning about a creature one transition behind
## the one it set up. Filing on the spot models what actually happens -- the creature changed
## state and told the Director -- and takes the artificial lag out of every assertion.
func _file() -> void:
	if _director != null:
		_director.exchange(_creature, _report)


## A sighting, which is the only evidence that names a player AND carries confidence -- so it
## is the only way to give the Director anybody to arbitrate between. Pushed straight into
## Suspicion here rather than through Perception's signal, because unlike the behavior suite
## nothing in this module listens to Perception at all.
func _see(player: Node, at: Vector3, strength: float = 1.0) -> void:
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION, at, 0.25, strength, 1.0, _suspicion.clock
	)
	evidence.source_player = player
	evidence.source_confidence = 1.0
	_suspicion.submit_evidence(evidence)


## A detached Node3D whose `position` is written directly. See the class docstring.
func _player(named: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var player: Node3D = autofree(Node3D.new())
	player.name = named
	player.position = at
	return player


func _phase() -> EncounterDirective.Phase:
	return _track().phase


func _phase_names() -> Array:
	var found: Array = []
	for entry: Array in _phases:
		found.append(EncounterDirective.phase_name(entry[1]))
	return found


## The WHOLE surface EncounterDirector touches on a creature: one field it reads to reach the
## belief facade, and one signal it subscribes to. Everything else the Director might have
## wanted -- a state, a position, a goal, an HFSM -- is deliberately absent, so a Director
## that grew a reach into Behavior would fail to run here rather than quietly work.
class _FakeCreature:
	extends Node

	signal attack_landed(target: Node, lethality: EncounterDirective.Lethality)

	var suspicion: CreatureSuspicion = null

	func strike(lethality: EncounterDirective.Lethality) -> void:
		attack_landed.emit(null, lethality)
