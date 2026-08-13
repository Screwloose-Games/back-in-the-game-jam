extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## Evidence ingestion, independent decay, and the two caps.
##
## The properties here are the ones suspicion.md calls "Effective Evidence Strength":
## belief fades on its own schedule per sense, nothing is deleted at an arbitrary
## timeout, and remembering more must never cost unbounded memory.


func test_the_clock_starts_at_zero_and_advances_with_delta() -> void:
	assert_eq(_suspicion.clock, 0.0)
	_advance(1.0)
	assert_almost_eq(_suspicion.clock, 1.0, TICK)


## The load-bearing decision in the whole module. Perception stamps observed_at on ITS
## clock; if Suspicion decayed from that value, evidence handed over by a perception
## that has been alive for two minutes would arrive already dead.
func test_decay_runs_from_arrival_not_from_perceptions_timestamp() -> void:
	_advance_coarse(120.0)
	var stale := _hear(Vector3.ZERO)
	stale.observed_at = 0.0  # a perception that booted two minutes before this one

	_suspicion.submit_evidence(stale)
	_settle()

	var record: SuspicionEvidenceRecord = _suspicion.memory.records[0]
	assert_almost_eq(record.received_at, 120.0, 0.1, "stamped on arrival")
	assert_eq(record.observed_at, 0.0, "and the original is kept as data")
	assert_gt(record.effective_strength(_suspicion.clock), 0.5, "it must not arrive pre-decayed")


func test_evidence_decays_toward_zero_without_being_deleted_abruptly() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	var record: SuspicionEvidenceRecord = _suspicion.memory.records[0]
	var fresh: float = record.effective_strength(_suspicion.clock)

	_advance_coarse(12.0)
	var later: float = record.effective_strength(_suspicion.clock)

	assert_lt(later, fresh)
	assert_gt(later, 0.0, "decay is asymptotic; nothing falls off a cliff at a timeout")
	assert_almost_eq(later, fresh * 0.5, 0.05, "hearing's default is about a 12s half-life")


## Section "Effective Evidence Strength": different senses persist differently, and it
## has to be config that says so rather than a special case in the code.
func test_each_sense_decays_at_its_own_rate() -> void:
	var seen := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION, Vector3(40, 0, 0), 1.0, 1.0, 1.0, 0.0
	)
	var touched := SuspicionEvidence.make(
		SuspicionEvidence.Sense.TOUCH, Vector3(80, 0, 0), 1.0, 1.0, 1.0, 0.0
	)
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 1.0, 1.0, 1.0))
	_suspicion.submit_evidence(seen)
	_suspicion.submit_evidence(touched)
	_advance_coarse(20.0)

	var strengths: Array[float] = []
	for record: SuspicionEvidenceRecord in _suspicion.memory.records:
		strengths.append(record.effective_strength(_suspicion.clock))

	assert_gt(strengths[1], strengths[0], "a sighting outlasts a noise")
	assert_gt(strengths[0], strengths[2], "and contact goes stale fastest of all")


func test_evidence_below_the_retention_floor_is_dropped() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	assert_eq(_suspicion.memory.records.size(), 1)

	_advance_coarse(200.0)

	assert_eq(_suspicion.memory.records.size(), 0, "it stopped changing any answer")
	assert_eq(_suspicion.get_overall_suspicion(), 0.0)


func test_an_observation_too_weak_to_matter_is_never_stored() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.001, 4.0, 0.01))
	assert_eq(_suspicion.memory.records.size(), 0)


## A player drilling continuously produces evidence faster than it decays. An uncapped
## array is a frame spike with nothing in the log.
func test_the_evidence_cap_drops_the_weakest_not_the_oldest() -> void:
	_config.max_evidence_count = 8
	var loud := _hear(Vector3.ZERO, 1.0, 1.0, 1.0)
	_suspicion.submit_evidence(loud)

	for index: int in 40:
		_suspicion.submit_evidence(_hear(Vector3(float(index), 0, 0), 0.12, 4.0, 0.5))

	assert_eq(_suspicion.memory.records.size(), 8)
	var kept_the_loud_one: bool = false
	for record: SuspicionEvidenceRecord in _suspicion.memory.records:
		if record.initial_strength >= 1.0:
			kept_the_loud_one = true
	assert_true(kept_the_loud_one, "dropping the oldest would forget the one thing that mattered")


func test_the_disconfirmation_list_is_capped_too() -> void:
	_config.max_disconfirmation_count = 5
	for index: int in 20:
		_suspicion.submit_disconfirmation(_search(Vector3(float(index) * 3.0, 0, 0), 4.0))
	assert_eq(_suspicion.memory.disconfirmations.size(), 5)


## An aborted scan reaches FINISHED so Behavior's request-then-poll loop does not hang,
## but it never looked. Remembering it would be remembering that somewhere was checked.
func test_a_zero_strength_search_is_not_remembered() -> void:
	_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0, 0.0))
	assert_eq(_suspicion.memory.disconfirmations.size(), 0)


func test_an_observation_with_no_uncertainty_gets_the_configured_default() -> void:
	var exact := SuspicionEvidence.make(
		SuspicionEvidence.Sense.HEARING, Vector3.ZERO, 0.0, 0.9, 0.9, 0.0
	)
	_suspicion.submit_evidence(exact)

	assert_eq(
		_suspicion.memory.records[0].uncertainty_radius,
		_config.default_uncertainty_radius,
		"zero would claim perfect knowledge"
	)


## The kernel is what makes the module spatial. A vague noise must spread its belief
## over a wide area, not deposit a point of certainty at a guessed coordinate.
func test_a_vague_observation_spreads_its_support_further_than_a_precise_one() -> void:
	var vague := SuspicionEvidenceRecord.from_observation(
		1, _hear(Vector3.ZERO, 1.0, 12.0, 1.0), 0.0, _config
	)
	var precise := SuspicionEvidenceRecord.from_observation(
		2, _hear(Vector3.ZERO, 1.0, 1.0, 1.0), 0.0, _config
	)
	var away := Vector3(6, 0, 0)

	assert_almost_eq(
		vague.support_at(Vector3.ZERO, 0.0),
		precise.support_at(Vector3.ZERO, 0.0),
		0.001,
		"uncertainty is about where, not about how much"
	)
	assert_gt(vague.support_at(away, 0.0), precise.support_at(away, 0.0) + 0.3)


func test_ingesting_null_is_a_no_op_rather_than_a_crash() -> void:
	_suspicion.submit_evidence(null)
	_suspicion.submit_disconfirmation(null)
	_settle()
	assert_eq(_suspicion.memory.records.size(), 0)
	assert_eq(_suspicion.get_overall_suspicion(), 0.0)


func test_a_batch_submits_every_item() -> void:
	var batch: Array[SuspicionEvidence] = [
		_hear(Vector3.ZERO), _hear(Vector3(30, 0, 0)), _hear(Vector3(60, 0, 0))
	]
	_suspicion.submit_evidence_batch(batch)
	_settle()

	assert_eq(_suspicion.memory.records.size(), 3)
	assert_eq(_suspicion.get_hotspots().size(), 3, "far apart, so three separate beliefs")
