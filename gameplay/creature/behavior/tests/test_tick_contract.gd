extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## fsm.md's tick contract: one _physics_process, one order, no exceptions.
##
## The order is not a preference. Evidence must land before decay runs and before any query
## reads it; the directive must be fixed for the whole tick; the tree must never run before
## transitions have settled. None of those produce an error when they are wrong -- they
## produce a creature that is a frame behind its own beliefs, which is indistinguishable
## from tuning until somebody spends an afternoon on it.


## Perception, then Suspicion. A noise received this tick has to be belief by the time the
## HFSM looks, or the alien reacts to everything one frame late forever.
func test_a_noise_becomes_belief_within_the_same_tick() -> void:
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	assert_gt(_suspicion.get_overall_suspicion(), 0.0)
	assert_not_null(_suspicion.get_strongest_hotspot())


## THE DOUBLE-ADVANCE TEST. All three facades run their own _physics_process, so leaving
## them on while this one drives them would age every clock twice -- navigation would emit
## motion_planned TWICE PER FRAME with the same body state and the motor would consume both.
func test_driving_the_tick_switches_off_the_subsystems_own_processing() -> void:
	_add_navigation()
	_tick()

	assert_false(_perception.is_physics_processing(), "perception would advance twice per frame")
	assert_false(_suspicion.is_physics_processing(), "suspicion would advance twice per frame")
	assert_false(_navigation.is_physics_processing(), "navigation would advance twice per frame")


func test_one_tick_advances_every_clock_exactly_once() -> void:
	_advance(1.0)

	assert_almost_eq(_behavior.clock, 1.0, 0.02)
	assert_almost_eq(_perception.clock, 1.0, 0.02, "perception ran at the wrong rate")
	assert_almost_eq(_suspicion.clock, 1.0, 0.02, "suspicion ran at the wrong rate")


## Set false and the caller owns the order, which is how the prototype drives it. The
## subsystems must be left alone in that mode.
func test_a_creature_that_does_not_drive_the_tick_leaves_the_subsystems_alone() -> void:
	_behavior.drive_subsystems = false
	_tick()

	assert_almost_eq(_perception.clock, 0.0, 0.001, "it advanced a subsystem it does not own")


## Step 6, and its ordering. Alertness is published from the state the HFSM has just settled
## on, so vision sharpens once the creature is already suspicious -- the one place Behavior
## writes to Perception, and the only legitimate one.
func test_alertness_is_published_from_the_current_state() -> void:
	_tick()
	assert_almost_eq(_perception.get_alertness(), _config.alertness_unalerted, 0.001)

	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	assert_eq(_state(), CreatureState.State.INVESTIGATING)
	assert_almost_eq(_perception.get_alertness(), _config.alertness_investigating, 0.001)


## Below the gate a searching alien is blind and every search clears half as much, because
## the VISION bit drops out of the disconfirmation mask.
func test_an_investigating_creature_can_actually_see() -> void:
	assert_true(
		_perception.config.vision_gate(_config.alertness_investigating),
		"alertness_investigating is below PerceptionConfig.vision_activation_suspicion"
	)
	assert_true(_perception.config.vision_gate(_config.alertness_hunting))
	assert_false(
		_perception.config.vision_gate(_config.alertness_unalerted),
		"a calm alien is meant to be visually dulled"
	)


## One directive per creature per tick. No mid-frame revisions.
func test_the_directive_is_taken_once_per_tick() -> void:
	var counter := _CountingDirector.new(_directive)
	_behavior.director = counter
	_advance(10.0 * TICK)

	assert_eq(counter.calls, 10, "the Director was consulted more than once in a tick")


func test_a_creature_with_no_director_runs_on_the_neutral_directive() -> void:
	_behavior.director = null
	_tick()

	assert_true(_behavior.directive.permit_hunt)
	assert_false(_behavior.directive.force_disengage)


## The report is the Director's only view of navigation, so its two metrics have to mean
## what director.md says they mean.
func test_a_creature_with_no_route_reports_no_proximity_pressure() -> void:
	var report: EncounterReport = _behavior.build_report()

	assert_eq(report.route_distance, EncounterReport.NO_ROUTE_DISTANCE)
	assert_true(report.target_reachable, "nowhere to go is not the same as cannot reach you")


func test_the_report_carries_the_state_and_the_time_in_it() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_advance(0.5)

	var report: EncounterReport = _behavior.build_report()
	assert_eq(report.state, CreatureState.State.INVESTIGATING)
	assert_gt(report.time_in_state, 0.0)


## Derived from Perception's own signal rather than from a line-of-sight query. Behavior may
## observe what Perception emits; it may not reach past it into the world.
func test_visual_contact_follows_a_sighting_and_then_lapses() -> void:
	var player: Node3D = _player("p1")
	_see(player, Vector3(0.0, 0.0, 4.0))
	_tick()
	assert_true(_behavior.build_report().has_visual_contact)

	_advance(_config.visual_contact_grace_s + 0.5)
	assert_false(_behavior.build_report().has_visual_contact, "contact never lapsed")


func test_a_heard_noise_is_not_visual_contact() -> void:
	_hear(Vector3(0.0, 0.0, 6.0))
	_advance(0.2)

	assert_false(_behavior.build_report().has_visual_contact)


## The grace has to outlast a vision interval or contact flickers off between ticks and the
## Director's sight term stutters on a creature staring straight at you.
func test_the_contact_grace_outlasts_a_vision_interval() -> void:
	assert_gt(_config.visual_contact_grace_s, _perception.config.vision_scan_interval_calm)


## Injected delta, never a wall clock. Time.get_ticks_msec() ignores get_tree().paused and
## Engine.time_scale, so belief would decay in a paused game and no test could drive it.
func test_the_clock_is_the_delta_it_is_handed() -> void:
	_behavior.advance(5.0)
	assert_almost_eq(_behavior.clock, 5.0, 0.001)

	_behavior.advance(0.0)
	assert_almost_eq(_behavior.clock, 5.0, 0.001, "time passed without a delta")


func test_the_debug_dictionary_answers_why_it_is_doing_that() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	var shown: Dictionary = _behavior.debug_state()
	assert_eq(shown["state"], "investigating")
	assert_has(shown, "directive")
	assert_has(shown, "report")


class _CountingDirector:
	extends Node

	var directive: EncounterDirective = null
	var calls: int = 0

	func _init(p_directive: EncounterDirective) -> void:
		directive = p_directive

	func exchange(_creature: Node, _report: EncounterReport) -> EncounterDirective:
		calls += 1
		return directive
