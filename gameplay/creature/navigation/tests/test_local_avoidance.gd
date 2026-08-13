extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Local avoidance and surface adhesion (navigation.md sections 8.1, 9.2, 21).
##
## THE FOUR THINGS THAT LOOKED LIKE AVOIDANCE AND WERE NOT. `collision_penalty` was scored
## only after a swept cast had already failed, so it never influenced a choice; `medial`
## centres a body without any opinion about the wall it is angling at; the swimmer had one
## candidate direction; the crawl fan is an arc, so an obstacle needing a wider turn had no
## candidate at all. Each of those is asserted below in the form that would have caught it.
##
## Slip recovery and the section 40 watchdog are the other half of the same work, and live
## in `test_slip_recovery.gd`.


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


# ----- section 21's sixth term, which used to do nothing -----


func test_a_direction_with_nothing_ahead_is_risk_free() -> void:
	var reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, 1.0]])
	assert_eq(NavAvoidance.risk(Vector3.RIGHT, reading, _profile().avoid_margin), 0.0)


## A wall the body is moving AWAY from is not a collision risk, and charging for it is how
## a creature refuses to leave the surface it is standing on.
func test_a_surface_behind_the_heading_is_not_charged_for() -> void:
	var reading: NavSurfaceReading = _reading_of([[Vector3.LEFT, 0.5]])
	assert_eq(NavAvoidance.risk(Vector3.RIGHT, reading, _profile().avoid_margin), 0.0)


func test_risk_rises_as_the_wall_gets_closer() -> void:
	var margin: float = _profile().avoid_margin
	var far: float = NavAvoidance.risk(
		Vector3.RIGHT, _reading_of([[Vector3.RIGHT, margin * 0.9]]), margin
	)
	var near: float = NavAvoidance.risk(
		Vector3.RIGHT, _reading_of([[Vector3.RIGHT, margin * 0.1]]), margin
	)
	assert_lt(far, near, "a wall 10%% of the margin away must score above one at 90%%")
	assert_almost_eq(near, 0.9, 0.001)


## The MAXIMUM over samples, not the sum. A body in the middle of a corridor has walls on
## both sides and is in no danger from either; summing would make the safest place in a
## tunnel score as the most dangerous, and the swimmer would refuse to use tunnels.
func test_two_opposing_walls_do_not_add_up() -> void:
	var margin: float = _profile().avoid_margin
	var corridor: NavSurfaceReading = _reading_of(
		[[Vector3.LEFT, margin * 0.5], [Vector3.RIGHT, margin * 0.5]]
	)
	var one_wall: NavSurfaceReading = _reading_of([[Vector3.RIGHT, margin * 0.5]])
	assert_almost_eq(
		NavAvoidance.risk(Vector3.RIGHT, corridor, margin),
		NavAvoidance.risk(Vector3.RIGHT, one_wall, margin),
		0.001
	)


## The assertion that would have caught the vestigial term: with a wall on one side, the
## crawler's winner must change. Scoring after the cast could never do this.
func test_collision_risk_changes_which_direction_the_crawler_picks() -> void:
	_flat_floor()
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var goal := Vector3(6.0, FLOOR_STANDOFF, 0.0)
	var crawler := SurfaceCrawlController.new()

	var clear_reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, FLOOR_STANDOFF]])
	var open: NavMotionCommand = crawler.steer(body, goal, clear_reading, 0.1, _probe, _config)
	assert_not_null(open, "an open floor with the goal ahead must produce a command")

	# The same floor, plus a wall to the body's right -- which is the way the goal lies.
	# Nothing else about the situation changes.
	#
	# THE WALL MUST STAY FURTHER THAN THE FLOOR, and getting that wrong is instructive: a
	# nearer wall becomes `dominant_normal`, the crawler's tangent plane rotates to the wall's
	# face, and the goal is then straight out of the surface -- a legitimate refusal, and a
	# completely different question from the one this test is asking.
	var walled: NavSurfaceReading = _reading_of(
		[[Vector3.DOWN, FLOOR_STANDOFF], [Vector3.RIGHT, FLOOR_STANDOFF + 0.1]]
	)
	var avoided: NavMotionCommand = crawler.steer(body, goal, walled, 0.1, _probe, _config)
	assert_not_null(avoided, "the crawler must still find somewhere to go")
	assert_lt(
		avoided.desired_direction.dot(Vector3.RIGHT),
		open.desired_direction.dot(Vector3.RIGHT),
		"a wall in the goal direction must bend the chosen heading away from it"
	)


# ----- steer_clear: what medial could not say -----


func test_steer_clear_leaves_a_clear_heading_alone() -> void:
	var reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, 1.0]])
	var steered: Vector3 = NavAvoidance.steer_clear(
		Vector3.RIGHT, reading, _profile().avoid_margin, 1.0
	)
	assert_almost_eq(steered.dot(Vector3.RIGHT), 1.0, 0.001)


func test_steer_clear_turns_away_from_a_wall_it_is_angling_at() -> void:
	var margin: float = _profile().avoid_margin
	var reading: NavSurfaceReading = _reading_of([[Vector3.RIGHT, margin * 0.2]])
	var steered: Vector3 = NavAvoidance.steer_clear(
		Vector3(1.0, 0.0, 1.0).normalized(), reading, margin, 1.0
	)
	assert_lt(
		steered.dot(Vector3.RIGHT),
		Vector3(1.0, 0.0, 1.0).normalized().dot(Vector3.RIGHT),
		"the component heading into the wall must shrink"
	)


## The knob the swimmer's retries turn. Without a monotone response, asking again more
## firmly would produce the same refused direction three times.
func test_more_strength_turns_further() -> void:
	var margin: float = _profile().avoid_margin
	var reading: NavSurfaceReading = _reading_of([[Vector3.RIGHT, margin * 0.2]])
	var wanted: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
	var gentle: Vector3 = NavAvoidance.steer_clear(wanted, reading, margin, 1.0)
	var firm: Vector3 = NavAvoidance.steer_clear(wanted, reading, margin, 3.0)
	assert_lt(firm.dot(Vector3.RIGHT), gentle.dot(Vector3.RIGHT))


# ----- section 8.1's adhesion -----


func test_adhesion_is_zero_within_the_hold_distance() -> void:
	var profile: LocomotionProfile = _profile()
	var reading: NavSurfaceReading = _reading_of(
		[[Vector3.DOWN, profile.crawl_hold_distance - 0.1]]
	)
	assert_eq(
		NavAvoidance.adhesion(
			reading, profile.crawl_hold_distance, profile.crawl_adhesion_gain, 1.0
		),
		Vector3.ZERO
	)


func test_adhesion_pulls_toward_the_surface_it_found() -> void:
	var profile: LocomotionProfile = _profile()
	var reading: NavSurfaceReading = _reading_of(
		[[Vector3.DOWN, profile.crawl_hold_distance + 1.0]]
	)
	var pull: Vector3 = NavAvoidance.adhesion(
		reading, profile.crawl_hold_distance, profile.crawl_adhesion_gain, 4.0
	)
	assert_almost_eq(pull.normalized().dot(Vector3.DOWN), 1.0, 0.001)
	assert_almost_eq(pull.length(), profile.crawl_adhesion_gain, 0.001)


## Adhesion is a correction, not a destination. Uncapped, a body that has drifted 10 m
## returns a pull that dwarfs the step it was taking, and the crawler stops making
## progress in order to hug a wall.
func test_adhesion_is_capped() -> void:
	var profile: LocomotionProfile = _profile()
	var reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, 100.0]])
	var pull: Vector3 = NavAvoidance.adhesion(
		reading, profile.crawl_hold_distance, profile.crawl_adhesion_gain, 0.75
	)
	assert_almost_eq(pull.length(), 0.75, 0.001)


func test_a_body_with_no_surface_has_nothing_to_adhere_to() -> void:
	var profile: LocomotionProfile = _profile()
	assert_eq(
		NavAvoidance.adhesion(
			_reading_of([]), profile.crawl_hold_distance, profile.crawl_adhesion_gain, 1.0
		),
		Vector3.ZERO
	)


## The behaviour, not the arithmetic: a crawler that has drifted must come back. Without
## this the body walks level with the floor at whatever height it happened to reach,
## which is how it eventually leaves tentacle reach entirely.
func test_a_drifted_crawler_steps_back_toward_its_floor() -> void:
	_flat_floor()
	var profile: LocomotionProfile = _profile()
	var high: float = profile.crawl_hold_distance + 1.0
	var body: NavBodyState = _body_state(Vector3(0.0, high, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, high]])
	var command: NavMotionCommand = SurfaceCrawlController.new().steer(
		body, Vector3(6.0, high, 0.0), reading, 0.1, _probe, _config
	)
	assert_not_null(command)
	assert_lt(command.desired_direction.y, 0.0, "the chosen heading must have a downward part")


# ----- the crawler's escape fan -----


## Boxed in on three sides, with the goal behind. The 120 degree fan around the current
## heading contains no usable direction; the 360 degree escape fan does.
func test_the_escape_fan_finds_a_direction_the_arc_cannot() -> void:
	_flat_floor()
	# A wall directly ahead of the body's facing, close enough to block every step in the
	# forward arc.
	_probe.add_solid(AABB(Vector3(2.0, -4.0, -10.0), Vector3(6.0, 12.0, 20.0)))
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = _reading_of([[Vector3.DOWN, FLOOR_STANDOFF]])
	var crawler := SurfaceCrawlController.new()
	var command: NavMotionCommand = crawler.steer(
		body, Vector3(-8.0, FLOOR_STANDOFF, 0.0), reading, 0.1, _probe, _config
	)
	assert_not_null(command, "the way out is behind, and refusing the tick is what used to happen")
	assert_lt(
		command.desired_direction.dot(Vector3.RIGHT),
		0.9,
		"the chosen heading must leave the blocked forward arc"
	)
