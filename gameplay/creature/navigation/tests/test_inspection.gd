extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 9: section 29's chain, and section 30's contract with behaviour.
##
## THE ORDERING ASSERTION IS THE POINT OF THIS FILE. Section 41 phase 9 calls for "delayed
## knowledge acquisition", and the entire implementation of that is WHERE in the chain
## `learn_connected_region` is called: at the end of RELEARNING and nowhere earlier. An
## inspection that applied knowledge on entry would pass every other test here, would
## produce a perfectly sensible state machine, and would be omniscience with four extra
## frames of animation in front of it.

const TICK: float = 1.0 / 60.0


func _inspector() -> NavInspector:
	return NavInspector.new()


func _request(at: Vector3) -> NavInspectionRequest:
	return NavInspectionRequest.make(
		at, NavInspectionRequest.Reason.GEOMETRY_MISMATCH, _config.chunk_size
	)


## Ticks until `state` is reached, or gives up. Bounded so a bug cannot hang the suite.
func _run_to(inspector: NavInspector, state: NavInspector.State) -> bool:
	for _step: int in 2000:
		if inspector.state() == state:
			return true
		inspector.advance(TICK, _config)
	return inspector.state() == state


# ----- section 29's chain -----


func test_the_chain_runs_in_the_order_section_29_gives() -> void:
	var inspector: NavInspector = _inspector()
	assert_eq(inspector.state(), NavInspector.State.MOVING)
	assert_true(inspector.report(_request(Vector3.ZERO), 0.0, _config))
	assert_eq(inspector.state(), NavInspector.State.GEOMETRY_MISMATCH)

	assert_true(_run_to(inspector, NavInspector.State.INSPECTING), "never began inspecting")
	inspector.complete()
	assert_eq(inspector.state(), NavInspector.State.RELEARNING)
	assert_true(_run_to(inspector, NavInspector.State.REPLANNING), "never replanned")
	assert_true(_run_to(inspector, NavInspector.State.MOVING), "never went back to moving")


func test_the_alien_holds_still_while_it_looks() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	assert_true(
		inspector.should_hold_still(), "section 29: it must not absorb new terrain mid-stride"
	)
	_run_to(inspector, NavInspector.State.INSPECTING)
	assert_true(inspector.should_hold_still())


func test_the_pause_before_inspecting_is_not_instant() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	inspector.advance(TICK, _config)
	assert_eq(
		inspector.state(),
		NavInspector.State.GEOMETRY_MISMATCH,
		"the beat where the alien stops and orients has to actually last"
	)


# ----- delayed acquisition -----


func test_knowledge_is_offered_only_once_and_only_at_the_end_of_relearning() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	var ready_ticks: int = 0
	var ready_state: NavInspector.State = NavInspector.State.MOVING
	for _step: int in 2000:
		var before: NavInspector.State = inspector.state()
		inspector.advance(TICK, _config)
		if inspector.is_relearn_ready():
			ready_ticks += 1
			ready_state = before
	assert_eq(ready_ticks, 1, "learning twice is learning at a moment nobody chose")
	assert_eq(
		ready_state,
		NavInspector.State.RELEARNING,
		"section 41: acquisition is DELAYED, which means it happens at the end of relearning"
	)


func test_nothing_is_learned_while_the_inspection_is_still_running() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	_run_to(inspector, NavInspector.State.INSPECTING)
	for _step: int in 10:
		inspector.advance(TICK, _config)
		assert_false(
			inspector.is_relearn_ready(),
			"Scenario J: mid-inspection the believed graph must be unchanged"
		)


# ----- section 30's contract -----


func test_behaviour_completing_the_inspection_moves_it_along() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	_run_to(inspector, NavInspector.State.INSPECTING)
	inspector.complete()
	assert_eq(inspector.state(), NavInspector.State.RELEARNING)


func test_an_inspection_nobody_answers_still_finishes() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	assert_true(
		_run_to(inspector, NavInspector.State.MOVING),
		"every project today has no behaviour system; without a timeout the alien wedges"
	)


func test_completing_outside_an_inspection_does_nothing() -> void:
	var inspector: NavInspector = _inspector()
	inspector.complete()
	assert_eq(inspector.state(), NavInspector.State.MOVING)


# ----- the dedupe, which is a bug fix -----


func test_the_same_place_is_not_investigated_twice_in_a_row() -> void:
	var inspector: NavInspector = _inspector()
	assert_true(inspector.report(_request(Vector3.ZERO), 0.0, _config))
	_run_to(inspector, NavInspector.State.MOVING)
	assert_false(
		inspector.report(_request(Vector3(1.0, 0.0, 0.0)), 1.0, _config),
		"an unreachable goal raises this twice a second forever; that was the bug"
	)


func test_a_different_place_is_investigated() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	_run_to(inspector, NavInspector.State.MOVING)
	assert_true(
		inspector.report(_request(Vector3(40.0, 0.0, 0.0)), 1.0, _config),
		"dedupe by place, not a blanket cooldown"
	)


func test_the_same_place_may_be_investigated_again_later() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	_run_to(inspector, NavInspector.State.MOVING)
	var later: float = _config.inspection_dedupe_time + 1.0
	assert_true(
		inspector.report(_request(Vector3.ZERO), later, _config),
		"terrain changes; a place investigated a minute ago is worth another look"
	)


# ----- section 30's STALE_ROUTE is a discovery, not a condition -----
#
# The alien froze for most of every six seconds in front of a slot it does not fit through,
# investigating the same wall for the rest of the level. `_replan` raised STALE_ROUTE on
# every replan while the route stayed non-COMPLETE, and dedupe RATE-LIMITS rather than
# concludes -- so the pursuit timer re-asked forever and every `inspection_dedupe_time` the
# answer got through. Nothing below asserts a delay; they assert that the alien stops asking
# a question it has already had answered.


## Two chambers with a 1 m slot between them: a goal no body fits through, ever.
func _navigation_at_an_impassable_wall() -> CreatureNavigation:
	var navigation := CreatureNavigation.new()
	navigation.config = _config
	navigation.probe = _probe
	# The watchdog is the other thing that raises inspections when a body holds still, and
	# this fixture holds the body still. Nothing wedged can be reported, so what arrives is
	# the route's doing and only the route's.
	_config.progress_threshold = 0.0
	navigation.bake_now(_corridor_cave(IMPASSABLE_CORRIDOR))
	return navigation


## Every STALE_ROUTE request raised over `ticks` with the body held in chamber A.
func _stale_route_requests(navigation: CreatureNavigation, ticks: int) -> Array:
	var seen: Array = []
	navigation.inspection_requested.connect(
		func(request: NavInspectionRequest) -> void:
			if request.reason == NavInspectionRequest.Reason.STALE_ROUTE:
				seen.append(request)
	)
	for _step: int in ticks:
		navigation.advance(TICK, Vector3(4.0, 4.0, 6.0))
	return seen


func test_an_unreachable_goal_is_investigated_once_rather_than_forever() -> void:
	var navigation: CreatureNavigation = _navigation_at_an_impassable_wall()
	navigation.set_goal(Vector3(22.0, 4.0, 6.0))
	var seen: Array = _stale_route_requests(navigation, 2000)
	assert_eq(
		seen.size(),
		1,
		"33 seconds of asking the same wall the same question; the alien is stopped for most of it"
	)
	navigation.free()


func test_a_different_unreachable_goal_is_a_different_question() -> void:
	var navigation: CreatureNavigation = _navigation_at_an_impassable_wall()
	navigation.set_goal(Vector3(22.0, 4.0, 6.0))
	var seen: Array = _stale_route_requests(navigation, 600)
	navigation.set_goal(Vector3(22.0, 4.0, 2.0))
	for _step: int in 600:
		navigation.advance(TICK, Vector3(4.0, 4.0, 6.0))
	assert_eq(seen.size(), 2, "the latch is per goal, not a blanket silence")
	navigation.free()


func test_terrain_changing_under_the_answer_asks_again() -> void:
	var navigation: CreatureNavigation = _navigation_at_an_impassable_wall()
	navigation.set_goal(Vector3(22.0, 4.0, 6.0))
	var seen: Array = _stale_route_requests(navigation, 600)

	# Section 24.2: what the patcher bumps when mining changes the graph. The player has
	# been at the wall, so what the alien concluded about it may no longer hold.
	navigation.world_graph.terrain_revision += 1
	for _step: int in 600:
		navigation.advance(TICK, Vector3(4.0, 4.0, 6.0))
	assert_eq(seen.size(), 2, "an alien that never re-asks never notices the wall came down")
	navigation.free()


func test_nothing_is_accepted_while_an_inspection_is_running() -> void:
	var inspector: NavInspector = _inspector()
	inspector.report(_request(Vector3.ZERO), 0.0, _config)
	assert_false(
		inspector.report(_request(Vector3(40.0, 0.0, 0.0)), 0.5, _config),
		"one thing at a time, or the state machine has no meaning"
	)
