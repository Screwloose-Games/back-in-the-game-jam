class_name CreatureSuspicion
extends Node

## The facade Behavior and the Director talk to (suspicion.md, "Public API").
##
## Answers exactly one question: GIVEN EVERYTHING I HAVE PERCEIVED RECENTLY, WHAT DO I
## CURRENTLY BELIEVE IS WORTH INVESTIGATING, AND WHERE? It does not decide what to do
## about it. Behavior reads the answer and picks an action; the Director reads the
## per-player answer and picks a victim; Navigation never talks to this class at all.
##
##     Perception --> submit_evidence / submit_disconfirmation --> here
##     here       --> hotspots, overall suspicion, player beliefs --> Behavior, Director
##
## Extends Node, NOT Node3D, and that is deliberate. Suspicion has no position of its
## own; giving it a transform invites someone to read `global_position` off it and
## quietly make a spatial belief system depend on where its owner is standing.
##
## THIS CLASS NEVER LOOKS AT THE WORLD. No groups, no raycasts, no reading a player's
## transform. Everything it believes arrived through submit_evidence, because an alien
## that peeks at the truth to sharpen a hotspot works VISIBLY BETTER while destroying
## the entire design, and no behavioural test would ever catch it.
## `tools/verify_suspicion_static.gd` fails the build on the attempt.
##
## The write API is the only write API. There is deliberately no `reduce_suspicion()`,
## `clear_hotspot()` or `mark_investigation_complete()`: Behavior makes the creature
## investigate, Perception observes the result, and belief updates from that. Letting
## Behavior subtract suspicion directly would let it declare a room searched without
## ever going there.

## The creature's total current concern moved. Only fires past
## SuspicionConfig.suspicion_change_epsilon -- suspicion drifts every single frame, and
## an unconditioned signal would wake every listener 60 times a second forever.
signal overall_suspicion_changed(value: float)
## A new place is worth attention. The id is stable for the hotspot's whole life.
signal hotspot_created(hotspot_id: int)
signal hotspot_updated(hotspot_id: int)
## Decayed or searched below SuspicionConfig.resolved_hotspot_threshold. NOT the same
## as "the creature has finished investigating" -- Behavior decides that.
signal hotspot_resolved(hotspot_id: int)
signal player_suspicion_changed(player: Node, suspicion: float)

@export var config: SuspicionConfig = null:
	set = _set_config

## Seconds since this suspicion came alive. THE ONLY CLOCK IN THE MODULE, and NOT the
## same clock as CreaturePerception's.
##
## Both start at 0.0 when their node is constructed, so they agree only if the two
## nodes were built on the same frame -- which nothing guarantees. Evidence is
## therefore stamped with THIS clock on arrival and decays from that;
## `SuspicionEvidence.observed_at` is kept as data. Getting this wrong is silent:
## records would arrive pre-decayed or with negative age, and the alien would be
## inexplicably forgetful with nothing in the log.
##
## Not wall time either. Time.get_ticks_msec() ignores get_tree().paused and
## Engine.time_scale, so belief would keep decaying in a paused game, and no test could
## drive it without freezing the machine.
var clock: float = 0.0

var memory: SuspicionEvidenceMemory = null
var hotspot_field: SuspicionHotspotField = null
var player_beliefs: SuspicionPlayerBeliefs = null

## Optional `func(position: Vector3) -> int`, for
## SuspicionConfig.require_same_spatial_region_for_merge. Supplied by Spatial Memory or
## by a level; unset means every point is in the same region and the flag does nothing.
##
## A Callable rather than a dependency on purpose: it keeps the thin-cave-wall rule
## expressible without Suspicion ever owning geometry or touching the physics server.
var region_resolver: Callable = Callable():
	set = _set_region_resolver

var _overall_suspicion: float = 0.0
var _last_broadcast_suspicion: float = 0.0
var _next_hotspot_update: float = 0.0
var _dirty_players: Array[int] = []


func _init() -> void:
	# Built here rather than in _ready(), so a suspicion created with .new() and never
	# added to a tree is fully usable. That is what lets the entire belief model be
	# driven from GUT with no tree, no physics and no frames.
	memory = SuspicionEvidenceMemory.new()
	hotspot_field = SuspicionHotspotField.new()
	player_beliefs = SuspicionPlayerBeliefs.new()
	_set_config(config)


func _ready() -> void:
	if config == null:
		config = SuspicionConfig.new()
		push_warning("CreatureSuspicion has no SuspicionConfig; running on script defaults.")


func _physics_process(delta: float) -> void:
	advance(delta)


## The single tick entry point, public so a test can drive it exactly.
##
## 180 calls of advance(1.0/60.0) is one deterministic simulated second, with no awaits
## and no physics. The runtime suite still has to prove _physics_process actually calls
## this -- no GUT test can see that wire, and every timing assertion below would pass
## against a facade whose _physics_process had been deleted.
func advance(delta: float) -> void:
	clock += delta
	player_beliefs.advance(delta)
	_flush_player_signals()
	if config == null:
		return
	if clock < _next_hotspot_update:
		return
	_next_hotspot_update = clock + config.hotspot_update_interval
	memory.prune(clock)
	_rebuild_hotspots()


# ----- Perception -> Suspicion (the only write API) -----


## Positive evidence. Wire it straight to CreaturePerception.evidence_observed.
func submit_evidence(evidence: SuspicionEvidence) -> void:
	if config == null:
		return
	var record: SuspicionEvidenceRecord = memory.remember(evidence, clock)
	if record == null:
		return
	var player: Node = player_beliefs.observe(record, clock)
	if player != null and not _dirty_players.has(player.get_instance_id()):
		_dirty_players.append(player.get_instance_id())
	# Rebuild on the next tick rather than here. A creature standing in a room with a
	# drilling player receives evidence many times per frame, and reclustering on each
	# arrival is quadratic work for an answer nothing reads until the next frame.
	_next_hotspot_update = minf(_next_hotspot_update, clock)


func submit_evidence_batch(evidence: Array[SuspicionEvidence]) -> void:
	for item: SuspicionEvidence in evidence:
		submit_evidence(item)


## Negative evidence: "I checked there and found nothing." Wire it to
## CreaturePerception.disconfirmation_observed.
##
## This is how suspicion goes DOWN in a specific place. It reduces the current belief
## that something is still there; it never touches the historical record that something
## happened, which is why a searched hotspot can become interesting again later.
func submit_disconfirmation(observation: DisconfirmationObservation) -> void:
	if config == null:
		return
	if memory.remember_search(observation, clock) != null:
		_next_hotspot_update = minf(_next_hotspot_update, clock)


# ----- Behavior -> Suspicion (reads) -----


## Total current concern, 0..1, derived from the hotspots rather than stored. Useful
## for HFSM transitions -- but the thresholds are Behavior's, and Suspicion must never
## transition anything itself.
func get_overall_suspicion() -> float:
	return _overall_suspicion


## The live hotspot objects, strongest first. Read-only by convention: they are
## recomputed in place on the next update, so call duplicate_hotspot() on anything you
## intend to keep, and never write to one as a way of changing belief.
func get_hotspots() -> Array[SuspicionHotspot]:
	return hotspot_field.above(0.0)


func get_hotspots_above(minimum_suspicion: float) -> Array[SuspicionHotspot]:
	return hotspot_field.above(minimum_suspicion)


func get_strongest_hotspot() -> SuspicionHotspot:
	return hotspot_field.strongest()


func get_hotspot(hotspot_id: int) -> SuspicionHotspot:
	return hotspot_field.find(hotspot_id)


## How much unresolved belief is concentrated around a place, ignoring hotspot
## boundaries. Sampled over the sphere rather than read at the centre, so a search
## region that overlaps half a hotspot reports half of it.
func get_suspicion_near(position: Vector3, radius: float) -> float:
	if config == null:
		return 0.0
	var probe := SuspicionHotspot.new()
	probe.position = position
	probe.radius = maxf(radius, 0.0)
	var total: float = 0.0
	var points: PackedVector3Array = hotspot_field.sample_points(probe)
	for point: Vector3 in points:
		total += memory.unresolved_at(point, clock)
	return config.saturate(total / float(maxi(points.size(), 1)), config.hotspot_saturation_rate)


## Where inside a hotspot the creature still has reason to look. Behavior asks this
## repeatedly as it searches: each completed search feeds a disconfirmation back in,
## and the answer moves into whatever is still unchecked.
##
## Returns the hotspot's own centre for an unknown id, so a caller that raced a
## `hotspot_resolved` still gets somewhere to stand rather than the origin.
func get_best_unresolved_location(hotspot_id: int) -> Vector3:
	var hotspot: SuspicionHotspot = hotspot_field.find(hotspot_id)
	if hotspot == null:
		return Vector3.ZERO
	return hotspot_field.best_unresolved_point(hotspot, memory, clock)


# ----- Director -> Suspicion (reads) -----


func get_player_suspicion(player: Node) -> float:
	return player_beliefs.get_suspicion(player)


func get_player_source_confidence(player: Node) -> float:
	return player_beliefs.get_source_confidence(player)


## Who the creature is most suspicious of. A candidate, NOT a target -- stickiness and
## retarget thresholds belong to the Director, which is why this does not commit to
## anything.
func get_best_player_candidate() -> PlayerSuspicionCandidate:
	return player_beliefs.get_best_candidate()


# ----- debug -----


## Everything the overlay needs, computed on demand. Not a cache and not a history.
func debug_state() -> Dictionary:
	var hotspots: Array = []
	for hotspot: SuspicionHotspot in hotspot_field.hotspots:
		hotspots.append(hotspot.to_dictionary())
	var players: Array = []
	for candidate: PlayerSuspicionCandidate in player_beliefs.get_candidates():
		players.append(candidate.to_dictionary())
	return {
		"clock": clock,
		"overall": _overall_suspicion,
		"evidence": memory.records.size(),
		"disconfirmations": memory.disconfirmations.size(),
		"hotspots": hotspots,
		"players": players,
	}


## Forget everything. For the sandbox and for tests; nothing in the AI should call it,
## because "the creature stops being suspicious" is a thing that has to be earned by
## searching, not asserted.
func reset() -> void:
	memory.clear()
	hotspot_field.clear()
	player_beliefs.clear()
	_overall_suspicion = 0.0
	_last_broadcast_suspicion = 0.0
	_dirty_players.clear()


# ----- internals -----


func _rebuild_hotspots() -> void:
	var changes: Dictionary = hotspot_field.rebuild(memory, clock)
	for id: int in changes["resolved"]:
		hotspot_resolved.emit(id)
	for id: int in changes["created"]:
		hotspot_created.emit(id)
	for id: int in changes["updated"]:
		hotspot_updated.emit(id)
	_recompute_overall()


## Overall suspicion is DERIVED from the spatial hotspots, never accumulated
## separately. A second counter would drift from the hotspots the moment a search
## cleared one, and the creature would stay alert about nowhere in particular.
##
## Saturating rather than a plain maximum, so three moderate leads read as slightly
## worse than one -- but never past 1.0, and never enough for a scatter of faint
## noises to add up to certainty.
func _recompute_overall() -> void:
	var total: float = 0.0
	for hotspot: SuspicionHotspot in hotspot_field.hotspots:
		total += hotspot.suspicion
	_overall_suspicion = (
		clampf(config.saturate(total, config.hotspot_saturation_rate), 0.0, 1.0)
		if config != null
		else 0.0
	)
	if absf(_overall_suspicion - _last_broadcast_suspicion) < _change_epsilon():
		return
	_last_broadcast_suspicion = _overall_suspicion
	overall_suspicion_changed.emit(_overall_suspicion)


func _change_epsilon() -> float:
	return config.suspicion_change_epsilon if config != null else 0.0


## Player signals are emitted from the tick, not from submit_evidence, so a listener
## cannot re-enter this class part-way through ingesting a batch.
func _flush_player_signals() -> void:
	if _dirty_players.is_empty():
		return
	var ids: Array[int] = _dirty_players.duplicate()
	_dirty_players.clear()
	for id: int in ids:
		var player := instance_from_id(id) as Node
		if is_instance_valid(player):
			player_suspicion_changed.emit(player, player_beliefs.get_suspicion(player))


func _set_config(value: SuspicionConfig) -> void:
	config = value
	# The parts exist from _init(), so this runs correctly whether the value arrived
	# from the scene loader or from a test assigning it by hand.
	if memory != null:
		memory.config = value
		hotspot_field.config = value
		player_beliefs.config = value


func _set_region_resolver(value: Callable) -> void:
	region_resolver = value
	if hotspot_field != null:
		hotspot_field.region_resolver = value
