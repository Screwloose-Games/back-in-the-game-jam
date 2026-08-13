extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 6: the leap planner and controller (navigation.md section 11, Invariant 4).
##
## SECTION 43'S SCENARIOS D AND E ARE THE HEADLINE. They are already asserted as config
## arithmetic in test_locomotion_profile.gd; here they are asserted through the planner,
## against real candidates, so that the tuning and the code that uses it cannot drift
## apart. A leap system where the numbers are right and the comparison is wrong looks
## exactly like one where nothing is wrong.

const TICK: float = 1.0 / 60.0
## Far enough that no fixture's geometry is in the way by accident.
const OPEN: float = 200.0
## How far off the launch wall the body sits. ABOVE ITS OWN 1.25 m CLEARANCE RADIUS: a
## body centred on the wall face is in penetration, the flight sweep has no trajectory at
## all, and every leap below would be rejected as BLOCKED_FLIGHT for a reason that has
## nothing to do with the leap.
const LAUNCH_STANDOFF: float = 1.5
## And the same at the far end, with room to spare for `leap_grab_reach` to still find the
## wall from the landing point.
const LANDING_STANDOFF: float = 1.3


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


## The launch wall, whose face is at x = 0.
func _launch_wall() -> void:
	_probe.add_solid(AABB(Vector3(-6.0, -20.0, -20.0), Vector3(6.0, 40.0, 40.0)))


## Where the body launches from.
func _origin() -> Vector3:
	return Vector3(LAUNCH_STANDOFF, 0.0, 0.0)


## Where a leap of exactly `distance` metres lands.
func _landing(distance: float) -> Vector3:
	return Vector3(LAUNCH_STANDOFF + distance, 0.0, 0.0)


## Two facing walls, positioned so a leap of exactly `distance` runs between them from a
## valid launch pose to a valid landing pose.
func _leap_gap(distance: float) -> void:
	_launch_wall()
	var far_face: float = _landing(distance).x + LANDING_STANDOFF
	_probe.add_solid(AABB(Vector3(far_face, -20.0, -20.0), Vector3(6.0, 40.0, 40.0)))


func _evaluate(landing: Vector3, crawl: float) -> NavLeapCandidate:
	return NavLeapPlanner.new().evaluate(
		_origin(), Vector3.RIGHT, true, landing, crawl, 0.0, _probe, _config
	)


## Winds a controller all the way up and launches it. Returns it airborne.
func _launched(distance: float) -> LeapController:
	var controller := LeapController.new()
	controller.begin(_evaluate(_landing(distance), 4.0 * distance))
	var body: NavBodyState = _body_state(_origin(), Vector3.RIGHT)
	for _step: int in 120:
		controller.advance(body, TICK, _probe, _config)
	return controller


# ----- section 43 scenarios D and E, through the planner -----


func test_scenario_d_takes_the_leap() -> void:
	_leap_gap(20.0)
	var candidate: NavLeapCandidate = _evaluate(_landing(20.0), 30.0)
	assert_true(
		candidate.accepted, "rejected as %s" % candidate.rejection_name(candidate.rejection)
	)
	assert_lt(candidate.leap_cost, candidate.crawl_cost)


func test_scenario_e_keeps_crawling() -> void:
	_leap_gap(18.0)
	var candidate: NavLeapCandidate = _evaluate(_landing(18.0), 21.0)
	assert_false(candidate.accepted)
	assert_eq(
		candidate.rejection,
		NavLeapCandidate.Rejection.TOO_EXPENSIVE,
		"the leap is perfectly possible; it simply loses to walking"
	)


## Section 11.1 and Scenario H: there is no maximum leap distance anywhere in the model.
func test_a_very_long_clear_leap_is_not_rejected_for_being_long() -> void:
	_leap_gap(120.0)
	var candidate: NavLeapCandidate = _evaluate(_landing(120.0), 400.0)
	assert_true(
		candidate.accepted, "rejected as %s" % candidate.rejection_name(candidate.rejection)
	)


# ----- section 11.2's four requirements -----


func test_an_unattached_body_has_no_launch_pose() -> void:
	_leap_gap(20.0)
	var candidate: NavLeapCandidate = NavLeapPlanner.new().evaluate(
		_origin(), Vector3.RIGHT, false, _landing(20.0), 30.0, 0.0, _probe, _config
	)
	assert_eq(candidate.rejection, NavLeapCandidate.Rejection.NO_LAUNCH_POSE)


func test_launching_into_the_wall_being_held_is_refused() -> void:
	_leap_gap(20.0)
	var candidate: NavLeapCandidate = NavLeapPlanner.new().evaluate(
		_origin(), Vector3.LEFT, true, _landing(20.0), 30.0, 0.0, _probe, _config
	)
	assert_eq(
		candidate.rejection,
		NavLeapCandidate.Rejection.NO_LAUNCH_POSE,
		"the surface normal points away from where the alien is trying to go"
	)


func test_a_blocked_flight_is_refused() -> void:
	_leap_gap(20.0)
	# A pillar across the middle of the gap.
	_probe.add_solid(AABB(Vector3(9.0, -20.0, -4.0), Vector3(2.0, 40.0, 8.0)))
	var candidate: NavLeapCandidate = _evaluate(_landing(20.0), 30.0)
	assert_eq(candidate.rejection, NavLeapCandidate.Rejection.BLOCKED_FLIGHT)


func test_a_leap_into_the_void_has_nothing_to_grab() -> void:
	# Only the launch wall exists; the far side is open space forever.
	_launch_wall()
	var candidate: NavLeapCandidate = _evaluate(Vector3(OPEN, 0.0, 0.0), 400.0)
	assert_eq(
		candidate.rejection,
		NavLeapCandidate.Rejection.NO_GRAB,
		"section 11.1: the alien cannot stop in open space, so it must not aim at it"
	)


func test_a_rejected_candidate_still_records_why_for_the_overlay() -> void:
	_launch_wall()
	var candidate: NavLeapCandidate = _evaluate(Vector3(OPEN, 0.0, 0.0), 400.0)
	assert_eq(candidate.to_dictionary()["rejection"], "no_grab")


# ----- Invariant 4 -----


func test_once_airborne_the_velocity_cannot_be_changed() -> void:
	_leap_gap(20.0)
	var controller: LeapController = _launched(20.0)
	assert_true(controller.is_airborne())

	var body: NavBodyState = _body_state(_origin(), Vector3.RIGHT)
	var launched: Vector3 = controller.advance(body, TICK, _probe, _config).leap_velocity
	# Move the body somewhere else entirely and ask again. Invariant 4 says the answer is
	# identical: there is no steering input, so there is nothing to ignore incorrectly.
	var displaced: NavBodyState = _body_state(Vector3(5.0, 9.0, -7.0), Vector3.BACK)
	var after: Vector3 = controller.advance(displaced, TICK, _probe, _config).leap_velocity
	assert_eq(launched, after, "a leap in flight may not be redirected, at any price")


func test_the_flight_speed_is_the_configured_leap_speed() -> void:
	_leap_gap(20.0)
	var controller: LeapController = _launched(20.0)
	assert_almost_eq(
		(
			controller
			. advance(_body_state(_origin(), Vector3.RIGHT), TICK, _probe, _config)
			. leap_velocity
			. length()
		),
		_profile().leap_speed,
		0.001
	)


# ----- section 40.5 -----


func test_a_flight_blocked_during_the_wind_up_is_abandoned() -> void:
	_leap_gap(20.0)
	var controller := LeapController.new()
	controller.begin(_evaluate(_landing(20.0), 30.0))
	var body: NavBodyState = _body_state(_origin(), Vector3.RIGHT)
	controller.advance(body, TICK, _probe, _config)

	# The world changes under a leap that has not left the ground.
	_probe.add_solid(AABB(Vector3(9.0, -20.0, -20.0), Vector3(2.0, 40.0, 40.0)))
	var command: NavMotionCommand = controller.advance(body, TICK, _probe, _config)
	assert_eq(command.abort, NavMotionCommand.Abort.LEAP_INVALIDATED)
	assert_false(controller.is_busy(), "an abandoned leap must not leave the controller armed")


func test_the_body_does_not_move_during_the_wind_up() -> void:
	_leap_gap(20.0)
	var controller := LeapController.new()
	controller.begin(_evaluate(_landing(20.0), 30.0))
	var command: NavMotionCommand = controller.advance(
		_body_state(_origin(), Vector3.RIGHT), TICK, _probe, _config
	)
	assert_true(command.preparing_leap)
	assert_eq(command.desired_speed, 0.0, "section 11.2.1 wants a held pose, not a run-up")


# ----- section 11.5, Scenario I -----


## Scenario I, set up so the question is meaningful: the alien is flying to a far wall,
## and a ledge comes within reach that is much nearer the place it actually wants to be.
func test_a_useful_wall_within_reach_is_grabbed_mid_flight() -> void:
	_leap_gap(36.0)
	# A ledge beside the flight path. Its face is 1.4 m from the flight line: clear of the
	# body's own 1.25 m radius, so the flight is not blocked, and inside the 1.5 m grab
	# reach, so it can be caught. That narrow band IS section 11.5's situation.
	_probe.add_solid(AABB(Vector3(22.0, 1.4, -20.0), Vector3(6.0, 4.0, 40.0)))
	var controller: LeapController = _launched(36.0)
	var beside: NavBodyState = _body_state(Vector3(24.0, 0.0, 0.0), Vector3.RIGHT)
	var goal := Vector3(25.0, 6.0, 0.0)
	assert_not_null(
		controller.opportunistic_grab(beside, goal, _probe, _config),
		"section 11.5: a surface nearer the goal than the destination came within reach"
	)


func test_a_wall_no_nearer_the_goal_than_the_destination_is_left_alone() -> void:
	_leap_gap(36.0)
	_probe.add_solid(AABB(Vector3(22.0, 1.4, -20.0), Vector3(6.0, 4.0, 40.0)))
	var controller: LeapController = _launched(36.0)
	var beside: NavBodyState = _body_state(Vector3(24.0, 0.0, 0.0), Vector3.RIGHT)
	assert_null(
		controller.opportunistic_grab(beside, _landing(36.0), _probe, _config),
		"grabbing a wall short of where it was already going turns every leap into a hop"
	)
