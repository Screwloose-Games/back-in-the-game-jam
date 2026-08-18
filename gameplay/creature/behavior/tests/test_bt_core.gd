extends "res://gameplay/creature/behavior/tests/bt_test_case.gd"

## The six node types from fsm.md's table, and the reactivity rule that makes them useful.
##
## Composite semantics are the boring half and are asserted anyway, because every one of
## them has an off-by-one form that produces a tree which mostly works: a selector that
## treats RUNNING as failure walks past a leaf that is mid-action, a sequence that treats
## RUNNING as success reports a half-finished search as complete. Neither errors.
##
## The interesting half is `test_a_running_leaf_does_not_stop_conditions_being_re_asked`.
## That is the entire trade fsm.md makes -- a few condition evaluations per frame, in
## exchange for an alien that changes its mind the instant the evidence does.


func test_a_selector_returns_the_first_child_that_does_not_fail() -> void:
	var second: StubLeaf = _leaf(&"second", BtNode.Status.SUCCESS)
	var third: StubLeaf = _leaf(&"third", BtNode.Status.SUCCESS)
	var selector: BtSelector = _selector([_leaf(&"first", BtNode.Status.FAILURE), second, third])

	assert_eq(_tick(selector), BtNode.Status.SUCCESS)
	assert_eq(second.ticks, 1)
	assert_eq(third.ticks, 0, "a selector stops at its first non-failure")


func test_a_selector_whose_children_all_fail_fails() -> void:
	var selector: BtSelector = _selector(
		[_leaf(&"a", BtNode.Status.FAILURE), _leaf(&"b", BtNode.Status.FAILURE)]
	)
	assert_eq(_tick(selector), BtNode.Status.FAILURE)


## RUNNING is not failure. A selector that walked past it would abandon a leaf mid-action
## every frame it was ticked, and the lower-priority branch would run instead.
func test_a_selector_stops_at_a_running_child() -> void:
	var later: StubLeaf = _leaf(&"later", BtNode.Status.SUCCESS)
	var selector: BtSelector = _selector([_running(), later])

	assert_eq(_tick(selector), BtNode.Status.RUNNING)
	assert_eq(later.ticks, 0)


func test_a_sequence_returns_the_first_child_that_does_not_succeed() -> void:
	var third: StubLeaf = _leaf(&"third", BtNode.Status.SUCCESS)
	var sequence: BtSequence = _sequence(
		[_leaf(&"a", BtNode.Status.SUCCESS), _leaf(&"b", BtNode.Status.FAILURE), third]
	)

	assert_eq(_tick(sequence), BtNode.Status.FAILURE)
	assert_eq(third.ticks, 0)


func test_a_sequence_whose_children_all_succeed_succeeds() -> void:
	var sequence: BtSequence = _sequence(
		[_leaf(&"a", BtNode.Status.SUCCESS), _leaf(&"b", BtNode.Status.SUCCESS)]
	)
	assert_eq(_tick(sequence), BtNode.Status.SUCCESS)


## RUNNING is not success either. A sequence that advanced past it would report a
## half-finished action as complete and run the next one on top of it.
func test_a_sequence_stops_at_a_running_child() -> void:
	var later: StubLeaf = _leaf(&"later", BtNode.Status.SUCCESS)
	var sequence: BtSequence = _sequence([_running(), later])

	assert_eq(_tick(sequence), BtNode.Status.RUNNING)
	assert_eq(later.ticks, 0)


## THE ASSERTION THIS FILE EXISTS FOR. fsm.md: "Conditions are re-evaluated even when a
## deeper leaf is RUNNING." A memory-BT keeps the alien walking to a stale hotspot while a
## louder, closer lead goes unexamined, because the branch that chose the stale one is
## never revisited -- and every individual decision still looks correct.
func test_a_running_leaf_does_not_stop_conditions_being_re_asked() -> void:
	var guard: StubCondition = _condition(&"guard", true)
	var action: StubLeaf = _running()
	var tree: BtSequence = _sequence([guard, action])

	for _i: int in 5:
		_tick(tree)

	assert_eq(guard.checks, 5, "the condition was asked once and then trusted")
	assert_eq(action.ticks, 5)


## The other half: when the condition changes its mind, the running action is dropped on
## that frame rather than after it finishes.
func test_a_condition_going_false_stops_the_running_action_beneath_it() -> void:
	var guard: StubCondition = _condition(&"guard", true)
	var action: StubLeaf = _running()
	var tree: BtSequence = _sequence([guard, action])

	_tick(tree)
	guard.answer = false
	assert_eq(_tick(tree), BtNode.Status.FAILURE)
	assert_eq(action.ticks, 1, "the action must not be ticked once its reason has gone")


## No sibling memory: a composite restarts at child zero, so a higher-priority branch that
## becomes viable takes over on the frame it does.
func test_a_composite_restarts_at_its_first_child_every_tick() -> void:
	var first: StubCondition = _condition(&"first", false)
	var fallback: StubLeaf = _leaf(&"fallback", BtNode.Status.SUCCESS)
	var selector: BtSelector = _selector([first, fallback])

	_tick(selector)
	assert_eq(fallback.ticks, 1)

	first.answer = true
	assert_eq(_tick(selector), BtNode.Status.SUCCESS)
	assert_eq(fallback.ticks, 1, "the higher-priority branch should have won this tick")


func test_an_inverter_swaps_success_and_failure() -> void:
	var pass_node := BtInverter.new(&"not", _leaf(&"a", BtNode.Status.SUCCESS))
	var fail_node := BtInverter.new(&"not", _leaf(&"b", BtNode.Status.FAILURE))

	assert_eq(_tick(pass_node), BtNode.Status.FAILURE)
	assert_eq(_tick(fail_node), BtNode.Status.SUCCESS)


## RUNNING means "ask me again", not a result. Inverting it would report a half-finished
## action as complete.
func test_an_inverter_passes_running_through_unchanged() -> void:
	assert_eq(_tick(BtInverter.new(&"not", _running())), BtNode.Status.RUNNING)


## A condition physically cannot report RUNNING, however it is written -- subclasses
## implement `_check`, which returns a bool.
func test_a_condition_only_ever_succeeds_or_fails() -> void:
	assert_eq(_tick(_condition(&"yes", true)), BtNode.Status.SUCCESS)
	assert_eq(_tick(_condition(&"no", false)), BtNode.Status.FAILURE)


## `-INF`, not zero. A clock injected from delta starts at 0.0, and a naive
## `now - 0.0 < seconds` would mute the child for the creature's first few seconds of life.
func test_a_cooldown_is_available_on_the_very_first_tick() -> void:
	var child: StubLeaf = _leaf(&"child", BtNode.Status.SUCCESS)
	assert_eq(_tick(BtCooldown.new(&"cool", 5.0, child)), BtNode.Status.SUCCESS)
	assert_eq(child.ticks, 1)


func test_a_cooldown_fails_until_its_interval_has_elapsed_since_success() -> void:
	var child: StubLeaf = _leaf(&"child", BtNode.Status.SUCCESS)
	var cooldown := BtCooldown.new(&"cool", 5.0, child)

	_tick(cooldown)
	_elapse(4.0)
	assert_eq(_tick(cooldown), BtNode.Status.FAILURE)
	assert_eq(child.ticks, 1, "the child must not even be asked while cooling")

	_elapse(1.5)
	assert_eq(_tick(cooldown), BtNode.Status.SUCCESS)
	assert_eq(child.ticks, 2)


## Times from SUCCESS, not from the attempt. A cooldown that started on the attempt would
## lock a branch out for failing, which is the opposite of what a fallback selector needs.
func test_a_cooldown_does_not_start_on_a_failed_or_running_attempt() -> void:
	var child: StubLeaf = _leaf(&"child", BtNode.Status.FAILURE)
	var cooldown := BtCooldown.new(&"cool", 5.0, child)

	_tick(cooldown)
	assert_eq(_tick(cooldown), BtNode.Status.FAILURE)
	assert_eq(child.ticks, 2, "a failure must not have started the timer")

	child.status = BtNode.Status.RUNNING
	_tick(cooldown)
	assert_eq(child.ticks, 3, "nor must a RUNNING tick")


func test_every_node_type_carries_a_name_for_the_debug_line() -> void:
	var nodes: Array[BtNode] = [
		_selector([]),
		_sequence([]),
		_condition(&"cond", true),
		_leaf(&"act", BtNode.Status.SUCCESS),
		BtInverter.new(&"inv", null),
		BtCooldown.new(&"cool", 1.0, null),
	]
	for node: BtNode in nodes:
		assert_ne(node.node_name, &"", "%s has no name" % node)
		assert_ne(node.node_name, &"node", "%s kept the base default" % node)


func test_every_status_has_a_debug_name() -> void:
	for status: int in [BtNode.Status.SUCCESS, BtNode.Status.FAILURE, BtNode.Status.RUNNING]:
		assert_ne(BtNode.status_name(status), "?", "status %d has no name" % status)


## A decorator is never itself the running leaf. One that answered for itself would have the
## tree abort a wrapper while the action inside kept its navigation goal.
func test_running_leaf_reaches_through_decorators_to_the_action() -> void:
	var action: StubLeaf = _running(&"the_action")
	var wrapped := BtCooldown.new(&"cool", 0.0, BtInverter.new(&"inv", action))

	_tick(wrapped)
	assert_same(wrapped.running_leaf(), action)


func test_a_composite_reports_the_running_leaf_of_the_branch_it_took() -> void:
	var action: StubLeaf = _running(&"deep")
	var selector: BtSelector = _selector(
		[_leaf(&"skipped", BtNode.Status.FAILURE), _sequence([_condition(&"ok", true), action])]
	)

	_tick(selector)
	assert_same(selector.running_leaf(), action)


func test_nothing_is_running_when_the_tree_settles() -> void:
	var selector: BtSelector = _selector([_leaf(&"done", BtNode.Status.SUCCESS)])
	_tick(selector)
	assert_null(selector.running_leaf())
