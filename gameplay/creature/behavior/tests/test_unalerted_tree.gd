extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## The UNALERTED tree: choose a nest, travel, idle, choose another.
##
## ```text
## Selector
## |-- Sequence[at_nest, idle_at_nest]
## +-- travel_to_nest
## ```
##
## THE LOOP THIS SUITE EXISTS TO CATCH is the alien that arrives at a nest and never leaves.
## It happens whenever `at_nest` answers about PROXIMITY rather than about INTENT: the dwell
## finishes, the creature is still standing in the nest, the idle branch wins again and
## re-arms its own timer. Nothing errors, the creature simply stops being territorial, and
## the only symptom is an alien you always know the location of.


func test_a_calm_creature_sets_off_for_a_nest() -> void:
	_add_navigation()
	_nests([Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_tick()

	assert_eq(_behavior.running_action(), &"travel_to_nest")
	assert_true(_behavior.goal.has_goal(), "travelling without a goal is standing still")


func test_arriving_at_the_nest_starts_a_dwell() -> void:
	_add_navigation()
	_nests([Vector3(10.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_tick()
	_walk_to(Vector3(10.0, 0.0, 0.0), 0.5)

	assert_eq(_behavior.running_action(), &"idle_at_nest")


## THE ASSERTION THIS FILE EXISTS FOR. After the dwell the alien must pick somewhere else,
## not settle in.
func test_the_creature_leaves_again_when_the_dwell_is_over() -> void:
	_add_navigation()
	_nests([Vector3(10.0, 0.0, 0.0), Vector3(-10.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_tick()
	_walk_to(Vector3(10.0, 0.0, 0.0), 0.5)
	assert_eq(_behavior.running_action(), &"idle_at_nest")

	_advance(_config.nest_dwell_s + 0.2)

	assert_eq(_behavior.running_action(), &"travel_to_nest", "the alien settled in and stopped")


func test_the_nest_it_just_left_is_not_the_one_it_picks() -> void:
	_add_navigation()
	var here := Vector3(10.0, 0.0, 0.0)
	_nests([here, Vector3(-10.0, 0.0, 0.0)])
	_place(here)
	_advance(_config.nest_dwell_s + 0.5)

	var memory: UnalertedMemory = _unalerted().memory
	assert_ne(memory.travel_target, -1, "nowhere was chosen")
	assert_ne(memory.nests.position_of(memory.travel_target), here)


## Recency is the other half of the anti-ping-pong rule: with three nests the alien should
## work round them rather than bouncing between the two nearest.
func test_wandering_visits_more_than_two_nests() -> void:
	_add_navigation()
	var nests: Array = [Vector3(12.0, 0.0, 0.0), Vector3(-12.0, 0.0, 0.0), Vector3(0.0, 0.0, 12.0)]
	_nests(nests)
	_place(Vector3.ZERO)

	var visited := {}
	for _trip: int in 4:
		_tick()
		var target: int = _unalerted().memory.travel_target
		if target < 0:
			continue
		visited[target] = true
		_walk_to(nests[target], 0.4)
		_advance(_config.nest_dwell_s + 0.2)

	assert_gt(visited.size(), 2, "the alien is ping-ponging between two nests")


## The Director's only reach into where the creature idles. A weighting on nests it already
## knows -- never a destination of its own.
func test_a_positive_roam_bias_pulls_the_choice_toward_the_anchor() -> void:
	_add_navigation()
	var far_side := Vector3(0.0, 0.0, 25.0)
	_nests([Vector3(12.0, 0.0, 0.0), far_side])
	_place(Vector3.ZERO)

	_direct().roam_bias = 1.0
	_directive.roam_anchor = far_side
	_tick()

	assert_eq(_unalerted().memory.nests.position_of(_unalerted().memory.travel_target), far_side)


func test_a_negative_roam_bias_pushes_it_away() -> void:
	_add_navigation()
	var near_anchor := Vector3(12.0, 0.0, 0.0)
	_nests([near_anchor, Vector3(0.0, 0.0, 25.0)])
	_place(Vector3.ZERO)

	_direct().roam_bias = -1.0
	_directive.roam_anchor = near_anchor
	_tick()

	assert_ne(_unalerted().memory.nests.position_of(_unalerted().memory.travel_target), near_anchor)


## A nest behind a collapse must not hold the alien RUNNING against a route that can never
## complete -- it would stand at the wall for the rest of the session.
func test_an_unreachable_nest_is_abandoned_for_another() -> void:
	_add_navigation()
	# Well outside the baked room, so no graph node can attach and the route comes back
	# UNREACHABLE rather than PARTIAL. A nest inside the room is always reachable somehow.
	var unreachable := Vector3(500.0, 0.0, 0.0)
	var reachable := Vector3(-14.0, 0.0, 0.0)
	_nests([unreachable, reachable])
	_place(Vector3.ZERO)

	_advance(1.0)

	var memory: UnalertedMemory = _unalerted().memory
	assert_eq(
		memory.nests.position_of(memory.travel_target),
		reachable,
		"the alien is still walking at a nest it can never get to"
	)
	assert_eq(_state(), CreatureState.State.UNALERTED, "an unreachable nest is not an emergency")


func test_a_creature_with_no_nests_does_not_crash_or_transition() -> void:
	_add_navigation()
	_nests([])
	_advance(1.0)

	assert_eq(_state(), CreatureState.State.UNALERTED)
	assert_false(_behavior.goal.has_goal(), "there is nowhere to go; nothing should be commanded")


## Interrupting UNALERTED must not leak the travel goal into the next state.
func test_leaving_the_state_gives_the_travel_goal_back() -> void:
	_add_navigation()
	_nests([Vector3(20.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_advance(_config.min_dwell_s + 0.2)
	assert_true(_behavior.goal.has_goal())

	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()
	assert_eq(_state(), CreatureState.State.INVESTIGATING)

	var holder: BtNode = _behavior.goal.holder()
	assert_true(
		holder == null or holder.node_name != &"travel_to_nest",
		"the nest goal survived the state change and the alien is still walking to it"
	)


## Stamped on arrival rather than departure, so the very next choice cannot land on the nest
## the creature is sitting in.
func test_a_nest_is_marked_visited_when_the_creature_gets_there() -> void:
	_add_navigation()
	_nests([Vector3(10.0, 0.0, 0.0), Vector3(-10.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_tick()
	var target: int = _unalerted().memory.travel_target

	_walk_to(_unalerted().memory.nests.position_of(target), 0.4)
	_tick()

	assert_gt(_unalerted().memory.nests.visited_at(target), 0.0)


func test_the_running_action_is_announced_as_it_changes() -> void:
	_add_navigation()
	_nests([Vector3(8.0, 0.0, 0.0)])
	_place(Vector3.ZERO)
	_tick()
	_walk_to(Vector3(8.0, 0.0, 0.0), 0.4)

	assert_has(_actions, &"travel_to_nest")
	assert_has(_actions, &"idle_at_nest")


func _unalerted() -> UnalertedState:
	return _behavior.hfsm.state_of(CreatureState.State.UNALERTED) as UnalertedState
