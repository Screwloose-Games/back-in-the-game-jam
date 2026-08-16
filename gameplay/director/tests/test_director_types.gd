extends GutTest

## EncounterDirective and EncounterReport: the defaults, and why they are those defaults.
##
## There is no behaviour here to test -- both are value types. What IS worth asserting is
## every default that would quietly change how the creature or the Director behaves if
## someone "tidied" it, because none of them announces itself. A neutral directive that
## forbade hunting, or a report claiming zero route distance from an alien with no route,
## both produce a game that runs and is wrong.


func test_a_bare_directive_is_the_neutral_one() -> void:
	var bare := EncounterDirective.new()
	var neutral: EncounterDirective = EncounterDirective.neutral()
	assert_eq(bare.phase, neutral.phase)
	assert_eq(bare.permit_hunt, neutral.permit_hunt)
	assert_eq(bare.escalation_bias, neutral.escalation_bias)
	assert_eq(bare.lethality, neutral.lethality)


## A directive that withheld permission by default would be a silent difficulty setting:
## the alien never hunts, and the search starts in the HFSM rather than here.
func test_neutral_permits_hunting() -> void:
	assert_true(EncounterDirective.neutral().permit_hunt)


## Mercy is a pacing judgement and needs session history. A creature with no Director has
## none, so it does not get to be merciful by accident.
func test_neutral_is_lethal_rather_than_graceful() -> void:
	assert_eq(EncounterDirective.neutral().lethality, EncounterDirective.Lethality.LETHAL)


func test_neutral_applies_no_pressure_and_no_bias() -> void:
	var directive: EncounterDirective = EncounterDirective.neutral()
	assert_eq(directive.menace, 0.0)
	assert_eq(directive.lull, 0.0)
	assert_eq(directive.escalation_bias, 0.0)
	assert_eq(directive.roam_bias, 0.0)
	assert_eq(directive.phase, EncounterDirective.Phase.QUIET)


func test_neutral_forces_nothing_and_names_nobody() -> void:
	var directive: EncounterDirective = EncounterDirective.neutral()
	assert_false(directive.force_disengage)
	assert_eq(directive.disengage_reason, EncounterDirective.Reason.NONE)
	assert_null(directive.target)


## Every override must be attributable -- "the alien left" is not a bug report.
func test_every_enum_value_has_a_debug_name() -> void:
	for phase: int in [
		EncounterDirective.Phase.QUIET,
		EncounterDirective.Phase.BUILD,
		EncounterDirective.Phase.PEAK,
		EncounterDirective.Phase.RELIEF,
	]:
		assert_ne(EncounterDirective.phase_name(phase), "?", "phase %d has no name" % phase)
	for reason: int in [
		EncounterDirective.Reason.NONE,
		EncounterDirective.Reason.SATED,
		EncounterDirective.Reason.STALLED,
	]:
		assert_ne(EncounterDirective.reason_name(reason), "?", "reason %d has no name" % reason)


func test_the_directive_debug_dictionary_carries_what_is_constraining_the_creature() -> void:
	var directive: EncounterDirective = EncounterDirective.neutral()
	directive.force_disengage = true
	directive.disengage_reason = EncounterDirective.Reason.SATED
	var shown: Dictionary = directive.to_dictionary()
	assert_true(shown["force_disengage"])
	assert_eq(shown["disengage_reason"], "sated")


## THE ASSERTION THIS FILE EXISTS FOR. RouteFollower.distance_remaining returns 0.0 when
## there is no route, and the Director's proximity term is
## w_proximity * (1 - clamp(route_distance / menace_range)). Pass the raw value through and
## an alien idling at a nest reports maximum dread, forever, with nothing in the log.
func test_a_report_with_no_route_claims_no_proximity_pressure() -> void:
	var report := EncounterReport.new()
	assert_eq(report.route_distance, EncounterReport.NO_ROUTE_DISTANCE)
	assert_true(report.route_distance > 0.0, "the sentinel must read as FAR, not as near")


## "Nowhere to go" is not "cannot reach you". CreatureNavigation.route is null before the
## first replan and after every clear_goal, so a false default fires the Director's stall
## penalty against a creature behaving perfectly.
func test_a_report_with_no_route_does_not_claim_the_target_is_unreachable() -> void:
	assert_true(EncounterReport.new().target_reachable)


func test_a_bare_report_claims_no_contact_of_any_kind() -> void:
	var report := EncounterReport.new()
	assert_false(report.has_visual_contact)
	assert_false(report.attack_window_open)
	assert_false(report.lurking_at_crevice)
	assert_eq(report.state, CreatureState.State.UNALERTED)


func test_the_report_debug_dictionary_names_the_state_rather_than_numbering_it() -> void:
	var report := EncounterReport.new()
	report.state = CreatureState.State.HUNTING
	assert_eq(report.to_dictionary()["state"], "hunting")


func test_every_creature_state_has_a_debug_name() -> void:
	for state: int in [
		CreatureState.State.UNALERTED,
		CreatureState.State.INVESTIGATING,
		CreatureState.State.HUNTING,
		CreatureState.State.RETREATING,
	]:
		assert_ne(CreatureState.state_name(state), "?", "state %d has no name" % state)


## director.md: the Director publishes a directive and Behavior honours it. A directive that
## could call into the creature would be the Director transitioning the HFSM itself.
func test_a_directive_can_command_nothing() -> void:
	var directive: EncounterDirective = EncounterDirective.neutral()
	for banned: String in [
		"apply", "apply_to", "force_state", "set_state", "transition", "exchange"
	]:
		assert_false(
			directive.has_method(banned),
			"%s would let the Director transition the HFSM directly" % banned
		)
