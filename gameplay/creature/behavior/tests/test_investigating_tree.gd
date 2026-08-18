extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## The INVESTIGATING tree, and the four traps the prototype paid for once already.
##
## ```text
## Selector
## |-- Sequence[arrived_at_goal, cooldown(search_area)]
## +-- investigate_location
## ```
##
## THE LOOP THIS SUITE EXISTS TO CATCH is the alien that arrives, searches, and then searches
## the same spot until the timeout. It happens whenever `arrived_at_goal` asks only whether
## navigation has finished: after a search the body has not moved, so it is still finished,
## and the search branch wins again while the best unresolved location quietly walks off
## without it. The hotspot never resolves and it reads as a bug in disconfirmation.


func test_an_investigation_walks_to_the_unresolved_location() -> void:
	_add_navigation()
	_reach_investigating()

	assert_eq(_behavior.running_action(), &"investigate_location")
	assert_true(_behavior.goal.has_goal(), "there is nowhere to walk")


func test_arriving_starts_a_search() -> void:
	_add_navigation()
	_reach_investigating()
	_walk_to(_desired(), 0.5)

	assert_eq(_behavior.running_action(), &"search_area")
	assert_true(_perception.is_activity_scan_active())


## TRAP 3. A degenerate AABB aborts the scan, and an aborted scan reports a ZERO-STRENGTH
## disconfirmation that suppresses nothing -- so the alien searches and the hotspot never
## clears. The region must enclose a real volume however small the config is set.
func test_the_search_region_always_encloses_a_real_volume() -> void:
	_config.search_half_extent = 0.5
	var region: AABB = BtSearchArea._region(Vector3(3.0, 0.0, 4.0), _config)
	assert_gt(region.get_volume(), 0.0)
	assert_true(region.has_point(Vector3(3.0, 0.0, 4.0)), "the region must contain what it checks")


## A search that could not run is "never looked", not "checked and empty". Succeeding on an
## aborted scan would let the state believe an area was cleared by a scan that never ran.
func test_a_search_that_could_not_run_reports_failure_rather_than_success() -> void:
	_add_navigation()
	_reach_investigating()
	_perception.probe.bound = false
	_walk_to(_desired(), 0.5)

	assert_false(_perception.is_activity_scan_active())
	assert_true(_perception.activity_scan_aborted(), "the fixture did not reproduce an abort")
	assert_eq(_suspicion.memory.disconfirmations.size(), 0, "an aborted scan cleared something")


## The scan can finish INSIDE the request call, so a node that polled the active flag blind
## would re-request every frame -- and each request writes a zero-strength disconfirmation
## into a ring capped at 48, evicting real search records with junk.
func test_an_abortable_search_does_not_re_request_every_frame() -> void:
	_add_navigation()
	_reach_investigating()
	_perception.probe.bound = false
	_walk_to(_desired(), 0.5)
	_advance(1.0)

	assert_lt(
		_suspicion.memory.disconfirmations.size(),
		4,
		"the search is storming; the cooldown is not holding it"
	)


## THE ASSERTION THIS FILE EXISTS FOR. After a completed search the desired location moves,
## and the tree has to notice and re-commit rather than searching the same point again.
func test_the_creature_re_aims_after_a_search_instead_of_repeating_it() -> void:
	_add_navigation()
	_reach_investigating()
	_walk_to(_desired(), 0.5)
	var searched: Vector3 = _behavior.goal.committed()

	# Long enough for the scan to finish and the disconfirmation to land.
	_advance(_perception.config.search_scan_duration_max + 2.0)

	assert_gt(_suspicion.memory.disconfirmations.size(), 0, "the search never reported anything")
	assert_lt(
		_suspicion.get_suspicion_near(searched, 3.0),
		_suspicion.get_overall_suspicion() + 0.001,
		"searching should have suppressed belief where the creature actually looked"
	)


## TRAP 1. `get_best_unresolved_location` returns Vector3.ZERO for an id that is no longer
## live -- not the hotspot centre, whatever its docstring says. Unguarded, an alien whose
## hotspot resolves mid-approach sets off for the world origin.
func test_a_dead_hotspot_never_sends_the_creature_to_the_world_origin() -> void:
	_add_navigation()
	_reach_investigating()
	var state: InvestigatingState = _investigating()
	state.memory.hotspot_id = 999_999
	state.refresh(_behavior.context)

	if state.memory.has_location:
		assert_ne(state.memory.desired_location, Vector3.ZERO, "that is the dead-id sentinel")


## behavior.md section 25's first branch: current hotspot resolved -> select another. A lead
## dying mid-approach should not drop the alien straight back to calm while a louder one is
## still on the board.
func test_a_lead_dying_mid_approach_is_replaced_rather_than_abandoned() -> void:
	_add_navigation()
	_reach_investigating()
	var state: InvestigatingState = _investigating()

	_hear(Vector3(0.0, 0.0, -8.0))
	_tick()
	state.on_hotspot_resolved(state.memory.hotspot_id)
	_tick()

	assert_eq(_state(), CreatureState.State.INVESTIGATING, "there was another lead to follow")
	assert_true(state.memory.has_location)


## TRAP 4. A PARTIAL route still finishes, at the far end of what was reachable. The alien
## searches the mouth of a shaft it cannot enter and correctly fails to resolve a hotspot on
## the other side; the timeout is what stops it standing there.
func test_a_hotspot_the_creature_cannot_reach_ends_on_the_timeout() -> void:
	_config.investigate_timeout_s = 2.0
	_add_navigation()
	_reach_investigating()

	for _i: int in 400:
		_hear(Vector3(0.0, 0.0, 6.0))
		_tick()

	assert_has(_reasons(), &"timeout", "an unreachable lead must not strand the creature")


## TRAP 2 / the deadband. Re-issuing every frame nulls navigation's route and resets its
## stuck watchdog, which disables the only backstop against a wedged alien.
func test_the_goal_is_not_re_issued_for_tiny_moves() -> void:
	_add_navigation()
	_reach_investigating()
	var first: Vector3 = _behavior.goal.committed()

	_investigating().memory.desired_location = first + Vector3(0.5, 0.0, 0.0)
	_tick()

	assert_eq(_behavior.goal.committed(), first, "a half-metre drift re-planned the whole route")


func test_leaving_the_state_gives_the_investigate_goal_back() -> void:
	_add_navigation()
	_reach_investigating()
	assert_true(_behavior.goal.has_goal())

	_behavior.hfsm.reset_to(CreatureState.State.UNALERTED, _behavior.context)

	assert_false(_behavior.goal.has_goal(), "the investigate goal leaked into the next state")


## An action that reached into Suspicion and lowered a number would work visibly better and
## destroy the design. Belief has three doors and Behavior is not one of them.
func test_searching_never_writes_belief_directly() -> void:
	_add_navigation()
	_reach_investigating()
	var before: int = _suspicion.memory.disconfirmations.size()
	_walk_to(_desired(), 0.5)
	_tick()

	assert_eq(
		_suspicion.memory.disconfirmations.size(),
		before,
		"the action wrote a disconfirmation itself instead of letting Perception observe one"
	)


# ----- helpers -----


func _reach_investigating() -> void:
	_place(Vector3.ZERO)
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 8.0))
	_tick()
	assert_eq(
		_state(), CreatureState.State.INVESTIGATING, "the fixture never started investigating"
	)


func _investigating() -> InvestigatingState:
	return _behavior.hfsm.state_of(CreatureState.State.INVESTIGATING) as InvestigatingState


func _desired() -> Vector3:
	return _investigating().memory.desired_location
