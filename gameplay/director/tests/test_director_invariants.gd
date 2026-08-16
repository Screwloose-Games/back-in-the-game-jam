extends "res://gameplay/director/tests/director_test_case.gd"

## director.md's "Design invariants", as assertions rather than as prose.
##
## THESE ARE THE TESTS THAT WOULD CATCH A HELPFUL CHANGE. Every one of them guards something
## a future edit could break while making the alien visibly better at its job -- handing it a
## position, damping the belief that will not go away, ending a hunt a frame sooner. The
## module is only worth what these hold.


func test_the_director_has_no_way_to_write_belief() -> void:
	# "Suspicion has three doors -- evidence, disconfirmation, the clock -- and the Director
	# is not one of them."
	for forbidden: StringName in [
		&"submit_evidence", &"submit_disconfirmation", &"reduce_suspicion", &"clear_hotspot"
	]:
		assert_false(_director.has_method(forbidden), "EncounterDirector.%s" % forbidden)


func test_the_director_has_no_way_to_issue_a_destination() -> void:
	for forbidden: StringName in [&"set_goal", &"clear_goal", &"plan_route", &"navigate_to"]:
		assert_false(_director.has_method(forbidden), "EncounterDirector.%s" % forbidden)


func test_the_director_has_no_way_to_transition_the_hfsm() -> void:
	for forbidden: StringName in [
		&"reset_to", &"evaluate_transitions", &"set_state", &"force_state"
	]:
		assert_false(_director.has_method(forbidden), "EncounterDirector.%s" % forbidden)


func test_the_director_has_no_way_to_adjust_perception() -> void:
	# "Not 'should not' -- the interface does not exist. Difficulty lives in
	# perception_config.gd. Pacing lives here."
	for forbidden: StringName in [&"set_alertness_context", &"receive_noise", &"set_hearing_range"]:
		assert_false(_director.has_method(forbidden), "EncounterDirector.%s" % forbidden)


func test_a_whole_encounter_leaves_belief_exactly_as_it_found_it() -> void:
	# THE STRONGEST FORM OF "the Director never damps suspicion". After a forced disengagement
	# the creature still fully believes you are there -- the cooldown works by shifting
	# Behavior's thresholds, not by editing belief. An alien that lost interest reads as a
	# predator making a choice; one that lost its memory reads as a bug.
	var player: Node3D = _player("Player1")
	for _i: int in 40:
		_see(player, Vector3(4.0, 0.0, 0.0))
		_advance(0.1)
	var believed: float = _suspicion.get_overall_suspicion()
	var hotspots: int = _suspicion.get_hotspots().size()
	assert_gt(believed, 0.0, "the creature genuinely believes something")

	_hunt(0.0, true, true)
	_advance(22.0)
	assert_true(_directive().force_disengage, "and the Director has just ended the encounter")
	assert_almost_eq(
		_suspicion.get_overall_suspicion(), believed, 0.05, "belief was not touched to do it"
	)
	assert_eq(_suspicion.get_hotspots().size(), hotspots, "and no lead was cleared")


func test_exactly_one_directive_is_in_effect_per_creature_per_tick() -> void:
	var first: EncounterDirective = _director.exchange(_creature, _report)
	var second: EncounterDirective = _director.exchange(_creature, _report)
	assert_eq(first, second, "the same object, so there is nothing to revise mid-frame")


func test_a_second_exchange_in_one_tick_cannot_change_what_the_creature_reads() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	var directive: EncounterDirective = _director.exchange(_creature, _report)
	var forced: bool = directive.force_disengage
	var phase: EncounterDirective.Phase = directive.phase
	_director.exchange(_creature, _report)
	assert_eq(directive.force_disengage, forced, "no mid-frame revision")
	assert_eq(directive.phase, phase, "of anything")


func test_the_report_handed_up_is_never_written_to() -> void:
	_hunt(6.0, true, true, true, false)
	var before: Dictionary = _report.to_dictionary()
	_advance(5.0)
	assert_eq(_report.to_dictionary(), before, "one struct up, and it goes up read-only")


func test_every_phase_change_is_attributable() -> void:
	# "Every override carries a named reason, visible in debug and in the signal."
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_gt(_phases.size(), 0, "the phase moved")
	assert_eq(_disengages.size(), 1, "and the one override it produced was announced")
	assert_ne(_disengages[0], EncounterDirective.Reason.NONE, "with a reason, never anonymously")


func test_nothing_is_ever_forced_without_a_reason() -> void:
	_hunt(0.0, true, true)
	for _i: int in 3000:
		_tick()
		if _directive().force_disengage:
			assert_ne(
				_directive().disengage_reason,
				EncounterDirective.Reason.NONE,
				"a forced disengage always says which kind it is"
			)


func test_both_meters_and_both_biases_stay_in_range_under_abuse() -> void:
	# Every combination of report flags, in sequence, for long enough that any unclamped
	# accumulator would run away.
	var states: Array = [
		CreatureState.State.UNALERTED,
		CreatureState.State.INVESTIGATING,
		CreatureState.State.HUNTING,
		CreatureState.State.RETREATING,
	]
	for round: int in 240:
		_report = _make_report(states[round % 4])
		_report.route_distance = 0.0 if round % 3 == 0 else EncounterReport.NO_ROUTE_DISTANCE
		_report.has_visual_contact = round % 2 == 0
		_report.attack_window_open = round % 5 == 0
		_report.lurking_at_tunnel_mouth = round % 7 == 0
		_report.target_reachable = round % 11 != 0
		_report.position = Vector3(float(round % 50), 0.0, 0.0)
		_file()
		_advance(0.5)
		assert_between(_track().menace, 0.0, 1.0, "menace")
		assert_between(_director.lull, 0.0, 1.0, "lull")
		assert_between(_directive().escalation_bias, -1.0, 1.0, "escalation_bias")
		assert_between(_directive().roam_bias, -1.0, 1.0, "roam_bias")


func test_a_creature_with_no_director_is_indistinguishable_on_the_first_frame() -> void:
	# gameplay/director/README.md's promise: "With EncounterDirective.neutral() the creature
	# runs correctly and unpaced, and the day the Director lands nothing in Behavior changes."
	# A track that has never been advanced must publish exactly that.
	var fresh: Node = autofree(Node.new())
	var directive: EncounterDirective = _director.exchange(fresh, EncounterReport.new())
	var neutral := EncounterDirective.neutral()
	assert_eq(directive.to_dictionary(), neutral.to_dictionary(), "neutral on frame one")
