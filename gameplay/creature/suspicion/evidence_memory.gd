class_name SuspicionEvidenceMemory
extends RefCounted

## Everything the creature currently remembers perceiving, and everywhere it has
## recently checked (suspicion.md, "Evidence Memory" and "Investigation State").
##
## Two lists, deliberately kept separate and never allowed to cancel each other out at
## rest. A search does not delete the evidence it failed to corroborate, because
##
##     "I heard drilling here"                  stays true forever
##     "whatever made that noise is still here" is what searching disconfirms
##
## are different claims, and the spec is built on the difference. Suppression is
## therefore applied at query time, not at write time -- which is also what lets a
## searched area become interesting again as the disconfirmation itself goes stale.
##
## This class holds no clock. Every method that needs one is handed `now` by the
## facade, which is what keeps the whole belief model drivable from a test with no
## tree, no physics and no frames.

var config: SuspicionConfig = null

var records: Array[SuspicionEvidenceRecord] = []
var disconfirmations: Array[SuspicionDisconfirmation] = []

var _next_evidence_id: int = 1
var _next_disconfirmation_id: int = 1


## Returns the stored record, or null when the observation was too weak to be worth
## remembering at all.
func remember(observation: SuspicionEvidence, now: float) -> SuspicionEvidenceRecord:
	if observation == null or config == null:
		return null
	var record := SuspicionEvidenceRecord.from_observation(
		_next_evidence_id, observation, now, config
	)
	if record.effective_strength(now) < config.evidence_min_retention_strength:
		return null
	_next_evidence_id += 1
	records.append(record)
	_enforce_evidence_cap(now)
	return record


## Returns the stored search, or null when it cleared nothing.
##
## An aborted scan arrives at strength 0.0 -- it reached FINISHED so Behavior's
## request-then-poll loop would not hang, but it never actually looked. Storing it
## would be remembering that somewhere was checked when it was not.
func remember_search(
	observation: DisconfirmationObservation, now: float
) -> SuspicionDisconfirmation:
	if observation == null or config == null:
		return null
	var record := SuspicionDisconfirmation.from_observation(
		_next_disconfirmation_id, observation, now, config
	)
	if record.strength < config.investigation_min_observation_strength or record.radius <= 0.0:
		return null
	_next_disconfirmation_id += 1
	disconfirmations.append(record)
	_enforce_disconfirmation_cap(now)
	return record


## Drop what no longer changes any answer. Cheap enough to run every update, and the
## reason nothing here needs an explicit timeout.
func prune(now: float) -> void:
	if config == null:
		return
	var kept_records: Array[SuspicionEvidenceRecord] = []
	for record: SuspicionEvidenceRecord in records:
		if record.effective_strength(now) >= config.evidence_min_retention_strength:
			kept_records.append(record)
	records = kept_records

	var kept_searches: Array[SuspicionDisconfirmation] = []
	for search: SuspicionDisconfirmation in disconfirmations:
		if search.effective_strength(now) >= config.investigation_min_observation_strength:
			kept_searches.append(search)
	disconfirmations = kept_searches


## Total belief that something happened at this point, ignoring whether anyone has
## looked there since.
func support_at(point: Vector3, now: float) -> float:
	var total: float = 0.0
	for record: SuspicionEvidenceRecord in records:
		total += record.support_at(point, now)
	return total


## How thoroughly this point has been checked, 0..1. Clamped because overlapping
## searches of the same spot must not be able to drive belief negative.
func suppression_at(point: Vector3, now: float) -> float:
	var total: float = 0.0
	for search: SuspicionDisconfirmation in disconfirmations:
		total += search.suppression_at(point, now)
	return clampf(total, 0.0, 1.0)


## What the creature still believes might be here: what it perceived, minus what it
## has since ruled out. This is the quantity every spatial answer in the module is
## built from.
func unresolved_at(point: Vector3, now: float) -> float:
	return support_at(point, now) * (1.0 - suppression_at(point, now))


## Records still worth clustering, strongest first. Sorted so hotspot assembly is
## deterministic -- an unordered greedy clustering gives different hotspots for the
## same evidence depending on arrival order, and the tests would be unwritable.
func live_records(now: float) -> Array[SuspicionEvidenceRecord]:
	if config == null:
		return []
	var live: Array[SuspicionEvidenceRecord] = []
	for record: SuspicionEvidenceRecord in records:
		if record.effective_strength(now) >= config.evidence_min_retention_strength:
			live.append(record)
	live.sort_custom(
		func(a: SuspicionEvidenceRecord, b: SuspicionEvidenceRecord) -> bool:
			var difference: float = a.effective_strength(now) - b.effective_strength(now)
			# Ties broken by id so the order is total, not merely mostly-sorted. Two
			# records of identical strength are common: the same drill, twice.
			return a.id < b.id if is_zero_approx(difference) else difference > 0.0
	)
	return live


func find_record(id: int) -> SuspicionEvidenceRecord:
	for record: SuspicionEvidenceRecord in records:
		if record.id == id:
			return record
	return null


func clear() -> void:
	records.clear()
	disconfirmations.clear()


## Weakest first, because a hard cap that dropped the OLDEST would throw away the
## direct sighting of thirty seconds ago in favour of six faint footsteps from just
## now -- the alien would grow more forgetful the more it perceived.
func _enforce_evidence_cap(now: float) -> void:
	if records.size() <= config.max_evidence_count:
		return
	records.sort_custom(
		func(a: SuspicionEvidenceRecord, b: SuspicionEvidenceRecord) -> bool:
			return a.effective_strength(now) > b.effective_strength(now)
	)
	records.resize(config.max_evidence_count)


func _enforce_disconfirmation_cap(now: float) -> void:
	if disconfirmations.size() <= config.max_disconfirmation_count:
		return
	disconfirmations.sort_custom(
		func(a: SuspicionDisconfirmation, b: SuspicionDisconfirmation) -> bool:
			return a.effective_strength(now) > b.effective_strength(now)
	)
	disconfirmations.resize(config.max_disconfirmation_count)
