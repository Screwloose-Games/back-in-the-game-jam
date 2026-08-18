extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Slip recovery and section 40's progress watchdog.
##
## THE POSE THE ALIEN COULD NOT SURVIVE. A body with nothing inside `crawl_surface_reach`
## refused every mode and stalled NO_SURFACE; a stall is zero speed, and zero speed cannot
## move the body out of the pose that caused the stall. It shipped twice -- once wedged
## against a ceiling inside its own planning envelope, once floating mid-room with all ten
## rays missing -- and both times the alien held a COMPLETE route and reported a plausible
## mode for the rest of the run.
##
## `test_only_airborne_may_be_unsupported` is Invariant 3 written as a test: an unsupported
## body is either mid-leap or it has slipped, and there is no third reading. The distinction
## between escaping an illegal pose and travelling through open space is the whole invariant
## and is exactly the kind of thing a later refactor softens away.


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


# ----- Invariant 3 -----


## THE INVARIANT, AS A TEST, so nobody later softens recovery into a movement mode. Section
## 11 is the only place the alien may be in open space; every other unsupported reading is
## a slip to escape, not a way to travel.
func test_only_airborne_may_be_unsupported() -> void:
	var nothing: NavSurfaceReading = _reading_of([])
	assert_false(nothing.has_surface(), "the fixture must actually be unsupported")
	assert_true(
		NavLocalPlanner.is_slipped(nothing, false),
		"unsupported and not airborne is a slip, whatever mode the body believes it is in"
	)
	assert_false(
		NavLocalPlanner.is_slipped(nothing, true),
		"unsupported and airborne is section 11, and the only legal way to be there"
	)
	var held: NavSurfaceReading = _reading_of([[Vector3.DOWN, 1.5]])
	assert_false(NavLocalPlanner.is_slipped(held, false), "a body holding a floor has not slipped")
	assert_false(NavLocalPlanner.is_slipped(held, true))


## The recovery fan reaches past the ordinary one, or it re-asks the question that just
## came back empty.
func test_the_recovery_fan_finds_a_floor_the_ordinary_fan_cannot() -> void:
	var profile: LocomotionProfile = _profile()
	_flat_floor()
	var high: float = profile.crawl_surface_reach + 4.0
	var at := Vector3(0.0, high, 0.0)
	var field := NavSurfaceField.new()
	assert_false(
		field.sample(at, _probe, profile, _config.world_mask).has_surface(),
		"the ordinary fan must find nothing, or this test proves nothing"
	)
	var found: NavSurfaceSample = field.reacquire(at, _probe, profile, _config.world_mask)
	assert_not_null(found, "the recovery fan must find the floor")
	assert_almost_eq(found.direction.dot(Vector3.DOWN), 1.0, 0.001)


## The whole failure, end to end: the pose that used to be terminal now produces motion.
func test_a_slipped_body_is_given_motion_rather_than_a_stall() -> void:
	var profile: LocomotionProfile = _profile()
	_flat_floor()
	var high: float = profile.crawl_surface_reach + 4.0
	var body: NavBodyState = _body_state(Vector3(0.0, high, 0.0), Vector3.RIGHT)
	var planner := NavLocalPlanner.new()
	var command: NavMotionCommand = planner.plan_next_motion(body, null, 0.05, _probe, _config)
	assert_false(command.is_stalled(), "a slipped body used to stall here, forever")
	assert_true(command.recovering, "and the command must say that is what it is doing")
	assert_gt(command.desired_speed, 0.0, "a zero-speed answer never leaves the pose")
	assert_almost_eq(command.desired_direction.dot(Vector3.DOWN), 1.0, 0.001)


# ----- section 40's backstop -----


func test_a_body_covering_ground_never_trips_the_watchdog() -> void:
	var monitor := NavProgressMonitor.new()
	var at := Vector3.ZERO
	for tick: int in 200:
		at += Vector3(0.05, 0.0, 0.0)
		assert_false(monitor.note(at, 0.05, true, _config), "tick %d" % tick)
	assert_eq(monitor.trips, 0)


func test_a_body_going_nowhere_trips_once_per_window() -> void:
	var monitor := NavProgressMonitor.new()
	var at := Vector3.ZERO
	var trips: int = 0
	# Two whole windows, plus the first tick that only starts the clock.
	var ticks: int = int(2.0 * _config.progress_window / 0.05) + 1
	for tick: int in ticks:
		if monitor.note(at, 0.05, true, _config):
			trips += 1
	assert_eq(trips, 2, "one report per window, not one per tick after the first")
	assert_eq(monitor.trips, 2)


## Section 29 has the alien stop, orient and look for as long as an inspection takes, and
## Scenario B has it hold still while it compresses. A watchdog tuned long enough to
## outlast every legitimate pause would eventually be tuned long enough to miss the
## failures, so deliberate stillness is excluded outright instead.
func test_a_deliberate_hold_does_not_trip_the_watchdog() -> void:
	var monitor := NavProgressMonitor.new()
	var at := Vector3.ZERO
	var ticks: int = int(4.0 * _config.progress_window / 0.05)
	for tick: int in ticks:
		assert_false(monitor.note(at, 0.05, false, _config), "tick %d" % tick)
	assert_eq(monitor.trips, 0)


## And the seconds spent holding still must not be banked against the seconds after it
## starts again -- otherwise the tick an inspection ends is the tick the alien is declared
## wedged.
func test_a_hold_forgets_the_window_rather_than_pausing_it() -> void:
	var monitor := NavProgressMonitor.new()
	var at := Vector3.ZERO
	var ticks: int = int(0.9 * _config.progress_window / 0.05)
	for _tick: int in ticks:
		monitor.note(at, 0.05, true, _config)
	monitor.note(at, 0.05, false, _config)
	# One tick short of a fresh window, from a clock that had almost run out.
	for _tick: int in ticks:
		assert_false(monitor.note(at, 0.05, true, _config))
	assert_eq(monitor.trips, 0)
