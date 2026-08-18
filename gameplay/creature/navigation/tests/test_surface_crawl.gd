extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 3: the crawl controller (navigation.md sections 8, 21, 22, 23). The sampler it
## reads is covered in test_surface_field.gd.
##
## Section 21 calls the six scoring weights "tuning parameters", which means they get
## retuned by somebody watching an alien move rather than by somebody reading the code.
## So each term is asserted on its own below, and the winner is asserted separately: a
## retune that inverts one term should fail with that term's name, not as "the alien went
## the wrong way".


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


func _crawler() -> SurfaceCrawlController:
	return SurfaceCrawlController.new()


# ----- section 21's six terms, one at a time -----


func test_goal_alignment_rewards_facing_the_goal() -> void:
	assert_almost_eq(
		SurfaceCrawlController.goal_alignment(Vector3.RIGHT, Vector3.RIGHT), 1.0, 0.001
	)
	assert_almost_eq(SurfaceCrawlController.goal_alignment(Vector3.RIGHT, Vector3.LEFT), 0.0, 0.001)
	assert_almost_eq(SurfaceCrawlController.goal_alignment(Vector3.RIGHT, Vector3.UP), 0.5, 0.001)


func test_surface_quality_falls_off_with_distance_and_bottoms_out_at_a_miss() -> void:
	var near := NavSurfaceSample.make(Vector3.DOWN, Vector3.DOWN, Vector3.UP, 0.0)
	var far := NavSurfaceSample.make(Vector3.DOWN, Vector3.DOWN * 2.0, Vector3.UP, 2.0)
	assert_almost_eq(SurfaceCrawlController.surface_quality(near, 2.2), 1.0, 0.001)
	assert_lt(SurfaceCrawlController.surface_quality(far, 2.2), 0.2)
	assert_eq(
		SurfaceCrawlController.surface_quality(NavSurfaceSample.missed(Vector3.DOWN, 2.2), 2.2),
		0.0,
		"an unreachable direction is the worst hold, not an absent opinion"
	)


func test_clearance_score_saturates_at_comfortable() -> void:
	assert_almost_eq(SurfaceCrawlController.clearance_score(1.25, 2.5), 0.5, 0.001)
	assert_almost_eq(SurfaceCrawlController.clearance_score(9.0, 2.5), 1.0, 0.001)
	assert_almost_eq(SurfaceCrawlController.clearance_score(INF, 2.5), 1.0, 0.001)


func test_turning_is_free_inside_what_the_body_can_do_and_charged_beyond() -> void:
	var forward := Vector3.FORWARD
	var slight: Vector3 = forward.rotated(Vector3.UP, 0.2)
	var sharp: Vector3 = forward.rotated(Vector3.UP, 2.5)
	assert_eq(
		SurfaceCrawlController.turning_penalty(slight, forward, 0.5),
		0.0,
		"a turn the body can simply make costs nothing"
	)
	assert_gt(SurfaceCrawlController.turning_penalty(sharp, forward, 0.5), 0.5)


func test_a_stationary_body_is_not_charged_for_turning() -> void:
	assert_eq(
		SurfaceCrawlController.turning_penalty(Vector3.BACK, Vector3.FORWARD, PI),
		0.0,
		"turn radius comes from momentum; at rest an alien may face wherever it likes"
	)


func test_the_score_subtracts_the_penalties_rather_than_adding_them() -> void:
	var candidate := NavCrawlCandidate.make(Vector3.FORWARD, Vector3.ZERO, null)
	candidate.goal_alignment = 1.0
	var clean: float = SurfaceCrawlController.score(candidate, _profile())
	candidate.collision_penalty = 1.0
	assert_lt(
		SurfaceCrawlController.score(candidate, _profile()),
		clean,
		"a candidate that would hit something must score worse, not better"
	)


func test_collision_outweighs_a_perfectly_aligned_goal() -> void:
	var toward := NavCrawlCandidate.make(Vector3.FORWARD, Vector3.ZERO, null)
	toward.goal_alignment = 1.0
	toward.collision_penalty = 1.0
	var aside := NavCrawlCandidate.make(Vector3.RIGHT, Vector3.ZERO, null)
	aside.goal_alignment = 0.5
	assert_gt(
		SurfaceCrawlController.score(aside, _profile()),
		SurfaceCrawlController.score(toward, _profile()),
		"otherwise the alien walks into a wall because the target is behind it"
	)


# ----- section 22, as a constraint -----


func test_the_chosen_heading_is_clamped_to_what_the_body_could_turn() -> void:
	var limited: Vector3 = SurfaceCrawlController.turn_limited(
		Vector3.FORWARD, Vector3.BACK, 5.0, 1.0 / 60.0, _profile()
	)
	var turned: float = Vector3.FORWARD.angle_to(limited)
	var allowed: float = LocomotionProfile.max_turn_angle(5.0, 1.0 / 60.0, 2.5)
	assert_almost_eq(turned, allowed, 0.0001, "a reversal is executed as an arc, not a pivot")


func test_a_turn_within_the_limit_is_taken_whole() -> void:
	var desired: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, 0.01)
	var limited: Vector3 = SurfaceCrawlController.turn_limited(
		Vector3.FORWARD, desired, 5.0, 1.0 / 60.0, _profile()
	)
	assert_almost_eq(limited.angle_to(desired), 0.0, 0.0001)


func test_an_exact_reversal_still_produces_a_finite_heading() -> void:
	# from.cross(to) is zero here, so the rotation axis has to be invented. Getting this
	# wrong yields NaN, which propagates into the body's position and is unrecoverable.
	var limited: Vector3 = SurfaceCrawlController.turn_limited(
		Vector3.UP, Vector3.DOWN, 5.0, 1.0 / 60.0, _profile()
	)
	assert_true(limited.is_finite(), "a degenerate axis must not become NaN")
	assert_almost_eq(limited.length(), 1.0, 0.001)


# ----- steering, end to end against analytic geometry -----


func test_the_crawler_heads_toward_the_goal_along_a_floor() -> void:
	_flat_floor()
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		body.position, _probe, _profile(), _config.world_mask
	)
	var command: NavMotionCommand = _crawler().steer(
		body, Vector3(10.0, FLOOR_STANDOFF, 0.0), reading, 1.0 / 60.0, _probe, _config
	)
	assert_not_null(command, "there is a floor right there; this must not refuse")
	assert_gt(command.desired_direction.x, 0.7, "the goal is +x and so should the heading be")
	assert_eq(command.mode, NavLocomotion.Mode.SURFACE_CRAWL)


func test_the_crawler_reports_the_surface_it_is_holding() -> void:
	_flat_floor()
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		body.position, _probe, _profile(), _config.world_mask
	)
	var command: NavMotionCommand = _crawler().steer(
		body, Vector3(10.0, FLOOR_STANDOFF, 0.0), reading, 1.0 / 60.0, _probe, _config
	)
	assert_gt(
		command.preferred_surface_normal.dot(Vector3.UP),
		0.9,
		"standing on a floor, the preferred normal is up"
	)


## Section 8.2, and the reason `steer` may return null at all.
func test_the_crawler_refuses_when_nothing_is_within_reach() -> void:
	var body: NavBodyState = _body_state(Vector3(0.0, 40.0, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		body.position, _probe, _profile(), _config.world_mask
	)
	assert_false(reading.has_surface(), "nothing was built, so nothing can be held")
	assert_null(
		_crawler().steer(body, Vector3(10.0, 40.0, 0.0), reading, 1.0 / 60.0, _probe, _config),
		"a best-effort answer here is an alien drifting through space (Invariant 3)"
	)


func test_every_scored_candidate_is_kept_for_the_overlay() -> void:
	_flat_floor()
	var crawler: SurfaceCrawlController = _crawler()
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		body.position, _probe, _profile(), _config.world_mask
	)
	crawler.steer(body, Vector3(10.0, FLOOR_STANDOFF, 0.0), reading, 1.0 / 60.0, _probe, _config)
	assert_eq(
		crawler.last_candidates.size(),
		_profile().crawl_candidate_count,
		"section 39 draws the whole fan, including the directions that lost"
	)


func test_candidate_directions_lie_in_the_surface_rather_than_into_it() -> void:
	_flat_floor()
	var crawler: SurfaceCrawlController = _crawler()
	var body: NavBodyState = _body_state(Vector3(0.0, FLOOR_STANDOFF, 0.0), Vector3.RIGHT)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		body.position, _probe, _profile(), _config.world_mask
	)
	crawler.steer(body, Vector3(10.0, FLOOR_STANDOFF, 0.0), reading, 1.0 / 60.0, _probe, _config)
	for candidate: NavCrawlCandidate in crawler.last_candidates:
		assert_almost_eq(
			candidate.direction.dot(Vector3.UP),
			0.0,
			0.001,
			"a crawler moves along what it holds; into the floor is not slow, it is impossible"
		)
