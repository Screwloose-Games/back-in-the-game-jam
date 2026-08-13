extends GutTest

## Shared fixture for the suites that exercise an assembled CreatureSuspicion.
##
## Not collected as a test script itself -- GUT's default prefix is `test_`, and this
## file deliberately does not have it.
##
## The fixture builds a facade that was never added to a scene tree and captures all
## five signals. Nothing here needs physics, a viewport, a frame or a wall clock: the
## whole belief model is reachable by calling advance() by hand, which is the property
## that keeps this suite fast enough to run on every commit.
##
## `hotspot_update_interval` is forced to 0.0 so a rebuild happens on every tick. In
## play it is throttled; in a test, "submit then tick then assert" has to mean exactly
## that or every assertion below acquires an invisible 0.2 s of slack.

const TICK: float = 1.0 / 60.0
## Perception's activity scan reports these two. Hearing is event-driven and never
## deliberately checks a region, so this is what a real search arrives with.
const SEARCHED_BY_SIGHT_AND_TOUCH: int = (
	(1 << int(SuspicionEvidence.Sense.VISION)) | (1 << int(SuspicionEvidence.Sense.TOUCH))
)

var _suspicion: CreatureSuspicion = null
var _config: SuspicionConfig = null
var _created: Array[int] = []
var _updated: Array[int] = []
var _resolved: Array[int] = []
var _overall: Array[float] = []
var _player_changes: Array = []


func before_each() -> void:
	_config = SuspicionConfig.new()
	_config.hotspot_update_interval = 0.0

	_suspicion = autofree(CreatureSuspicion.new())
	_suspicion.config = _config

	_created = []
	_updated = []
	_resolved = []
	_overall = []
	_player_changes = []
	_suspicion.hotspot_created.connect(func(id: int) -> void: _created.append(id))
	_suspicion.hotspot_updated.connect(func(id: int) -> void: _updated.append(id))
	_suspicion.hotspot_resolved.connect(func(id: int) -> void: _resolved.append(id))
	_suspicion.overall_suspicion_changed.connect(func(v: float) -> void: _overall.append(v))
	_suspicion.player_suspicion_changed.connect(
		func(player: Node, value: float) -> void: _player_changes.append([player, value])
	)


## Simulated seconds, in real-sized steps. Use for anything where hotspot smoothing or
## signal cadence matters.
func _advance(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_suspicion.advance(TICK)


## The same elapsed time in one step. Decay is a closed-form function of age, so this
## is exact for anything that only cares how much belief is left -- and it is hundreds
## of times cheaper than ticking through forty simulated seconds.
func _advance_coarse(seconds: float) -> void:
	_suspicion.advance(seconds)


## One tick, so a submission gets folded into the hotspot field.
func _settle() -> void:
	_suspicion.advance(TICK)


func _hear(
	position: Vector3, strength: float = 0.8, uncertainty: float = 4.0, confidence: float = 0.9
) -> SuspicionEvidence:
	return SuspicionEvidence.make(
		SuspicionEvidence.Sense.HEARING, position, uncertainty, strength, confidence, 0.0
	)


func _see(position: Vector3, player: Node, strength: float = 1.0) -> SuspicionEvidence:
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION, position, 0.25, strength, 1.0, 0.0
	)
	evidence.source_player = player
	evidence.source_confidence = 1.0
	return evidence


func _search(
	position: Vector3,
	radius: float,
	strength: float = 0.9,
	senses: int = SEARCHED_BY_SIGHT_AND_TOUCH
) -> DisconfirmationObservation:
	return DisconfirmationObservation.make(position, radius, strength, 0.0, senses)


func _player(named: String) -> Node3D:
	var player: Node3D = autofree(Node3D.new())
	player.name = named
	return player


## Submit one noise, tick once, and hand back the hotspot it formed.
func _hotspot_from_one_noise(
	position: Vector3 = Vector3.ZERO, uncertainty: float = 4.0
) -> SuspicionHotspot:
	_suspicion.submit_evidence(_hear(position, 0.9, uncertainty))
	_settle()
	return _suspicion.get_strongest_hotspot()
