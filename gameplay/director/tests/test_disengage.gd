extends "res://gameplay/director/tests/director_test_case.gd"

## Two ways to end a hunt (director.md, "Two ways to end a hunt").
##
## The exit matters as much as the timing: without the split a stalemate ends with the same
## triumphant beat as a real chase, and the game congratulates a player who did nothing.


func test_a_hunt_that_delivered_ends_sated() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_eq(_disengages, [EncounterDirective.Reason.SATED], "the earned exit")
	assert_eq(_track().menace, 1.0, "and it was earned by filling the meter")


func test_a_hunt_that_delivered_nothing_ends_stalled() -> void:
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(_config.hunt_max_duration_s - 1.0)
	assert_eq(_disengages, [], "not before the cap")
	_advance(2.0)
	assert_eq(_disengages, [EncounterDirective.Reason.STALLED], "the unearned exit")
	assert_lt(_track().menace, _config.peak_threshold, "with the meter still short")


func test_a_creature_the_player_hid_from_cannot_leave_triumphantly() -> void:
	# The rule w_time exists to enforce, end to end rather than as arithmetic: hunted for the
	# whole permitted duration with nothing delivered, and the exit is still STALLED.
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(_config.hunt_max_duration_s + 1.0)
	assert_does_not_have(_disengages, EncounterDirective.Reason.SATED, "never earned")


func test_the_directive_carries_the_force_and_the_reason_together() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_true(_directive().force_disengage, "the latch is set")
	assert_eq(_directive().disengage_reason, EncounterDirective.Reason.SATED, "with its reason")
	assert_false(_directive().permit_hunt, "and no permission to start again")


func test_the_latch_is_held_for_the_whole_of_relief_rather_than_one_frame() -> void:
	# CreatureHfsm latches force_disengage on OBSERVATION because min_dwell_s routinely
	# delays the transition check by whole seconds. A producer that dropped the flag after a
	# tick would be betting the encounter on that latch having been seen -- and this is the
	# producer's half of the same bug.
	_hunt(0.0, true, true)
	_advance(22.0)
	for _i: int in 10:
		_advance(1.0)
		assert_true(_directive().force_disengage, "still asking, every tick of the cooldown")


func test_the_reason_survives_until_the_encounter_actually_ends() -> void:
	# RetreatingState reads directive.disengage_reason ONCE on entry to choose the loud or the
	# quiet exit, and min_dwell_s means that entry can be seconds after the order.
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.RETREATING, Vector3(5.0, 0.0, 0.0))
	_advance(5.0)
	assert_eq(
		_directive().disengage_reason,
		EncounterDirective.Reason.SATED,
		"still SATED when Behavior gets round to reading it"
	)


func test_permission_comes_back_only_once_the_cycle_has_turned_over() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_false(_directive().permit_hunt)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 1.0)
	assert_true(_directive().permit_hunt, "QUIET again, and the alien may hunt")
	assert_false(_directive().force_disengage, "with nothing left forced")


func test_relief_publishes_the_negative_biases_the_trace_states() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_almost_eq(_directive().roam_bias, -0.8, 0.01, "roam -.8, clearing the alien out")
	assert_almost_eq(_directive().escalation_bias, -0.4, 0.01, "and bias -.4, the same 1:2")


func test_only_one_disengage_is_ordered_per_encounter() -> void:
	_hunt(0.0, true, true)
	_advance(40.0)
	assert_eq(_disengages.size(), 1, "the order is given once, not once per tick")


func test_a_second_encounter_can_end_differently_from_the_first() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 2.0)

	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(_config.hunt_max_duration_s + 1.0)
	assert_eq(
		_disengages,
		[EncounterDirective.Reason.SATED, EncounterDirective.Reason.STALLED],
		"one earned, then one not"
	)
