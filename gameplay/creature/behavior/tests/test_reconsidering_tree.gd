extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## Giving up on a lead the creature cannot reach, and the loop that made it necessary.
##
## THE BUG THIS SUITE PINS is an alien that hammers a wall for the rest of the session. A
## hotspot on the far side of rock produces a PARTIAL route, and a partial route is
## deliberately NOT a failure -- it finishes, at the near face, so `is_arrived` answers yes.
## The tree then searches the wrong place, the search disconfirms the wrong place, the lead
## stays exactly as hot as it was, and `investigate_location` re-commands the goal every tick
## the search cooldown is closed. Nothing errors. Nothing reaches the log. The alien simply
## visits a wall forever, flipping between `search_area` and `investigate_location`.
##
## `investigate_timeout_s` does not save it: that row drops to UNALERTED without writing the
## lead off, and UNALERTED walks straight back in on the next tick, because lead selection
## takes the strongest board entry and has no memory of having just failed on it. It converts
## a one-second loop into a forty-five-second one.
##
## `_crawl` IS THE HALF OF THIS FIXTURE THAT HAD TO BE BUILT. `behavior_test_case` never moves
## the body -- every other suite asserts about commands rather than about travel -- and a body
## that never moves has by definition stopped closing on its goal, so without a stand-in motor
## every case here passes for the wrong reason and the reachable control cannot exist at all.
## Following the ROUTE ANCHOR rather than the goal is what makes it faithful: the test body has
## no collider, so walking at the goal would take it straight through the divider.

## Where the creature starts. Near the slab, so a noise on the far side is still audible.
const START := Vector3(4.0, 0.0, 0.0)
## Beyond the slab. The bake fills the far side with nodes and validates no edge to any of
## them, so a route there stops at the near face -- see test_unreachable_target.gd.
const FAR_SIDE := Vector3(18.0, 0.0, 0.0)
## Same side, so a route completes and the creature genuinely arrives.
const NEAR_SIDE := Vector3(0.0, 0.0, 10.0)
## Stand-in for the motor, in m/s. Comfortably faster than the distances here need.
const CRAWL_SPEED: float = 8.0

## Where `_hold` and `_crawl` keep shouting. Captured by the `_hear` override below, so a test
## names the place once and the noise goes on coming from it.
var _last_noise: Vector3 = Vector3.ZERO


## THE ASSERTION THIS FILE EXISTS FOR.
func test_an_approach_that_gets_nowhere_gives_up() -> void:
	_investigate(FAR_SIDE)

	_crawl(_config.give_up_s + 2.0)

	assert_eq(_state(), CreatureState.State.RECONSIDERING, "the alien never stopped trying")
	assert_has(_reasons(), &"futile", "the give-up row did not fire")


## The control, and the one that stops this becoming an alien that abandons everything.
## Arrival is exactly where route distance is supposed to stop falling.
func test_a_lead_the_creature_reaches_is_not_given_up_on() -> void:
	_investigate(NEAR_SIDE)

	_crawl(_config.give_up_s + 3.0)

	assert_does_not_have(_reasons(), &"futile", "a reachable lead was written off as futile")
	assert_ne(_state(), CreatureState.State.RECONSIDERING)


## "Idle, not walk." The outgoing tree's abort released the goal and nothing in here takes
## another, so the leash marker parks on the body and the creature genuinely holds still.
func test_reconsidering_holds_no_goal() -> void:
	_give_up()

	assert_false(_behavior.goal.has_goal(), "the alien is still being told to walk somewhere")
	assert_eq(_behavior.running_action(), &"reconsider")


func test_reconsidering_goes_back_to_wandering() -> void:
	_give_up()

	_hold(_config.reconsider_dwell_s + 1.0)

	assert_eq(_state(), CreatureState.State.UNALERTED)
	assert_has(_reasons(), &"reconsidered")


## THE REGRESSION. Before `mark_unreachable` the alien re-selected the same unreachable lead on
## the tick after it gave up, because the board still offered it and nothing remembered.
func test_the_abandoned_lead_is_not_taken_again() -> void:
	_give_up()
	_hold(_config.reconsider_dwell_s + 1.0)
	assert_eq(_state(), CreatureState.State.UNALERTED, "the fixture never finished reconsidering")

	# Still shouting from the same place, so the hotspot is as alive as it ever was.
	_crawl(8.0)

	assert_eq(
		_state(),
		CreatureState.State.UNALERTED,
		"the alien walked straight back at the lead it just gave up on"
	)


## The belief itself is untouched. `mark_unreachable` is a claim about the creature, not about
## the world -- it stops the place being OFFERED, and changes nothing about how afraid of it
## the alien is. Hunt sustain and the Director both read the unfiltered numbers.
func test_giving_up_does_not_lower_the_belief() -> void:
	_give_up()

	assert_gt(
		_suspicion.get_suspicion_near(_last_noise, 14.0),
		0.0,
		"the place stopped reading as suspicious, which is a claim nobody checked"
	)
	assert_gt(_suspicion.get_hotspots().size(), 0, "the hotspot itself was dropped")


## A person beats standing around. The creature stopped walking at a PLACE it could not reach;
## someone it can see is a different question entirely.
func test_a_credible_player_interrupts_reconsidering() -> void:
	_give_up()

	var player: Node3D = _player("target")
	for _i: int in 600:
		_see(player, _body.position + Vector3(0.0, 0.0, 4.0))
		_tick()
		if _state() == CreatureState.State.HUNTING:
			return
	assert_eq(_state(), CreatureState.State.HUNTING, "a visible player did not break the sulk")


# ----- fixture -----


## Gets the creature into INVESTIGATING with a lead at `at`, on the far side of the divider.
##
## Repeats the noise rather than trusting one: hearing falls off with distance, and a single
## shout from beyond the slab lands under `investigate_threshold`.
func _investigate(at: Vector3) -> void:
	_add_navigation([DIVIDER])
	_place(START)
	_advance(_config.min_dwell_s + 0.1)
	for _i: int in 600:
		_hear(at)
		_tick()
		if _state() == CreatureState.State.INVESTIGATING:
			return
	assert_eq(_state(), CreatureState.State.INVESTIGATING, "the fixture never started looking")


## Investigate the unreachable lead until the creature gives up on it.
func _give_up() -> void:
	_investigate(FAR_SIDE)
	_crawl(_config.give_up_s + 2.0)
	assert_eq(_state(), CreatureState.State.RECONSIDERING, "the fixture never reconsidered")


## Time passing while the body follows its route and the noise goes on. The noise matters as
## much as the movement: without it the lead decays and the state ends for the wrong reason.
func _crawl(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_step_body()
		_hear(_last_noise)
		_tick()


## The same, standing still. For RECONSIDERING, where there is no route to follow.
func _hold(seconds: float) -> void:
	for _i: int in int(roundf(seconds / TICK)):
		_hear(_last_noise)
		_tick()


## One tick of stand-in motor. The ROUTE ANCHOR, never the goal -- see the class docstring.
func _step_body() -> void:
	if _navigation == null or _navigation.follower == null:
		return
	if not _navigation.follower.has_route():
		return
	var anchor: Vector3 = _navigation.follower.current_anchor()
	_body.position = _body.position.move_toward(anchor, CRAWL_SPEED * TICK)


func _hear(at: Vector3, loudness: float = 1.0, category: StringName = &"drill") -> void:
	_last_noise = at
	super(at, loudness, category)
