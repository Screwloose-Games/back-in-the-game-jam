extends "res://gameplay/director/tests/director_test_case.gd"

## The pacing cycle (director.md, "The pacing cycle").
##
## The phase is a VALUE COMPUTED FROM THE ACCUMULATORS, not a second state machine, and these
## assert that rather than asserting a transition table. Every edge, including the fourth one
## the spec's diagram does not draw.


func test_a_creature_doing_nothing_is_quiet() -> void:
	_advance(5.0)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET)


func test_an_investigation_carries_the_edge_into_build_with_the_meter_still_empty() -> void:
	# Menace integrates only while HUNTING, so t+12 of the worked encounter is an
	# INVESTIGATING edge with zero menace. Without the state clause in derive_phase the lull
	# would go on rising through the whole investigation.
	_state(CreatureState.State.INVESTIGATING)
	_tick()
	assert_eq(_phase(), EncounterDirective.Phase.BUILD)
	assert_eq(_track().menace, 0.0, "and it got there on nothing but the creature's own state")


func test_entering_build_zeroes_the_lull() -> void:
	_advance(60.0)
	assert_gt(_director.lull, 0.0, "quiet time accumulated first")
	_state(CreatureState.State.INVESTIGATING)
	_tick()
	assert_eq(_director.lull, 0.0, "zeroed on entering BUILD")


func test_peak_is_reached_exactly_at_the_threshold() -> void:
	_hunt(0.0, true, true)
	_advance(19.0)
	assert_eq(_phase(), EncounterDirective.Phase.BUILD, "still building under the threshold")
	_advance(2.0)
	assert_true(
		_phase() == EncounterDirective.Phase.PEAK or _phase() == EncounterDirective.Phase.RELIEF,
		"and PEAK, or the RELIEF it immediately becomes, once the meter is full"
	)


func test_the_whole_cycle_reads_as_the_spec_diagram() -> void:
	# quiet -> build -> peak -> relief -> quiet. PEAK LASTS EXACTLY ONE TICK, and that is
	# deliberate: a phase log containing PEAK is the log saying the exit was earned, so
	# swallowing it would make the two exits indistinguishable in the one place anybody looks.
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(25.0)
	assert_eq(_phase_names(), ["build", "peak", "relief", "quiet"], "the diagram, in order")


func test_a_stalled_hunt_never_passes_through_peak() -> void:
	# THE ENTIRE CONTENT OF THE SATED / STALLED SPLIT. A stalemate fires precisely because
	# menace failed to reach the threshold, so PEAK is unreachable on that path -- and the
	# phase log is what tells a designer which of the two happened.
	_hunt(EncounterReport.NO_ROUTE_DISTANCE, false)
	_advance(_config.hunt_max_duration_s + 1.0)
	assert_eq(_disengages, [EncounterDirective.Reason.STALLED], "the unearned exit")
	assert_does_not_have(_phase_names(), "peak", "and it never claimed to be earned")


func test_relief_outranks_everything_so_a_hunt_cannot_restart_inside_a_cooldown() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF)

	# The creature goes on hunting as loudly as it likes. The Director is unmoved.
	_hunt(0.0, true, true)
	_advance(5.0)
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF, "still in the cooldown")
	assert_false(_directive().permit_hunt, "and still refusing permission")


func test_the_director_can_be_in_relief_while_the_alien_is_still_hunting() -> void:
	# director.md: "The alien can be HUNTING while the Director is in RELIEF and wants it to
	# stop; that disagreement is the entire point of having a Director."
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_eq(_report.state, CreatureState.State.HUNTING, "Behavior has not acted on it yet")
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF, "and the Director already wants out")


func test_relief_needs_both_the_timer_and_the_separation() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)

	# Standing exactly where it gave up. The timer runs out; the distance never does.
	_state(CreatureState.State.RETREATING, Vector3.ZERO)
	_advance(_config.cooldown_s + 5.0)
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF, "timer spent, but it never left")

	_state(CreatureState.State.RETREATING, Vector3(_config.cooldown_separation_m + 1.0, 0.0, 0.0))
	_tick()
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "both clauses, and only then")


func test_reaching_unalerted_satisfies_the_separation_clause_outright() -> void:
	# RETREATING -> UNALERTED is Behavior's alone, gated on its own retreat_separation_m with
	# retreat_max_s as a backstop. A creature that got there has already passed a separation
	# test, and it is also what stops RELIEF hanging forever on an alien whose only nests sit
	# inside the Director's radius.
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3.ZERO)
	_advance(_config.cooldown_s + 1.0)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "without moving a metre")


func test_an_encounter_the_director_never_forced_still_ends() -> void:
	# THE FOURTH EDGE, which the spec's diagram does not draw. Behavior lost the hunt on its
	# own -- `hunt sustain lost` -- so no disengage was ever ordered and disengage_reason
	# stays NONE. The encounter ends when the pressure it built has drained away.
	_hunt(0.0, true)
	_advance(10.0)
	assert_eq(_phase(), EncounterDirective.Phase.BUILD)

	_state(CreatureState.State.RETREATING, Vector3(40.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_phase(), EncounterDirective.Phase.BUILD, "the pressure is still on the board")
	assert_eq(_disengages, [], "and nothing was forced")

	_advance(_track().menace / _config.menace_relief_rate + 1.0)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "menace drained, so the encounter is over")
	assert_eq(
		_track().disengage_reason, EncounterDirective.Reason.NONE, "Behavior's own reason carries"
	)


func test_a_retreat_never_reads_as_building() -> void:
	# behavior.md section 30 defines RETREATING as ENDING the encounter legibly. Counting it
	# as engagement would hold the phase open on a creature that is definitionally finished,
	# and after a forced disengage it produced a `relief -> build -> quiet` log that lied
	# about the one thing the log exists to say.
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.RETREATING, Vector3(60.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 10.0)
	var names: Array = _phase_names()
	assert_eq(names.slice(names.find("peak")), ["peak", "relief", "quiet"], "it finishes")


func test_the_phase_is_derived_rather_than_stored() -> void:
	# Mutating only the accumulators and re-deriving gives the same answer, which is what
	# "not a second hand-written state machine" has to mean in practice.
	var track: EncounterTrack = _track()
	track.menace = _config.peak_threshold
	var derived: EncounterDirective.Phase = EncounterPacing.derive_phase(track, _report, _config)
	assert_eq(derived, EncounterDirective.Phase.PEAK, "the meter alone decided it")
	assert_false(_director.has_method(&"set_phase"), "and nothing can be told a phase")
