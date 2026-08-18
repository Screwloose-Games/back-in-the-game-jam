extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## The tunnel-mouth lurk: what happens when the target goes somewhere the alien cannot fit.
##
## NOTHING HERE IS FLAGGED AS IMPASSABLE, and that is the claim the whole file is about. The
## fixture drops a slab of rock into the room; the bake fills the far side with perfectly good
## nodes and validates no edge to any of them; the route comes back PARTIAL and stops at the
## near face. behavior.md section 29's "the target was recently near a known non-creature
## passable tunnel" is therefore answered by the creature's own navigation graph, which is the
## only thing it legitimately knows -- and the answer covers every gap too tight for it rather
## than the ones somebody remembered to tag.
##
## THE LOOP THIS SUITE EXISTS TO CATCH is the alien that hammers the wall. fsm.md orders the
## selector chase-before-wait and gives chase no failure clause for a route that stops short,
## so read literally the lurk branch is dead code: while there is an estimate at all, chase
## claims the tick, walks to the near face, and reports RUNNING against a route that can never
## complete. The player is safe either way -- which is exactly why nobody would notice. The
## alien would simply never do the one thing this beat exists for.
##
## The second failure it catches is a wait the player can count. A gap with a known safe
## interval is not a gamble, and a fixed timer is the easiest thing in the world to write.

## Beyond the slab, in a part of the room the bake fills with nodes and reaches none of.
const FAR_SIDE := Vector3(20.0, 0.0, 0.0)
## Well inside the near half, so a route to it completes.
const NEAR_SIDE := Vector3(0.0, 0.0, 8.0)


## THE ASSERTION THIS FILE EXISTS FOR. Chase must yield the tick to the wait.
func test_the_creature_waits_at_the_mouth_rather_than_running_at_the_rock() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, FAR_SIDE)

	assert_true(_hunting().memory.beyond_reach, "the fixture never produced an unreachable target")
	assert_eq(
		_behavior.running_action(),
		&"lurk_at_tunnel_mouth",
		"the alien is still running at a wall it can never get through"
	)


## The three-part proof from verify_navigation_runtime.gd, and the middle part is the one
## people skip: a cave whose far side simply had no nodes would pass the first check for
## entirely the wrong reason, and would keep passing it if candidate rejection broke outright.
func test_the_far_side_is_real_and_reachable_from_nowhere() -> void:
	var nav: CreatureNavigation = _add_navigation([DIVIDER])
	var graph: NavGraph = nav.graph

	var near: int = -1
	var far: Array = []
	for id: Variant in graph.node_ids():
		var at: Vector3 = graph.node_at(id).position
		if at.x > DIVIDER.end.x:
			far.append(id)
		elif near < 0 and at.x < DIVIDER.position.x:
			near = id
	assert_gt(far.size(), 0, "the far side has no nodes, so nothing below proves anything")
	assert_gt(near, -1, "the near side has no nodes either")

	var reachable: Dictionary = graph.reachable_from(near)
	var leaked: int = 0
	for id: Variant in far:
		if reachable.has(id):
			leaked += 1
	assert_eq(leaked, 0, "the graph found a way through solid rock")

	var route: NavRoute = nav.plan_route(Vector3.ZERO, FAR_SIDE)
	assert_eq(route.status, NavRoute.Status.PARTIAL, "a route that stops short is not a failure")
	assert_lt(
		route.anchors[-1].x, DIVIDER.position.x, "the partial route ends inside the rock or past it"
	)


## The standoff is not tuned, computed or configured: the action asks for the estimate itself
## and navigation stops the alien at the nearest useful reachable place.
func test_the_lurk_asks_for_the_estimate_and_lets_navigation_stop_it_short() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, FAR_SIDE)

	assert_eq(
		_behavior.goal.holder().node_name, &"lurk_at_tunnel_mouth", "the wrong leaf owns the goal"
	)
	assert_lt(
		_behavior.goal.committed().distance_to(_estimate()),
		_config.goal_refresh_m,
		"the lurk invented a standoff position instead of asking for the target"
	)
	assert_true(_behavior.goal.is_partial(), "the route did not come back partial")


## A fixed wait is something the player counts, and a gap with a known safe interval stops
## being a gamble. `invariant_failures` rejects a range with no width; this asserts the action
## actually draws from it rather than picking a constant inside it.
func test_the_wait_is_a_different_length_each_time() -> void:
	var first: float = _lurk_duration(7)
	var second: float = _lurk_duration(4242)

	assert_gt(first, 0.0, "no lurk deadline was ever set")
	assert_ne(first, second, "the lurk is a fixed timer; a player would learn it in one session")
	assert_between(first, _config.lurk_min_s, _config.lurk_max_s, "the draw left its own range")
	assert_between(second, _config.lurk_min_s, _config.lurk_max_s, "the draw left its own range")


func test_the_lurk_gives_way_to_the_chase_when_the_target_comes_back() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, FAR_SIDE)
	assert_eq(_behavior.running_action(), &"lurk_at_tunnel_mouth", "the fixture never lurked")

	for _i: int in 30:
		_see(player, NEAR_SIDE)
		_tick()

	assert_false(_hunting().memory.beyond_reach, "the estimate came back and the latch did not")
	assert_eq(
		_behavior.running_action(),
		&"chase_target",
		"the alien is still waiting outside a gap the target has already left"
	)


## bt_node.gd and test_bt_abort.gd both cite this exact pair. The outgoing leaf's abort runs
## AFTER the incoming leaf has asked for its goal, so without BehaviorGoal's owner check the
## chase's release wipes the lurk's fresh request and the alien holds a route to nowhere.
func test_the_chase_hands_the_goal_to_the_lurk_rather_than_dropping_it() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, NEAR_SIDE)
	assert_eq(_behavior.running_action(), &"chase_target", "the fixture never started chasing")

	for _i: int in 30:
		_see(player, FAR_SIDE)
		_tick()

	assert_true(_behavior.goal.has_goal(), "the outgoing abort wiped the incoming goal")
	assert_eq(
		_behavior.goal.holder().node_name,
		&"lurk_at_tunnel_mouth",
		"the chase is still holding a goal it stopped using"
	)


## behavior.md section 29: a gap the alien cannot follow you through protects you PHYSICALLY
## without clearing the creature's suspicion. The hunt has to end by starving, never because
## the alien talked itself out of believing you were there.
func test_hiding_does_not_clear_the_creatures_belief() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, FAR_SIDE)
	var believed: float = _suspicion.get_suspicion_near(_estimate(), _config.hunt_sustain_radius)
	var disconfirmations: int = _suspicion.memory.disconfirmations.size()

	# Long enough for several lurk draws, with nothing new arriving.
	_advance(_config.lurk_max_s * 2.0)

	assert_eq(
		_suspicion.memory.disconfirmations.size(),
		disconfirmations,
		"the alien cleared a region it never actually reached"
	)
	assert_gt(believed, 0.0, "the fixture never established a belief to protect")


func test_the_hunt_ends_by_starving_rather_than_by_giving_up_on_the_place() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_hunt(player, FAR_SIDE)

	# No further evidence. Hunt sustain needs BOTH halves to fail -- no candidate above the
	# threshold for a continuous grace period, AND no unresolved suspicion left within
	# `hunt_sustain_radius` of the estimate -- and the second one is the slow half, because
	# nothing the alien can do disconfirms a region it cannot walk into. Only the clock can
	# end this, which is the point. Big steps: the decay is a function of elapsed time, and
	# four minutes of physics ticks is four minutes nobody gets back.
	for _i: int in 8:
		_behavior.advance(30.0)

	assert_has(_reasons(), &"lost", "the hunt ended for some reason other than running dry")
	assert_ne(_state(), CreatureState.State.HUNTING, "the alien is still waiting after two minutes")


func test_the_lurk_never_moves_the_body() -> void:
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_place(Vector3(0.0, 0.0, 4.0))
	_hunt(player, FAR_SIDE)
	var at: Vector3 = _body.position

	_advance(2.0)

	assert_eq(_body.position, at, "an action moved the creature instead of commanding navigation")


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


## Runs one lurk on a pinned seed and reports how long it was going to last. The seed is
## assigned after the first tick, which is where CreatureBehavior sets it from `behavior_seed`.
func _lurk_duration(seed_value: int) -> float:
	before_each()
	var player: Node3D = _player("target")
	_add_navigation([DIVIDER])
	_behavior.context.rng.seed = seed_value
	_hunt(player, FAR_SIDE)
	assert_eq(_behavior.running_action(), &"lurk_at_tunnel_mouth", "the fixture never lurked")
	return _hunting().memory.lurk_until - _behavior.clock


func _hunting() -> HuntingState:
	return _behavior.hfsm.state_of(CreatureState.State.HUNTING) as HuntingState


func _estimate() -> Vector3:
	return _hunting().memory.last_credible_target_position
