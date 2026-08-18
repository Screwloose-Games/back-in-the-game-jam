extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## The RETREATING tree: a far nest, loudly or quietly depending on how it ended.
##
## ```text
## Selector
## |-- Sequence[disengage_was_sated, retreat_to_nest(distant, loud)]
## +-- retreat_to_nest(distant, quiet)
## ```
##
## THE LOOP THIS SUITE EXISTS TO CATCH is the split that quietly stops splitting. The reason
## an encounter ended lives on a directive the Director rebuilds every tick, and the latch that
## forced the retreat was consumed at the transition -- so by the time the tree first runs, the
## live `disengage_reason` has very often reset to NONE. A tree that read it per tick would
## take the quiet branch every single time, and every guard in `test_hfsm_transitions.gd` would
## still pass, because nothing about the transition changed. The player just never gets the
## exhale, and a stalemate and a real chase end on the same beat.
##
## The other half is the retreat that never retreats. `travel_target` is an index into a nest
## list, and a state that inherits one from a list it has not been handed walks nowhere and
## exits on `gave_up` every time instead of on `separated`.

## Two nests, so "prefer a far one" has something to choose between.
const NEAR_NEST := Vector3(6.0, 0.0, 0.0)
## Far enough from the hunt's last credible target position to clear `retreat_separation_m`,
## which is what the retreat is actually measured against -- not distance from the start.
const FAR_NEST := Vector3(-26.0, 0.0, 0.0)


## THE ASSERTION THIS FILE EXISTS FOR.
func test_the_loud_exit_survives_a_director_that_forgets_why() -> void:
	_retreat(EncounterDirective.Reason.SATED)
	assert_eq(_behavior.running_action(), &"retreat_to_nest_loud", "the fixture never left loudly")

	# Exactly what a real Director does: it publishes a fresh directive every tick, and this
	# one has stopped asking for anything.
	_directive.disengage_reason = EncounterDirective.Reason.NONE
	_directive.force_disengage = false
	_advance(1.0)

	assert_eq(
		_behavior.running_action(),
		&"retreat_to_nest_loud",
		"the exhale turned into a sneak the moment the Director stopped repeating itself"
	)


func test_an_earned_ending_leaves_loudly() -> void:
	_retreat(EncounterDirective.Reason.SATED)

	assert_eq(_state(), CreatureState.State.RETREATING)
	assert_eq(
		_behavior.running_action(),
		&"retreat_to_nest_loud",
		"a hunt that reached its peak ended on the same beat as one that stalled"
	)


func test_a_stalemate_leaves_quietly() -> void:
	_retreat(EncounterDirective.Reason.STALLED)

	assert_eq(
		_behavior.running_action(),
		&"retreat_to_nest",
		"the game congratulated a player who did nothing"
	)


## The scoring function is shared with wandering and only the distance term's sign differs.
func test_a_retreat_picks_the_further_nest() -> void:
	_retreat(EncounterDirective.Reason.STALLED)

	assert_true(_behavior.goal.has_goal(), "retreating without a goal is standing still")
	assert_eq(
		_behavior.goal.committed(),
		FAR_NEST,
		"the alien retreated to the nearest nest, which creates no space at all"
	)


## behavior.md section 30, at tree level. `test_hfsm_transitions.gd` asserts the guard; this
## asserts the creature actually keeps walking, because a tree that turned round would look
## identical in the transition log.
func test_a_retreating_creature_walks_away_from_a_player_who_reveals_themselves() -> void:
	var player: Node3D = _player("target")
	_retreat(EncounterDirective.Reason.STALLED)
	var heading: Vector3 = _behavior.goal.committed()

	for _i: int in 120:
		_see(player, _body.position)
		_hear(_body.position, 1.0)
		_tick()

	assert_eq(_state(), CreatureState.State.RETREATING, "an alien walking away must stay walking")
	assert_eq(_behavior.running_action(), &"retreat_to_nest", "it turned round")
	assert_eq(_behavior.goal.committed(), heading, "it changed its mind about where it was going")


func test_a_retreat_that_gets_far_enough_ends_the_encounter() -> void:
	_retreat(EncounterDirective.Reason.SATED)
	var anchor: Vector3 = _retreating().separation_from

	_walk_to(FAR_NEST, 1.0)
	_advance(_config.retreat_min_s + 0.5)

	assert_gt(
		_body.position.distance_to(anchor),
		_config.retreat_separation_m,
		"the fixture never actually created any separation"
	)
	assert_has(_reasons(), &"separated", "the retreat ended on the backstop rather than on merit")
	# NOT necessarily UNALERTED. The Director never damps suspicion, so a creature that has
	# just walked away still fully believes you are back there and is entitled to go and look
	# again -- director.md is explicit that the cooldown works by shifting thresholds rather
	# than by editing belief. What must not happen is the retreat continuing.
	assert_ne(_state(), CreatureState.State.RETREATING, "the retreat never let go")


## `retreat_max_s` is not decoration, and this is the case it is the only answer to.
##
## A NEST OUTSIDE THE GRAPH DOES NOT FAIL. The route to it comes back PARTIAL rather than
## UNREACHABLE -- a partial route is deliberately not a failure -- so `travel_to_nest`'s
## UNREACHABLE clause never fires and the alien walks contentedly at rock. Every nest here also
## sits inside `retreat_separation_m` of where the hunt was given up, so no amount of walking
## ends the state on merit either. Something has to, or the Director cannot terminate an
## encounter and the whole pacing loop stops.
func test_a_retreat_that_can_never_get_far_enough_still_ends() -> void:
	_config.retreat_min_s = 1.0
	_config.retreat_max_s = 3.0
	_retreat(EncounterDirective.Reason.STALLED, [Vector3(2.0, 0.0, 4.0), Vector3(-3.0, 0.0, 2.0)])

	_advance(_config.retreat_max_s + 0.5)

	assert_has(_reasons(), &"gave_up", "the encounter had no way to end and did not")
	assert_ne(_state(), CreatureState.State.RETREATING, "the retreat never let go")


func test_leaving_the_state_gives_the_retreat_goal_back() -> void:
	_retreat(EncounterDirective.Reason.SATED)
	assert_true(_behavior.goal.has_goal())

	_behavior.hfsm.reset_to(CreatureState.State.UNALERTED, _behavior.context)

	assert_false(_behavior.goal.has_goal(), "the retreat goal leaked into the next state")


## One creature, one visit log. A visit stamp is a fact about where the creature has been, not
## about the mood it was in -- give each mode its own and the wandering half has no record of
## anywhere the retreating half went, so the alien walks back to a nest it was just at and
## `nest_recent_penalty_s` looks broken from the outside.
func test_the_retreat_and_the_wander_share_one_visit_log() -> void:
	_retreat(EncounterDirective.Reason.STALLED)

	assert_same(
		_retreating().memory.nests, _behavior.nest_memory, "the retreat kept a nest list of its own"
	)
	assert_same(
		_unalerted().memory.nests, _behavior.nest_memory, "the wander kept a nest list of its own"
	)


## And the retreat is given one at all. `travel_target` indexes into a list, so a state that
## never received one has nowhere to walk -- and would sit out its whole commitment period
## looking exactly like the placeholder it replaced.
func test_the_retreat_is_handed_the_nests() -> void:
	_retreat(EncounterDirective.Reason.STALLED)

	assert_false(_retreating().memory.nests.is_empty(), "the retreat has nowhere to go")
	assert_gt(_retreating().memory.travel_target, -1, "the retreat never chose a nest")


func test_the_tree_never_moves_the_body() -> void:
	_retreat(EncounterDirective.Reason.SATED)
	var at: Vector3 = _body.position

	_advance(1.0)

	assert_eq(_body.position, at, "an action moved the creature instead of commanding navigation")


# ----- helpers -----


## Hunts, then has the Director call it off for `reason`, and leaves the creature one tick into
## RETREATING with its tree running.
func _retreat(reason: EncounterDirective.Reason, nests: Array = [NEAR_NEST, FAR_NEST]) -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_nests(nests)
	_place(Vector3.ZERO)

	_advance(_config.min_dwell_s + 0.1)
	for _i: int in int(roundf((_config.min_dwell_s * 3.0 + 1.0) / TICK)):
		_see(player, Vector3(0.0, 0.0, 6.0))
		_tick()
		if _state() == CreatureState.State.HUNTING:
			break
	assert_eq(_state(), CreatureState.State.HUNTING, "the fixture never reached HUNTING")

	_direct().force_disengage = true
	_directive.disengage_reason = reason
	_advance(_config.min_dwell_s + 0.2)
	assert_eq(_state(), CreatureState.State.RETREATING, "the fixture never started retreating")


func _retreating() -> RetreatingState:
	return _behavior.hfsm.state_of(CreatureState.State.RETREATING) as RetreatingState


func _unalerted() -> UnalertedState:
	return _behavior.hfsm.state_of(CreatureState.State.UNALERTED) as UnalertedState
