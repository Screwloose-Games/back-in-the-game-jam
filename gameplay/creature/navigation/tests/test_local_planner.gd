extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Section 20's mode selection, and the dwell timer that makes it watchable.
##
## THE FLICKER TEST IS THE ONE THAT MATTERS. Every other assertion here fails loudly if
## the planner breaks. A mode that changes four times a second while the alien makes
## perfectly good progress fails nothing at all -- the route completes, no test notices,
## and the only symptom is an animation system being asked to blend crawl into swim and
## back before either has started.

const TICK: float = 1.0 / 60.0


func _planner_for() -> NavLocalPlanner:
	return NavLocalPlanner.new()


## Ticks the planner `count` times from a fixed pose, returning every mode it chose.
func _modes_over(planner: NavLocalPlanner, at: Vector3, count: int) -> Array[String]:
	var seen: Array[String] = []
	for _step: int in count:
		planner.plan_next_motion(_body_state(at, Vector3.RIGHT), null, TICK, _probe, _config)
		seen.append(NavLocomotion.mode_name(planner.mode()))
	return seen


func test_an_open_floor_produces_a_crawl() -> void:
	_flat_floor()
	var planner: NavLocalPlanner = _planner_for()
	var command: NavMotionCommand = planner.plan_next_motion(
		_body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT), null, TICK, _probe, _config
	)
	assert_eq(planner.mode(), NavLocomotion.Mode.SURFACE_CRAWL)
	assert_eq(command.mode, NavLocomotion.Mode.SURFACE_CRAWL)
	assert_false(command.is_stalled())


func test_a_bore_produces_a_swim_on_the_very_first_tick() -> void:
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var planner: NavLocalPlanner = _planner_for()
	planner.plan_next_motion(_body_state(Vector3.ZERO, Vector3.RIGHT), null, TICK, _probe, _config)
	assert_eq(
		planner.mode(),
		NavLocomotion.Mode.TUNNEL_SWIM,
		"an alien that starts inside a tunnel must not crawl for the dwell time first"
	)


## Section 9.3's thresholds plus the dwell timer, together, against a body that is not
## moving: the reading is identical every tick, so the mode must be too.
func test_a_steady_pose_never_changes_mode() -> void:
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var planner: NavLocalPlanner = _planner_for()
	var seen: Array[String] = _modes_over(planner, Vector3.ZERO, 30)
	for mode: String in seen:
		assert_eq(mode, seen[0], "the geometry did not change, so neither may the posture")


## THE FLICKER TEST. A mode that has just changed may not change straight back, however
## the reading moves -- which is the situation at every tunnel mouth, where the body is
## briefly enclosed and then briefly not.
##
## The dwell clock starts on a CHANGE, not on the first tick. An alien that has been
## crawling since it was created has no continuity to protect, so its first transition is
## free; it is the second one, hard on the heels of the first, that this forbids.
func test_a_mode_change_is_followed_by_a_quiet_period() -> void:
	_config.locomotion_profile.mode_dwell_time = 0.5
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var planner: NavLocalPlanner = _planner_for()
	planner.plan_next_motion(_body_state(Vector3.ZERO, Vector3.RIGHT), null, TICK, _probe, _config)
	assert_eq(planner.mode(), NavLocomotion.Mode.TUNNEL_SWIM, "entering the bore is the change")

	# Out into the open, two ticks later -- well inside the half-second dwell.
	_probe.solids.clear()
	_flat_floor()
	_modes_over(planner, Vector3(0.0, FLOOR_STANDOFF, 0.0), 2)
	assert_eq(
		planner.mode(),
		NavLocomotion.Mode.TUNNEL_SWIM,
		"changing back inside the dwell period is exactly the flicker this prevents"
	)


func test_the_quiet_period_expires_rather_than_latching() -> void:
	_config.locomotion_profile.mode_dwell_time = 0.1
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var planner: NavLocalPlanner = _planner_for()
	planner.plan_next_motion(_body_state(Vector3.ZERO, Vector3.RIGHT), null, TICK, _probe, _config)
	assert_eq(planner.mode(), NavLocomotion.Mode.TUNNEL_SWIM)

	_probe.solids.clear()
	_flat_floor()
	# Twenty ticks is a third of a second: past the dwell, so the mode may follow again.
	_modes_over(planner, Vector3(0.0, FLOOR_STANDOFF, 0.0), 20)
	assert_eq(
		planner.mode(),
		NavLocomotion.Mode.SURFACE_CRAWL,
		"a dwell timer that never lets go is a mode the alien can never leave"
	)


## Section 8.2 with nowhere to fall back to. The planner must say so rather than emit a
## direction, because a direction here is an alien crossing open space (Invariant 3).
func test_nothing_within_reach_stalls_with_a_reason() -> void:
	var planner: NavLocalPlanner = _planner_for()
	var command: NavMotionCommand = planner.plan_next_motion(
		_body_state(Vector3(0.0, 500.0, 0.0), Vector3.RIGHT), null, TICK, _probe, _config
	)
	assert_true(command.is_stalled())
	assert_eq(command.abort, NavMotionCommand.Abort.NO_SURFACE)
	assert_eq(command.desired_speed, 0.0, "a stall that still asks for speed is not a stall")


func test_a_stall_is_never_null() -> void:
	var planner: NavLocalPlanner = _planner_for()
	assert_not_null(
		planner.plan_next_motion(
			_body_state(Vector3(0.0, 500.0, 0.0)), null, TICK, _probe, _config
		),
		"section 20 returns a command; the caller should not have to null-check every tick"
	)


func test_the_reading_taken_this_tick_is_kept_for_the_overlay() -> void:
	_flat_floor()
	var planner: NavLocalPlanner = _planner_for()
	planner.plan_next_motion(
		_body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT), null, TICK, _probe, _config
	)
	assert_not_null(planner.last_reading())
	assert_true(planner.last_reading().has_surface())
	assert_true(planner.debug_state().has("mode"))


## The planner reads the anchor as a heading, so a route is optional: a body with no route
## still gets a well-formed command rather than an error.
func test_a_body_with_no_route_still_produces_a_command() -> void:
	_flat_floor()
	var command: NavMotionCommand = _planner_for().plan_next_motion(
		_body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT), null, TICK, _probe, _config
	)
	assert_not_null(command)


func test_resetting_the_mode_lets_the_next_tick_choose_freely() -> void:
	_config.locomotion_profile.mode_dwell_time = 10.0
	_flat_floor()
	var planner: NavLocalPlanner = _planner_for()
	planner.plan_next_motion(
		_body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT), null, TICK, _probe, _config
	)

	_probe.solids.clear()
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	planner.reset_mode()
	planner.plan_next_motion(_body_state(Vector3.ZERO, Vector3.RIGHT), null, TICK, _probe, _config)
	assert_eq(
		planner.mode(),
		NavLocomotion.Mode.TUNNEL_SWIM,
		"a replan means continuity is no longer worth protecting"
	)
