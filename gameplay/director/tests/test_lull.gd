extends "res://gameplay/director/tests/director_test_case.gd"

## Lull -- the throttle (director.md, "Two accumulators").
##
## The last test in this file is the most important one in the module.


func test_dead_air_accumulates_at_the_configured_rate() -> void:
	_advance(60.0)
	assert_almost_eq(_director.lull, 60.0 / _config.lull_full_s, 0.005, "linear in lull_full_s")


func test_two_quiet_minutes_give_the_spec_its_point_six() -> void:
	# director.md's worked encounter opens "lull .6 after two quiet minutes". lull_full_s is
	# derived from exactly this line, so if it moves the trace stops reproducing.
	_advance(120.0)
	assert_almost_eq(_director.lull, 0.6, 0.01, "the number the whole config is calibrated to")


func test_a_bored_director_publishes_the_biases_the_trace_states() -> void:
	_advance(120.0)
	assert_almost_eq(_directive().roam_bias, 0.6, 0.01, "roam +.6 at lull .6")
	assert_almost_eq(_directive().escalation_bias, 0.3, 0.01, "and bias +.3, the same 1:2")


func test_a_player_being_stalked_is_not_experiencing_dead_air() -> void:
	# Suspicion above the calm threshold stops the clock with no state change at all: the
	# creature is still UNALERTED and the phase is still QUIET, and the lull still does not
	# rise, because somebody is being crept up on.
	_advance(20.0)
	var held: float = _director.lull
	var player: Node3D = _player("Player1")
	for _i: int in 100:
		_see(player, Vector3(4.0, 0.0, 0.0))
		_advance(0.2)
	assert_gt(
		_suspicion.get_overall_suspicion(),
		_config.calm_suspicion_threshold,
		"the fixture actually raised belief"
	)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "and nothing transitioned")
	assert_almost_eq(_director.lull, held, 0.005, "yet the throttle closed")


func test_the_lull_is_capped_at_one() -> void:
	_advance(_config.lull_full_s * 2.0)
	assert_eq(_director.lull, 1.0)


func test_a_sated_exit_resets_the_lull_fully() -> void:
	_advance(120.0)
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 1.0)
	assert_eq(_track().disengage_reason, EncounterDirective.Reason.NONE, "the encounter ended")
	# The tolerance is the second or so of fresh quiet between the reset and this assert. Both
	# exits are checked the same way, so what the pair actually proves is the DIFFERENCE:
	# nothing back after an earned exit, stalled_lull_retention back after an unearned one.
	assert_almost_eq(
		_director.lull, 0.0, 0.02, "the player got the whole beat and earned the quiet"
	)


func test_a_stalled_exit_only_gives_part_of_it_back() -> void:
	# "lull resets only partially, so the Director rebuilds sooner." A stalemate earned
	# nothing, and giving it the same reset would reward hiding with silence.
	_advance(120.0)
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(_config.hunt_max_duration_s + 1.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 1.0)
	assert_almost_eq(_director.lull, _config.stalled_lull_retention, 0.02, "re-seeded, not reset")


func test_the_lull_never_fabricates_evidence() -> void:
	# THE HIGHEST-VALUE TEST IN THIS MODULE, and the one design invariant that would be
	# tempting to break. director.md: "There is deliberately no lever for injecting a false
	# noise into Suspicion to bait a player, because it would make noise discipline
	# meaningless -- you could no longer trust that an approaching alien means you made a
	# mistake. That trust is the mechanic."
	#
	# So: five minutes of maximal boredom, and belief must be untouched.
	var before: Dictionary = _suspicion.debug_state()
	before.erase("clock")
	_advance(300.0)
	assert_eq(_director.lull, 1.0, "the Director is as bored as it can possibly get")
	assert_eq(_suspicion.get_overall_suspicion(), 0.0, "and has invented nothing")
	assert_eq(_suspicion.get_hotspots().size(), 0, "no hotspot appeared out of impatience")
	assert_null(_suspicion.get_best_player_candidate(), "and nobody became a suspect")
	# Everything but the clock, which is Suspicion's own and is time passing rather than
	# belief changing -- the third of the three doors, and not one the Director went through.
	var after: Dictionary = _suspicion.debug_state()
	after.erase("clock")
	assert_eq(after, before, "belief is bit-for-bit what it was")


func test_boredom_raises_willingness_and_proximity_and_nothing_else() -> void:
	# The throttle's entire reach: two numbers on the directive. Everything else it publishes
	# must be exactly what an unbored Director would publish.
	_advance(_config.lull_full_s)
	var directive: EncounterDirective = _directive()
	assert_gt(directive.escalation_bias, 0.0, "more willing")
	assert_gt(directive.roam_bias, 0.0, "and drifting closer")
	assert_true(directive.permit_hunt, "but no permission it did not already have")
	assert_false(directive.force_disengage, "nothing forced")
	assert_null(directive.target, "and it has not named anybody")
	assert_eq(directive.menace, 0.0, "no pressure was invented either")


func test_with_nobody_in_the_party_the_drift_has_nowhere_to_point() -> void:
	# DirectorParty.anchor() answers Vector3.ZERO with an empty party, and the world origin is
	# a real place -- a nest near it would collect a roam bonus for no reason at all. Zeroing
	# the weight makes the anchor irrelevant rather than merely harmless. Willingness is
	# unaffected: being bored is still a reason to act on weaker evidence.
	_director.players = []
	_advance(_config.lull_full_s)
	assert_eq(_directive().roam_bias, 0.0, "no party, no drift")
	assert_gt(_directive().escalation_bias, 0.0, "but still bored")
