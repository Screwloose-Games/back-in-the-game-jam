extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## The HUNTING tree: bite, chase, wait, sweep, in that order.
##
## ```text
## Selector
## |-- Sequence[can_attack, attack]
## |-- Sequence[has_target_estimate, chase_target]
## |-- Sequence[target_beyond_reach, lurk_at_tunnel_mouth]
## +-- Cooldown[search_area]
## ```
##
## THE LOOP THIS SUITE EXISTS TO CATCH is the alien that arrives where it believed you were,
## finds nobody, and stands there until the hunt starves. It happens the moment `chase_target`
## reports SUCCESS on arrival, because a selector stops at its first non-FAILURE child -- the
## sweep below it never runs, the region is never disconfirmed, and the creature holds a
## perfectly good route to a place it is already standing in. Nothing errors. It reads as a
## pathfinding bug and it is a control-flow one.
##
## The second thing here is the ORDER, which is the priority claim rather than an arrangement:
## bite beats pursue beats wait beats search. A tree that got it right most of the time by
## accident is a tree that lunges at the wrong moment once a session.


## THE ASSERTION THIS FILE EXISTS FOR. Arriving must hand the tick to the sweep.
func test_arriving_where_it_believed_you_were_starts_a_sweep() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 6.0))

	# Standing on the estimate with the bite already spent, so the only branches left are the
	# ones below chase.
	_place(_estimate())
	_advance(_config.attack_cooldown_s * 0.25)
	_see(player, _estimate())
	_tick()

	assert_eq(
		_behavior.running_action(),
		&"search_area",
		"the alien arrived, found nobody, and never looked around"
	)


func test_the_branch_order_is_the_priority_claim() -> void:
	var root := _hunting().tree.root as BtSelector
	var names: Array = []
	for child: BtNode in root.children:
		names.append(child.node_name)

	assert_eq(
		names, [&"bite_gate", &"pursue", &"wait", &"search_gate"], "bite must beat everything"
	)


func test_a_hunting_creature_runs_at_the_estimate() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 12.0))

	assert_eq(_behavior.running_action(), &"chase_target")
	assert_true(_behavior.goal.has_goal(), "hunting without a goal is standing still")
	assert_lt(
		_behavior.goal.committed().distance_to(_estimate()),
		_config.goal_refresh_m,
		"the goal is not where the creature believes the target is"
	)


## The bite outranks the chase, and it has to: an alien that walks the last two metres instead
## of striking is an alien that never lands a hit.
func test_the_bite_beats_the_chase() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 6.0))
	assert_eq(_behavior.running_action(), &"chase_target", "the fixture never started chasing")

	_place(_estimate())
	_see(player, _estimate())
	_tick()

	assert_eq(_attacks.size(), 1, "the alien had its target within reach and walked at it")


## And it outranks the wait, which is the case worth pinning: the target is beyond reach AND
## close enough to strike, which is what a player standing just inside a gap looks like.
func test_the_bite_beats_the_wait() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, Vector3(14.0, 0.0, 0.0))
	assert_true(_hunting().memory.beyond_reach, "the fixture never produced an unreachable target")

	_place(_estimate() - Vector3(2.0, 0.0, 0.0))
	_see(player, _estimate())
	_tick()

	assert_eq(_attacks.size(), 1, "the alien settled in to wait with the target inside its reach")


func test_the_alien_does_not_bite_every_frame() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 6.0))
	_place(_estimate())

	for _i: int in int(roundf((_config.attack_cooldown_s * 2.0) / TICK)):
		_see(player, _estimate())
		_tick()

	assert_lt(_attacks.size(), 5, "the cooldown is not holding; the alien is machine-gunning")
	assert_gt(_attacks.size(), 1, "two cooldowns elapsed and it struck at most once")


## The Director owns the flag and Behavior owns the consequence. director.md's "one near-miss
## per encounter" rule lives up there too, because it needs session history this module does
## not have -- so what is asserted here is that the action reports faithfully whichever it is
## handed and never substitutes its own judgement.
func test_the_attack_reports_the_lethality_it_was_handed() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_direct().lethality = EncounterDirective.Lethality.GRACE
	_hunt(player, Vector3(0.0, 0.0, 6.0))
	_place(_estimate())
	_see(player, _estimate())
	_tick()
	assert_eq(_attacks.size(), 1, "the fixture never landed a first strike")
	assert_eq(
		_attacks[0][1],
		EncounterDirective.Lethality.GRACE,
		"the alien killed on a swing the Director had marked as a near-miss"
	)

	_directive.lethality = EncounterDirective.Lethality.LETHAL
	_advance(_config.attack_cooldown_s + 0.2)
	_see(player, _estimate())
	_tick()

	assert_gt(_attacks.size(), 1, "the second strike never came")
	assert_eq(
		_attacks[-1][1],
		EncounterDirective.Lethality.LETHAL,
		"the alien is still pulling its punch after the grace was spent"
	)


## behavior.md section 27: the estimate becomes less trustworthy as its evidence ages. It gates
## the BITE and not the walk -- an alien that has lost sight of you still goes to look, which
## is section 28, and standing still to scan a region twenty metres away is not searching.
func test_a_stale_estimate_is_still_worth_walking_to_and_not_worth_biting() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 12.0))
	assert_eq(_behavior.running_action(), &"chase_target", "the fixture never started chasing")

	_advance(_config.target_estimate_max_age_s + 0.5)

	assert_true(_hunting().memory.estimate_is_stale, "the estimate never aged")
	assert_eq(
		_behavior.running_action(),
		&"chase_target",
		"the alien lost sight of its target and stopped going to look for it"
	)

	# Standing on it, and still nothing has named the target since.
	_place(_estimate())
	_tick()

	assert_false(
		_hunting().memory.attack_window_open,
		"the alien is swinging at a position nobody has confirmed in seconds"
	)
	assert_eq(_attacks.size(), 0, "it got a free hit off its own memory")


## Aged on Suspicion's clock, which is not Behavior's. The two agree only if the nodes were
## built on the same frame, and subtracting one from the other compiles, runs and produces
## garbage.
func test_the_estimate_is_aged_on_suspicions_clock() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	# Behavior's clock alone, so the two genuinely disagree. In play they disagree whenever the
	# nodes were not built on the same frame; a fixture that advances both in lockstep cannot
	# tell the right subtraction from the wrong one, and the wrong one compiles.
	_behavior.drive_subsystems = false
	_behavior.advance(_config.target_estimate_max_age_s * 5.0)
	_behavior.drive_subsystems = true

	_hunt(player, Vector3(0.0, 0.0, 12.0))

	assert_gt(
		_behavior.clock - _suspicion.clock,
		_config.target_estimate_max_age_s,
		"the two clocks never diverged, so this proves nothing"
	)
	assert_false(
		_hunting().memory.estimate_is_stale,
		"a sighting from this frame read as stale; the wrong clock is being subtracted"
	)


func test_the_sweep_never_writes_belief_itself() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 6.0))
	_place(_estimate())
	var before: int = _suspicion.memory.disconfirmations.size()

	# Standing on the estimate with the bite spent, so chase FAILUREs on arrival and the sweep
	# below it takes the tick.
	_advance(_config.attack_cooldown_s * 0.25)
	_see(player, _estimate())
	_tick()
	assert_eq(_behavior.running_action(), &"search_area", "the fixture never started sweeping")

	assert_eq(
		_suspicion.memory.disconfirmations.size(),
		before,
		"the action wrote a disconfirmation itself instead of letting Perception observe one"
	)


func test_the_tree_never_moves_the_body() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_place(Vector3(0.0, 0.0, -4.0))
	_hunt(player, Vector3(0.0, 0.0, 12.0))
	var at: Vector3 = _body.position

	for _i: int in 30:
		_see(player, Vector3(0.0, 0.0, 12.0))
		_tick()

	assert_eq(_body.position, at, "an action moved the creature instead of commanding navigation")


func test_leaving_the_state_gives_the_chase_goal_back() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 12.0))
	assert_true(_behavior.goal.has_goal())

	_behavior.hfsm.reset_to(CreatureState.State.UNALERTED, _behavior.context)

	assert_false(_behavior.goal.has_goal(), "the chase goal leaked into the next state")


## `attack_window_open` means IN REACH, and it has to stay true between strikes. Menace is the
## pressure of having an alien on top of you; a flag that told the truth only on the single
## frame a bite fires would price a whole encounter at roughly nothing.
func test_the_attack_window_stays_open_between_strikes() -> void:
	var player: Node3D = _player("target")
	_add_navigation()
	_hunt(player, Vector3(0.0, 0.0, 6.0))
	assert_false(
		_behavior.build_report().attack_window_open, "nothing is within reach of a chasing alien"
	)

	_place(_estimate())
	_see(player, _estimate())
	_tick()
	assert_eq(_attacks.size(), 1, "the fixture never landed a strike")

	# Deep inside the cooldown, so the bite branch is definitely closed.
	for _i: int in int(roundf((_config.attack_cooldown_s * 0.5) / TICK)):
		_see(player, _estimate())
		_tick()
	assert_eq(_attacks.size(), 1, "the cooldown is not holding")

	assert_true(
		_behavior.build_report().attack_window_open,
		"the Director is being told the pressure stopped the instant the alien stopped biting"
	)


# ----- helpers -----


## Sightings at `at` until the hunt guard opens. Long enough to clear min_dwell_s twice: a
## sighting also raises a hotspot, and the table checks the investigate row first.
func _hunt(player: Node3D, at: Vector3) -> void:
	_advance(_config.min_dwell_s + 0.1)
	for _i: int in int(roundf((_config.min_dwell_s * 3.0 + 1.0) / TICK)):
		_see(player, at)
		_tick()
		if _state() == CreatureState.State.HUNTING:
			return
	assert_eq(_state(), CreatureState.State.HUNTING, "the fixture never reached HUNTING")


func _hunting() -> HuntingState:
	return _behavior.hfsm.state_of(CreatureState.State.HUNTING) as HuntingState


func _estimate() -> Vector3:
	return _hunting().memory.last_credible_target_position
