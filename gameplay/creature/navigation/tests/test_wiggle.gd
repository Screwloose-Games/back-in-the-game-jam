extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 5: squeezing, and section 40.2's refusal to grind.
##
## SECTION 10.3 AND INVARIANT 5 ARE THE SAME ASSERTION SEEN TWICE. There is no
## player-only flag anywhere in this module; a tunnel only the player fits is a tunnel
## narrower than the alien's compressed body, and the answer is NO_FIT. If that ever
## becomes a special case, section 43's Scenarios C and G both quietly stop being tested
## by anything.

const TICK: float = 1.0 / 60.0


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


## A cave with a square bore of `bore` metres through a wall at x = 4.
func _pinch(bore: float) -> void:
	var half: float = 0.5 * bore
	_probe.add_room(AABB(Vector3(-6.0, -6.0, -6.0), Vector3(24.0, 12.0, 12.0)))
	_probe.add_solid(AABB(Vector3(4.0, -6.0, -6.0), Vector3(2.0, 12.0, 6.0 - half)))
	_probe.add_solid(AABB(Vector3(4.0, -6.0, half), Vector3(2.0, 12.0, 6.0 - half)))
	_probe.add_solid(AABB(Vector3(4.0, -6.0, -6.0), Vector3(2.0, 6.0 - half, 12.0)))
	_probe.add_solid(AABB(Vector3(4.0, half, -6.0), Vector3(2.0, 6.0 - half, 12.0)))


## Drives the controller from just outside the pinch, returning the last command.
func _approach(wiggler: WiggleController, steps: int) -> NavMotionCommand:
	var body: NavBodyState = _body_state(Vector3(3.0, 0.0, 0.0), Vector3.RIGHT)
	var command: NavMotionCommand = null
	for _step: int in steps:
		command = wiggler.steer(body, Vector3(12.0, 0.0, 0.0), TICK, _probe, _config)
	return command


# ----- section 10.1: decided by fit, not by edge type -----


func test_squeeze_is_required_exactly_when_the_normal_body_is_the_problem() -> void:
	assert_true(WiggleController.squeeze_required(false, true))
	assert_false(WiggleController.squeeze_required(true, true), "it already fits")
	assert_false(WiggleController.squeeze_required(false, false), "nothing fits; that is NO_FIT")


func test_a_wide_opening_is_not_this_controller_s_business() -> void:
	_pinch(WIDE_CORRIDOR)
	assert_null(
		WiggleController.new().steer(
			_body_state(Vector3(3.0, 0.0, 0.0), Vector3.RIGHT),
			Vector3(12.0, 0.0, 0.0),
			TICK,
			_probe,
			_config
		),
		"returning a command here would squeeze the alien through a doorway it can walk through"
	)


func test_a_tight_opening_starts_a_squeeze() -> void:
	_pinch(TIGHT_CORRIDOR)
	var wiggler := WiggleController.new()
	var command: NavMotionCommand = _approach(wiggler, 1)
	assert_not_null(command)
	assert_eq(command.mode, NavLocomotion.Mode.WIGGLE)
	assert_true(command.squeeze, "the body has to be told to compress")


# ----- section 10.3 / Invariant 5 -----


## SECTION 10.3 IS ABOUT A BODY THAT IS COMMITTED, NOT ONE THAT IS MERELY FACING A WALL.
##
## `_measure_fit` samples a single point one step ahead, and "the point one step that way
## does not fit" is true of every wall the alien ever approaches -- it is the ordinary
## case. An earlier version reported NO_FIT there, which stopped the creature dead in
## front of any rock and denied the crawler, which scores nine alternatives, the chance to
## find one. Observed in the demo prototype: it reached the tunnel mouth, faced the wall
## beside it, and stalled with a COMPLETE route and eight good directions unexamined.
func test_facing_an_impassable_pinch_hands_the_tick_back_rather_than_stopping() -> void:
	_pinch(IMPASSABLE_CORRIDOR)
	assert_null(
		_approach(WiggleController.new(), 1),
		"an uncompressed body has not committed to anything; the crawler gets to try"
	)


## The real section 10.3: already compressed, part-way in, and the passage does not
## continue. There is no third body to try, so this is where a route stops being one.
func test_a_committed_squeeze_that_runs_out_reports_no_fit() -> void:
	# Enter a genuinely tight passage first, so the body is actually compressing.
	_pinch(TIGHT_CORRIDOR)
	var wiggler := WiggleController.new()
	_approach(wiggler, 30)
	assert_gt(wiggler.squeeze_fraction(), 0.0, "fixture must leave the body committed")

	# Now the way ahead closes to less than the compressed body.
	_probe.solids.clear()
	_pinch(IMPASSABLE_CORRIDOR)
	var command: NavMotionCommand = _approach(wiggler, 1)
	assert_true(command.is_stalled())
	assert_eq(
		command.abort,
		NavMotionCommand.Abort.NO_FIT,
		"section 43 Scenarios C and G: the alien determines the route unusable and stops"
	)


## Invariant 5 has no flag behind it anywhere in the module: a player-only tunnel is a
## passage narrower than the alien's compressed body, and that is the whole mechanism.
func test_the_refusal_needs_no_knowledge_that_a_player_exists() -> void:
	_pinch(IMPASSABLE_CORRIDOR)
	var wiggler := WiggleController.new()
	_approach(wiggler, 1)
	assert_false(
		WiggleController.squeeze_required(false, false),
		"nothing fits, so there is nothing to squeeze into -- no player anywhere in the answer"
	)


# ----- the squeeze transition is timed (section 10.2) -----


func test_the_body_does_not_move_while_it_is_still_compressing() -> void:
	_pinch(TIGHT_CORRIDOR)
	var command: NavMotionCommand = _approach(WiggleController.new(), 1)
	assert_eq(
		command.desired_speed,
		0.0,
		"Scenario B is approach, squeeze, wiggle -- not squeeze and wiggle at once"
	)


func test_compression_completes_and_then_the_body_moves() -> void:
	_pinch(TIGHT_CORRIDOR)
	var wiggler := WiggleController.new()
	# squeeze_transition_time is 0.6 s; sixty ticks is a full second.
	var command: NavMotionCommand = _approach(wiggler, 60)
	assert_true(wiggler.is_squeezed(), "the transition must finish rather than stall part-way")
	assert_gt(command.desired_speed, 0.0)
	assert_almost_eq(
		command.desired_speed,
		_config.wiggle_speed,
		0.001,
		"the controller must move at the speed A* charged for the edge, or routing lies"
	)


func test_compression_is_gradual_rather_than_instant() -> void:
	_pinch(TIGHT_CORRIDOR)
	var wiggler := WiggleController.new()
	_approach(wiggler, 1)
	assert_lt(
		wiggler.squeeze_fraction(),
		1.0,
		"an instant squeeze makes squeeze_transition_penalty a charge for nothing"
	)
	assert_gt(wiggler.squeeze_fraction(), 0.0)


func test_a_wiggle_is_substantially_slower_than_a_crawl() -> void:
	assert_lt(
		_config.wiggle_speed,
		0.5 * _profile().crawl_max_speed,
		"section 10.2 wants wiggle visibly deliberate, not marginally slower"
	)


# ----- section 40.2 -----


func test_going_nowhere_for_a_whole_window_is_grinding() -> void:
	var wiggler := WiggleController.new()
	var stuck := Vector3(4.5, 0.0, 0.0)
	assert_false(wiggler.note_progress(stuck, TICK, _profile()), "the first tick starts the window")
	var ground: bool = false
	for _step: int in 200:
		ground = ground or wiggler.note_progress(stuck, TICK, _profile())
	assert_true(ground, "section 40.2: do not merely push against collision indefinitely")


func test_slow_progress_is_not_grinding() -> void:
	var wiggler := WiggleController.new()
	var at := Vector3.ZERO
	wiggler.note_progress(at, TICK, _profile())
	var ground: bool = false
	for step: int in 200:
		# A wiggle covers 1.2 m/s, so a tick is 2 cm. Slow is the whole point of the mode.
		at = Vector3(_config.wiggle_speed * TICK * float(step + 1), 0.0, 0.0)
		ground = ground or wiggler.note_progress(at, TICK, _profile())
	assert_false(ground, "a wiggle is meant to be slow; slow must not read as stuck")


func test_grinding_is_not_reported_before_the_window_has_elapsed() -> void:
	var wiggler := WiggleController.new()
	var stuck := Vector3(4.5, 0.0, 0.0)
	wiggler.note_progress(stuck, TICK, _profile())
	# grind_window is 1.5 s; thirty ticks is half a second.
	for _step: int in 30:
		assert_false(
			wiggler.note_progress(stuck, TICK, _profile()),
			"aborting early turns every momentary snag into a failed traversal"
		)


func test_resetting_forgets_the_previous_crevice() -> void:
	var wiggler := WiggleController.new()
	var stuck := Vector3(4.5, 0.0, 0.0)
	for _step: int in 120:
		wiggler.note_progress(stuck, TICK, _profile())
	wiggler.reset_progress()
	assert_false(
		wiggler.note_progress(stuck, TICK, _profile()),
		"a fresh squeeze is judged on its own progress, not the last one's"
	)
