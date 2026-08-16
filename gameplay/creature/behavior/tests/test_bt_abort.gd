extends "res://gameplay/creature/behavior/tests/bt_test_case.gd"

## fsm.md's abort contract, and the ordering hazard it cannot state.
##
## "A RUNNING leaf that is not reached again gets abort()" is the rule. Without it,
## `chase_target` yielding to `lurk_at_crevice` leaves the chase goal live and the alien
## walks to a position nothing asked for -- a stall with no error in it, and the reason
## fsm.md calls this "not optional bookkeeping".
##
## THE PART THAT CANNOT BE IMPLEMENTED AS WRITTEN. fsm.md wants the outgoing leaf aborted
## "before any new leaf ticks". A reactive tree cannot know which leaf will run until it has
## ticked, so the abort necessarily happens after -- and the naive version of that wipes the
## INCOMING leaf's freshly-set goal with the OUTGOING leaf's clear. The last three tests
## here are that hazard, and the ownership handshake that closes it. Delete the owner check
## from BehaviorGoal.release and they are what fails.


func test_a_running_leaf_that_is_not_reached_again_is_aborted() -> void:
	var guard: StubCondition = _condition(&"guard", true)
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_sequence([guard, action]))

	tree.tick(_ctx)
	assert_eq(action.aborts, 0, "it is still running; nothing to give back yet")

	guard.answer = false
	tree.tick(_ctx)
	assert_eq(action.aborts, 1, "the branch was abandoned and the leaf was not told")


func test_a_leaf_that_keeps_running_is_never_aborted() -> void:
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_sequence([_condition(&"guard", true), action]))

	for _i: int in 10:
		tree.tick(_ctx)

	assert_eq(action.ticks, 10)
	assert_eq(action.aborts, 0, "aborting a leaf that is still on the active path resets it")


## Yielding to a HIGHER-priority branch is the case that actually happens in play: an alien
## travelling to a nest when a hotspot appears, mid-route.
func test_yielding_to_a_higher_priority_branch_aborts_the_lower_one() -> void:
	var urgent: StubCondition = _condition(&"urgent", false)
	var interrupt: StubLeaf = _leaf(&"interrupt", BtNode.Status.SUCCESS)
	var travelling: StubLeaf = _running(&"travelling")
	var tree := BehaviorTree.new(_selector([_sequence([urgent, interrupt]), travelling]))

	tree.tick(_ctx)
	assert_eq(travelling.ticks, 1)

	urgent.answer = true
	tree.tick(_ctx)
	assert_eq(interrupt.ticks, 1)
	assert_eq(travelling.aborts, 1, "the travel goal would otherwise still be live")


## A leaf that finishes on its own was reached, so it is not abandoned. Aborting on SUCCESS
## would make every completed action undo itself.
func test_a_leaf_that_finishes_normally_is_not_aborted() -> void:
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_selector([action]))

	tree.tick(_ctx)
	action.status = BtNode.Status.SUCCESS
	tree.tick(_ctx)

	assert_eq(action.aborts, 0, "it was reached and it succeeded; nothing was abandoned")


## The other half of the contract: a state change tears the whole branch down, whatever it
## was doing. A leaf holding a goal when its state exits keeps the creature walking somewhere
## the HFSM has stopped caring about.
func test_aborting_the_tree_tears_down_the_running_branch() -> void:
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_selector([_sequence([_condition(&"ok", true), action])]))

	tree.tick(_ctx)
	tree.abort(_ctx)

	assert_eq(action.aborts, 1)
	assert_null(tree.running_leaf(), "the tree still thinks something is running")


func test_aborting_twice_does_not_abort_the_same_leaf_twice() -> void:
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_selector([action]))

	tree.tick(_ctx)
	tree.abort(_ctx)
	tree.abort(_ctx)

	assert_eq(action.aborts, 1)


func test_a_sibling_that_never_ran_is_never_aborted() -> void:
	var never: StubLeaf = _leaf(&"never", BtNode.Status.SUCCESS)
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(_selector([action, never]))

	tree.tick(_ctx)
	tree.abort(_ctx)

	assert_eq(never.ticks, 0)
	assert_eq(never.aborts, 0, "it holds nothing; telling it to give something back is a bug")


## Abort reaches through decorators to the action that is actually holding something.
func test_abort_reaches_through_a_decorator_to_the_action() -> void:
	var action: StubLeaf = _running()
	var tree := BehaviorTree.new(BtCooldown.new(&"cool", 0.0, BtInverter.new(&"inv", action)))

	tree.tick(_ctx)
	tree.abort(_ctx)

	assert_eq(action.aborts, 1)


func test_the_tree_reports_which_action_is_running() -> void:
	var action: StubLeaf = _running(&"travel_to_nest")
	var tree := BehaviorTree.new(_selector([action]))

	assert_eq(tree.running_action(), &"none")
	tree.tick(_ctx)
	assert_eq(tree.running_action(), &"travel_to_nest")


func test_the_running_action_change_is_announced() -> void:
	var seen: Array = []
	var first: StubLeaf = _running(&"first")
	var guard: StubCondition = _condition(&"guard", false)
	var tree := BehaviorTree.new(_selector([_sequence([guard, first]), _running(&"second")]))
	tree.running_leaf_changed.connect(func(_a: StringName, b: StringName) -> void: seen.append(b))

	tree.tick(_ctx)
	guard.answer = true
	tree.tick(_ctx)

	assert_eq(seen, [&"second", &"first"], "half of 'why is it doing that' is this signal")


func test_an_empty_tree_is_harmless() -> void:
	var tree := BehaviorTree.new(null)
	assert_eq(tree.tick(_ctx), BtNode.Status.FAILURE)
	tree.abort(_ctx)
	assert_null(tree.running_leaf())


## THE ORDERING HAZARD, STATED. The abort runs after the incoming leaf has already asked
## for its goal. Without the owner check in release, the outgoing leaf's abort clears the
## goal the incoming leaf just set, and the alien stands still holding a route to nowhere.
func test_an_incoming_leafs_goal_survives_the_outgoing_leafs_abort() -> void:
	var urgent: StubCondition = _condition(&"urgent", false)
	var chasing: StubLeaf = _running(&"chasing")
	var lurking: StubLeaf = _running(&"lurking")
	chasing.claims_goal = true
	chasing.goal_position = Vector3(10.0, 0.0, 0.0)
	lurking.claims_goal = true
	lurking.goal_position = Vector3(-4.0, 0.0, 0.0)
	var tree := BehaviorTree.new(_selector([_sequence([urgent, lurking]), chasing]))

	tree.tick(_ctx)
	assert_eq(_ctx.goal.position, Vector3(10.0, 0.0, 0.0))

	urgent.answer = true
	tree.tick(_ctx)

	assert_eq(chasing.aborts, 1, "the outgoing leaf must still be told")
	assert_same(_ctx.goal.holder, lurking)
	assert_eq(
		_ctx.goal.position,
		Vector3(-4.0, 0.0, 0.0),
		"the outgoing abort wiped the incoming goal; this is the ordering hazard"
	)


## And the case the owner check must NOT suppress: nothing takes the goal, so the outgoing
## leaf's release has to actually land or the creature keeps walking to a dead objective.
func test_a_goal_nobody_takes_over_is_released() -> void:
	var urgent: StubCondition = _condition(&"urgent", false)
	var idling: StubLeaf = _running(&"idling")
	var travelling: StubLeaf = _running(&"travelling")
	travelling.claims_goal = true
	travelling.goal_position = Vector3(7.0, 0.0, 0.0)
	var tree := BehaviorTree.new(_selector([_sequence([urgent, idling]), travelling]))

	tree.tick(_ctx)
	urgent.answer = true
	tree.tick(_ctx)

	assert_null(_ctx.goal.holder, "nothing claimed it, so it must have been given back")
	assert_eq(_ctx.goal.position, Vector3.ZERO)


func test_tearing_the_tree_down_releases_the_goal_it_was_holding() -> void:
	var travelling: StubLeaf = _running(&"travelling")
	travelling.claims_goal = true
	travelling.goal_position = Vector3(3.0, 0.0, 0.0)
	var tree := BehaviorTree.new(_selector([travelling]))

	tree.tick(_ctx)
	tree.abort(_ctx)

	assert_null(_ctx.goal.holder, "a state change must not leak a navigation goal")
