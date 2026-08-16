class_name CreaturePerception
extends Node3D

## The facade the rest of the alien AI talks to (perception.md sections 5, 24, 25).
##
## Answers exactly one question: WHAT CAN THE ALIEN OBSERVE RIGHT NOW? It does not
## answer what the alien remembers, how suspicious it should be, or where it should
## go. Those belong to Suspicion, Spatial Memory and Behavior.
##
## Contains very little sensing logic itself. It owns the senses, gives them a clock
## and a probe, and routes what they produce:
##
##     Hearing / Vision / Touch  --> evidence_observed, disconfirmation_observed
##     GeometryPerception        --> geometry_observed
##
## OUTPUT IS SIGNALS, NOT DIRECT CALLS. Sections 20-21 describe
## `suspicion.submit_evidence(...)` and `spatial_memory.observe_geometry(...)`; this
## implementation emits instead and lets consumers connect. When those modules land,
## the spec's call API is a four-line adapter. See the module README.
##
## What this class must never do (section 31): transition an HFSM, select a target,
## change a suspicion value, touch a navigation path, or remember anything. The
## banned-state list in section 28 is asserted by test_dispatch.gd, not just written
## down here.

## Positive evidence of activity. Consumed by Suspicion.
signal evidence_observed(evidence: SuspicionEvidence)
## "I checked and found nothing." Consumed by Suspicion. Never emitted for the same
## scan that emitted evidence -- see _finish_activity_scan.
signal disconfirmation_observed(observation: DisconfirmationObservation)
## A batch of space observations. Consumed by Spatial Memory. NEVER carries activity
## evidence, and evidence_observed never carries geometry.
signal geometry_observed(observations: Array[GeometryObservation])
signal activity_scan_finished(found_evidence: bool)
signal geometry_scan_finished(observation_count: int)
## Debug-only, and the reason this class needs no memory to be debuggable
## (section 30). Fires for EVERY noise reaching this creature, including ones it
## failed to hear -- `evidence` is null then. That is what separates "the alien
## didn't hear me" from "the alien heard me and didn't care" (section 29).
signal noise_evaluated(
	event: NoiseEvent, evidence: SuspicionEvidence, distance: float, obstruction: float
)

@export var config: PerceptionConfig = null:
	set = _set_config
## Explicitly wired candidates. Wins over `candidate_group` when non-empty.
@export var targets: Array[Node3D] = []
## Fallback source of candidates. Vision evaluates known targets rather than
## searching the world (section 13), so something has to name them.
@export var candidate_group: StringName = &"perceivable"
## Where vision looks from and what it looks along (-Z, matching Vector3.FORWARD and
## this project's facing convention). Defaults to this node.
@export var eye: Node3D = null
## Optional. Its overlaps become Touch observations (section 15).
@export var proximity_area: Area3D = null
## Ambient visibility modifier, 0..1 (section 13's "lighting or visibility
## modifiers"). A lighting system can drive this; nothing here computes it.
@export_range(0.0, 1.0, 0.01) var light_level: float = 1.0
## Pins hearing's positional jitter. Two creatures with the same seed mishear a
## noise identically, which is wrong in play and essential in a test.
@export var hearing_seed: int = 0

## Seconds since this perception came alive. THE ONLY CLOCK IN THE MODULE.
##
## Not wall time. Time.get_ticks_msec() ignores get_tree().paused and
## Engine.time_scale, so evidence would keep ageing in a paused game, and it cannot
## be driven from a test without freezing the machine. Starting at 0.0 also keeps
## observed_at small enough for Suspicion's decay arithmetic to use directly.
var clock: float = 0.0

var hearing: CreatureHearing = null
var vision: CreatureVision = null
var touch: CreatureTouch = null
var geometry_perception: CreatureGeometryPerception = null
var probe: PerceptionProbe = null

var _alertness: float = 0.0
var _activity_scan: PerceptionScan = null
var _geometry_scan: PerceptionScan = null
## Targets the current activity scan has already reported. Transient scan state, of
## exactly the kind section 28 permits -- cleared on every request, and never read
## outside the scan that filled it.
var _activity_found: Array[Node3D] = []
var _geometry_cells: Array[AABB] = []
var _geometry_batch: Array[GeometryObservation] = []
var _next_vision_scan: float = 0.0
var _next_passive_geometry: float = 0.0
var _self_rids: Array[RID] = []


func _init() -> void:
	# Built here, not in _ready(), so a facade created with .new() and never added to
	# a tree is fully usable. That is what lets the scan machine, the clock and the
	# whole dispatch path be tested in GUT rather than only in the slow suite.
	probe = PerceptionProbe.new()
	hearing = CreatureHearing.new()
	vision = CreatureVision.new()
	touch = CreatureTouch.new()
	geometry_perception = CreatureGeometryPerception.new()
	_activity_scan = PerceptionScan.new()
	_geometry_scan = PerceptionScan.new()
	hearing.rng = RandomNumberGenerator.new()


func _ready() -> void:
	if config == null:
		config = PerceptionConfig.new()
		push_warning("CreaturePerception has no PerceptionConfig; running on script defaults.")
	hearing.rng.seed = hearing_seed
	probe.bind(get_world_3d())
	_collect_self_rids()
	if proximity_area != null:
		proximity_area.body_entered.connect(_on_proximity_body_entered)


func _physics_process(delta: float) -> void:
	advance(delta)


## The single tick entry point, public so a test can drive it exactly.
##
## 180 calls of advance(1.0/60.0) is one deterministic simulated second with no
## awaits and no physics. The runtime suite still has to prove _physics_process
## actually calls this -- no GUT test can see that wire.
func advance(delta: float) -> void:
	clock += delta
	_tick_vision()
	_tick_passive_geometry()
	_tick_activity_scan(delta)
	_tick_geometry_scan(delta)


# ----- external sensory events (section 24) -----


## Section 6: hearing is event-driven. The world pushes noises in.
func receive_noise(event: NoiseEvent) -> void:
	if event == null or config == null:
		return
	var listener: Vector3 = _own_position()
	var distance: float = listener.distance_to(event.position)
	var obstruction: float = 0.0
	if config.hearing_enabled and distance <= config.hearing_max_range:
		obstruction = probe.obstruction_between(listener, event.position, config.world_mask)
	var evidence: SuspicionEvidence = hearing.perceive_noise(event, listener, obstruction, clock)
	noise_evaluated.emit(event, evidence, distance, obstruction)
	if evidence != null:
		_submit_activity_evidence(evidence)


## Section 15. Call from a body collision, an attack volume, or wire an Area3D to
## `proximity_area` and let _ready() connect it.
func receive_contact(body: Node, contact_position: Vector3) -> void:
	var evidence: SuspicionEvidence = touch.perceive_contact(body, contact_position, clock)
	if evidence != null:
		_submit_activity_evidence(evidence)


func receive_proximity(body: Node, body_position: Vector3) -> void:
	var distance: float = _own_position().distance_to(body_position)
	var evidence: SuspicionEvidence = touch.perceive_proximity(body, body_position, distance, clock)
	if evidence != null:
		_submit_activity_evidence(evidence)


# ----- requests to observe (sections 18-19, 22-23) -----


## Behavior asks for a deliberate search. It does NOT get to say what the search
## finds -- that is the whole point of routing it through here rather than letting
## Behavior tell Suspicion to clear a hotspot.
func request_activity_scan(region: AABB, thoroughness: float) -> void:
	_activity_found.clear()
	var can_run: bool = config != null and probe.is_bound() and region.get_volume() > 0.0
	_activity_scan.begin(
		region,
		thoroughness,
		config.scan_duration(thoroughness) if config != null else 0.0,
		config.scan_sample_count(thoroughness) if config != null else 1
	)
	if not can_run:
		# Completes anyway, with a zero-strength disconfirmation. A scan that silently
		# never finishes hangs Behavior's request-then-poll loop forever on a config
		# flag, which is worse than a scan that honestly found nothing.
		_activity_scan.finish_immediately()
		_finish_activity_scan()


## Navigation asks for validation when reality contradicts remembered geometry
## (section 18). It says "my expectation seems wrong, look here", never "the
## geometry is now SOLID".
func request_geometry_scan(
	region: AABB, reason: CreatureGeometryPerception.GeometryScanReason
) -> void:
	_geometry_batch.clear()
	_geometry_cells.clear()
	var can_run: bool = config != null and config.geometry_perception_enabled and probe.is_bound()
	if can_run:
		# Coarsen to fit the budget rather than truncating the cell list -- a truncated
		# scan reports as complete while leaving part of the region unobserved. See
		# CreatureGeometryPerception.resolution_for.
		_geometry_cells = CreatureGeometryPerception.subdivide(
			region,
			CreatureGeometryPerception.resolution_for(
				region, config.geometry_clearance_resolution, config.max_scan_samples
			)
		)
	_geometry_scan.begin(
		region,
		1.0,
		config.geometry_scan_duration if config != null else 0.0,
		maxi(_geometry_cells.size(), 1),
		int(reason)
	)
	if _geometry_cells.is_empty():
		_geometry_scan.finish_immediately()
		_finish_geometry_scan()


func is_activity_scan_active() -> bool:
	return _activity_scan.is_active()


func is_geometry_scan_active() -> bool:
	return _geometry_scan.is_active()


func is_activity_scan_complete() -> bool:
	return _activity_scan.is_complete()


## Stops a sweep that Behavior has changed its mind about.
##
## Without this, an alien that abandons a search mid-scan -- a hotspot resolving, a hunt
## starting -- leaves the scan running, and it later reports a disconfirmation for a region
## the creature is no longer standing in. The alien would clear a place it never checked,
## which is the one thing searching must not be able to do. Emits nothing: a cancelled scan
## observed nothing, so there is nothing to report.
func cancel_activity_scan() -> void:
	_activity_scan.cancel()


## Whether the last activity scan gave up rather than finishing.
##
## "Never looked" and "checked and found nothing" are different claims, and only this tells
## them apart -- an aborted scan still reaches FINISHED so a caller's request-then-poll loop
## cannot hang, and still reports a disconfirmation, but at ZERO strength, which suppresses
## nothing. A caller that treated it as a completed search would believe an area was cleared
## by a scan that never ran.
func activity_scan_aborted() -> bool:
	return _activity_scan.aborted


func is_geometry_scan_complete() -> bool:
	return _geometry_scan.is_complete()


# ----- alertness context (section 14) -----


## Read-only context from Suspicion. It changes HOW HARD the creature looks -- scan
## frequency, whether vision runs at all -- and must never change what a sense
## reports for identical input. test_dispatch.gd asserts that.
func set_alertness_context(value: float) -> void:
	_alertness = clampf(value, 0.0, 1.0)


func get_alertness() -> float:
	return _alertness


## Candidates vision will evaluate. Explicit wiring wins; the group is the fallback
## so a level can drop a creature in without wiring anything.
func candidate_targets() -> Array[Node3D]:
	var from_group: Array[Node3D] = []
	if targets.is_empty() and is_inside_tree() and candidate_group != &"":
		for node: Node in get_tree().get_nodes_in_group(candidate_group):
			var node_3d := node as Node3D
			if node_3d != null:
				from_group.append(node_3d)
	return CreatureVision.choose_targets(targets, from_group)


func eye_transform() -> Transform3D:
	var source: Node3D = eye if eye != null else self
	return source.global_transform if source.is_inside_tree() else source.transform


## Everything the debug overlay needs, computed on demand.
##
## NOT a cache and not a history. If this returned "recent evidence" the facade
## would be holding memory, which section 28 forbids -- the overlay keeps its own
## decaying buffer off the signals instead.
func debug_state() -> Dictionary:
	return {
		"clock": clock,
		"alertness": _alertness,
		"vision_active": config != null and config.vision_gate(_alertness),
		"vision_interval": config.vision_scan_interval(_alertness) if config != null else 0.0,
		"candidates": candidate_targets().size(),
		"activity_scan_active": _activity_scan.is_active(),
		"activity_scan_progress": _activity_scan.progress(),
		"activity_scan_region": _activity_scan.region,
		"geometry_scan_active": _geometry_scan.is_active(),
		"geometry_scan_progress": _geometry_scan.progress(),
		"geometry_scan_region": _geometry_scan.region,
		"probe_bound": probe.is_bound(),
	}


# ----- internal dispatch (section 25) -----
#
# One place each. Individual senses therefore never need a reference to Suspicion,
# to Spatial Memory, or to each other.


func _submit_activity_evidence(evidence: SuspicionEvidence) -> void:
	evidence_observed.emit(evidence)


func _submit_disconfirmation(observation: DisconfirmationObservation) -> void:
	disconfirmation_observed.emit(observation)


func _submit_geometry(observations: Array[GeometryObservation]) -> void:
	if not observations.is_empty():
		geometry_observed.emit(observations)


# ----- periodic senses -----


func _tick_vision() -> void:
	if config == null or not config.vision_gate(_alertness) or not vision.enabled:
		return
	if clock < _next_vision_scan:
		return
	_next_vision_scan = clock + config.vision_scan_interval(_alertness)

	var eye_xform: Transform3D = eye_transform()
	for target: Node3D in candidate_targets():
		if target == null:
			continue
		var target_position: Vector3 = _node_position(target)
		var has_los: bool = probe.has_clear_line(
			eye_xform.origin, target_position, config.world_mask, _self_rids
		)
		var evidence: SuspicionEvidence = vision.evaluate_target(
			target, target_position, eye_xform, has_los, light_level, clock
		)
		if evidence != null:
			_submit_activity_evidence(evidence)


func _tick_passive_geometry() -> void:
	if config == null or not config.geometry_perception_enabled or not probe.is_bound():
		return
	if clock < _next_passive_geometry:
		return
	_next_passive_geometry = clock + config.geometry_passive_scan_interval

	var origin: Vector3 = _own_position()
	var region: AABB = geometry_perception.passive_region(origin)
	_submit_geometry(
		geometry_perception.scan_region(
			probe, region, origin, config.geometry_passive_scan_radius, clock
		)
	)


func _tick_activity_scan(delta: float) -> void:
	var due: int = _activity_scan.advance(delta)
	var first: int = _activity_scan.samples_done - due
	for offset: int in due:
		_sample_activity(first + offset)
	if _activity_scan.just_finished():
		_finish_activity_scan()


## One look at one point inside the search region. A candidate counts as found when
## it is inside the region AND reachable by a clear line from the sampled point --
## searching a dead end from the doorway should not see round the corner.
##
## EACH TARGET IS REPORTED AT MOST ONCE PER SCAN. Without that, a thorough search of
## a room a player is standing in emits one near-identical maximum-strength record
## per sample -- up to max_scan_samples of them, all saying the same thing -- and
## Suspicion is handed 256 pieces of evidence for one sighting. Finding the player
## twice in the same sweep is not twice the news.
func _sample_activity(index: int) -> void:
	if config == null:
		return
	var point: Vector3 = _activity_scan.sample_point(index)
	for target: Node3D in candidate_targets():
		if target == null or _activity_found.has(target):
			continue
		var target_position: Vector3 = _node_position(target)
		if not _activity_scan.region.has_point(target_position):
			continue
		if not probe.has_clear_line(point, target_position, config.world_mask, _self_rids):
			continue
		var evidence := SuspicionEvidence.make(
			SuspicionEvidence.Sense.VISION,
			target_position,
			config.vision_min_uncertainty,
			1.0,
			1.0,
			clock
		)
		evidence.source_player = target
		evidence.source_confidence = 1.0
		evidence.category = &"search_contact"
		_activity_found.append(target)
		_activity_scan.note_positive()
		_submit_activity_evidence(evidence)


## Section 19's fork, drawn literally: a finished scan produces evidence OR a
## disconfirmation. Never both, never neither.
func _finish_activity_scan() -> void:
	if _activity_scan.found_any:
		activity_scan_finished.emit(true)
		return
	var region: AABB = _activity_scan.region
	var radius: float = maxf(region.size.length() * 0.5, 0.0)
	if config != null:
		radius = maxf(radius, config.search_scan_radius) if region.get_volume() > 0.0 else 0.0
	var strength: float = 0.0
	# An aborted scan clears NOTHING. It reached FINISHED so Behavior does not hang,
	# but it never looked, and reporting it at full strength would tell Suspicion a
	# real hotspot had been thoroughly examined.
	if config != null and not _activity_scan.aborted:
		strength = config.search_disconfirmation_strength * _activity_scan.thoroughness
	_submit_disconfirmation(
		DisconfirmationObservation.make(
			region.get_center(), radius, strength, clock, _senses_checked()
		)
	)
	activity_scan_finished.emit(false)


## Which senses took part in a search. Suspicion clears less on the word of one
## sense than of three, and cannot tell them apart without this.
func _senses_checked() -> int:
	if config == null:
		return 0
	var mask: int = 0
	if config.vision_gate(_alertness) and vision.enabled:
		mask |= DisconfirmationObservation.sense_bit(SuspicionEvidence.Sense.VISION)
	if config.touch_enabled and touch.enabled:
		mask |= DisconfirmationObservation.sense_bit(SuspicionEvidence.Sense.TOUCH)
	return mask


func _tick_geometry_scan(delta: float) -> void:
	var due: int = _geometry_scan.advance(delta)
	var first: int = _geometry_scan.samples_done - due
	for offset: int in due:
		var index: int = first + offset
		if index < 0 or index >= _geometry_cells.size():
			continue
		var observation: GeometryObservation = geometry_perception.observe_cell(
			probe,
			_geometry_cells[index],
			_own_position(),
			config.geometry_validation_radius if config != null else 1.0,
			clock
		)
		if observation != null:
			_geometry_batch.append(observation)
	if _geometry_scan.just_finished():
		_finish_geometry_scan()


func _finish_geometry_scan() -> void:
	var batch: Array[GeometryObservation] = _geometry_batch.duplicate()
	_geometry_batch.clear()
	_submit_geometry(batch)
	geometry_scan_finished.emit(batch.size())


# ----- plumbing -----


func _set_config(value: PerceptionConfig) -> void:
	config = value
	# The senses exist from _init(), so this runs correctly whether the value came
	# from the scene loader or from a test assigning it by hand.
	if hearing != null:
		hearing.config = value
		vision.config = value
		touch.config = value
		geometry_perception.config = value


func _on_proximity_body_entered(body: Node3D) -> void:
	receive_contact(body, _node_position(body))


## Collision shapes belonging to the creature itself, so a line-of-sight ray fired
## from inside its own body does not report the creature as a wall.
func _collect_self_rids() -> void:
	_self_rids.clear()
	var root: Node = get_parent() if get_parent() != null else self
	for node: Node in _descendants(root):
		var collider := node as CollisionObject3D
		if collider != null:
			_self_rids.append(collider.get_rid())


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_descendants(child))
	return found


func _own_position() -> Vector3:
	return global_position if is_inside_tree() else position


## Node3D.global_position needs the node to be in a tree. Reading `position` for a
## detached node is exact for a lone node and keeps the facade usable in GUT.
func _node_position(node: Node) -> Vector3:
	var node_3d := node as Node3D
	if node_3d == null:
		return Vector3.ZERO
	return node_3d.global_position if node_3d.is_inside_tree() else node_3d.position
