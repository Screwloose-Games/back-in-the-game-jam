extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## fsm.md's closing invariants, asserted rather than written down.
##
## Every one of these describes a change that would make the alien work BETTER in the short
## term while destroying the design. An action that lowered suspicion directly would resolve
## hotspots crisply. A tree that could transition would react a frame sooner. A condition
## that cached its answer would be cheaper. None of them would fail a behavioural test --
## the creature would simply start working, and nobody would look for the reason.


## Belief has exactly three doors: evidence, disconfirmation, and the clock. Behavior is not
## one of them, and the absence has to be asserted by naming what must not exist.
func test_behavior_has_no_way_to_write_belief() -> void:
	for banned: String in [
		"reduce_suspicion",
		"clear_hotspot",
		"mark_investigation_complete",
		"set_suspicion",
		"resolve_hotspot",
		"submit_evidence",
		"submit_disconfirmation",
	]:
		assert_false(
			_behavior.has_method(banned),
			"%s would let the creature declare a room searched without going there" % banned
		)


## The Director publishes a directive; Behavior honours it at a moment of its own choosing.
## A method that let anything drive the machine directly would make the table a suggestion.
func test_nothing_outside_the_hfsm_can_change_state() -> void:
	for banned: String in ["set_state", "force_state", "transition_to", "enter_state"]:
		assert_false(_behavior.has_method(banned), "%s would bypass the transition table" % banned)


## An action never moves the body. It commands Navigation, which owns acceleration, turning
## and collision response.
func test_behavior_never_moves_the_body_itself() -> void:
	for banned: String in ["move_to", "teleport", "set_position", "apply_velocity"]:
		assert_false(_behavior.has_method(banned))


## Conditions are re-evaluated from the root every frame, so one that mutated anything would
## mutate it once per frame forever. Ticking each one repeatedly must change nothing.
func test_conditions_are_free_of_side_effects() -> void:
	_add_navigation()
	_nests([Vector3(12.0, 0.0, 0.0)])
	_advance(0.5)

	var condition := BtAtNest.new(_unalerted().memory)
	var first: bool = condition.tick(_behavior.context) == BtNode.Status.SUCCESS
	var target_before: int = _unalerted().memory.travel_target
	for _i: int in 20:
		condition.tick(_behavior.context)

	assert_eq(condition.tick(_behavior.context) == BtNode.Status.SUCCESS, first)
	assert_eq(_unalerted().memory.travel_target, target_before, "a condition moved the intent")


## A condition physically cannot report RUNNING however it is written: subclasses implement
## `_check`, which returns a bool.
func test_no_condition_can_report_running() -> void:
	_add_navigation()
	_advance(0.2)
	var conditions: Array[BtCondition] = [
		BtAtNest.new(_unalerted().memory), BtArrivedAtGoal.new(_investigating().memory)
	]
	for condition: BtCondition in conditions:
		assert_ne(condition.tick(_behavior.context), BtNode.Status.RUNNING)


## Every state must be reachable and answer for itself, or a transition into it is a silent
## no-op that leaves the creature in the state it was already in.
func test_every_state_is_registered_and_names_itself() -> void:
	for id: int in [
		CreatureState.State.UNALERTED,
		CreatureState.State.INVESTIGATING,
		CreatureState.State.HUNTING,
		CreatureState.State.RETREATING,
	]:
		var state: BehaviorState = _behavior.hfsm.state_of(id)
		assert_not_null(state, "%s is not registered" % CreatureState.state_name(id))
		assert_eq(state.state_id(), id, "a state answers for the wrong id")
		assert_not_null(state.tree, "%s has no tree" % CreatureState.state_name(id))


## Trees are per creature. BtCooldown holds a last-success time and BehaviorTree holds a
## running-leaf reference, so a shared tree would couple two aliens' cooldowns in a way that
## reads as a tuning problem.
func test_two_creatures_do_not_share_a_tree() -> void:
	var other: CreatureBehavior = autofree(CreatureBehavior.new())
	for id: int in [CreatureState.State.UNALERTED, CreatureState.State.INVESTIGATING]:
		assert_not_same(
			_behavior.hfsm.state_of(id).tree,
			other.hfsm.state_of(id).tree,
			"%s's tree is shared between creatures" % CreatureState.state_name(id)
		)


## The Director may know the truth and may only emit bias. Behavior never receives a position
## from it, so nothing here may reach for the target's transform.
func test_behavior_never_reads_a_targets_position() -> void:
	var player: Node3D = _player("p1")
	player.position = Vector3(99.0, 99.0, 99.0)
	_direct().target = player
	_add_navigation()
	_nests([Vector3(12.0, 0.0, 0.0)])
	_advance(1.0)

	if _behavior.goal.has_goal():
		assert_ne(
			_behavior.goal.committed(),
			player.position,
			"the creature navigated straight to a real player position"
		)


## An alien that stops on purpose repeatedly is a failure shape navigation's watchdog
## deliberately cannot catch, so every raiser has to be edge-triggered. Re-issuing a goal
## resets that watchdog.
func test_a_steady_goal_is_committed_once_rather_than_every_frame() -> void:
	_add_navigation()
	_nests([Vector3(25.0, 0.0, 0.0)])
	_advance(0.5)
	var committed: Vector3 = _behavior.goal.committed()

	_advance(1.0)
	assert_eq(_behavior.goal.committed(), committed, "the goal was re-issued while nothing changed")


## Releasing a goal nobody holds must not clear one somebody does -- that is the whole of the
## ownership rule that makes the abort ordering safe.
func test_releasing_a_goal_you_do_not_hold_does_nothing() -> void:
	_add_navigation()
	_nests([Vector3(25.0, 0.0, 0.0)])
	_advance(0.5)
	assert_true(_behavior.goal.has_goal())

	_behavior.goal.release(BtDoNothing.new(&"impostor"))

	assert_true(_behavior.goal.has_goal(), "a node that never asked was able to cancel the goal")


## The two file-scanning rules -- no wall clock anywhere, and `tree/` naming no creature
## subsystem -- live in `tools/verify_behavior_static.gd` rather than here, for the reason
## that verifier documents: a check for a banned token has to strip comments first, or it
## fires on the docstring explaining why the token is banned. Both rules cost this suite a
## false failure before they were moved, which is the argument for the split made concrete.


func _unalerted() -> UnalertedState:
	return _behavior.hfsm.state_of(CreatureState.State.UNALERTED) as UnalertedState


func _investigating() -> InvestigatingState:
	return _behavior.hfsm.state_of(CreatureState.State.INVESTIGATING) as InvestigatingState
