extends McpTestSuite

## ClingerStuck: the two signals that get a clinger off a surface it cannot navigate, with
## no scene.
##
## THE FALSE POSITIVES ARE THE CASES THAT MATTER. A detector that fires on a healthy crawl
## sends the creature across the room for no reason -- and in a playtest that is
## indistinguishable from the feature working, because a clinger leaping somewhere is
## exactly what this looks like when it is right. Four of these are negatives.

const TICK := 1.0 / 60.0
const CRAWL_SPEED := 1.1


func suite_name() -> String:
	return "clinger_stuck"


func test_a_straight_crawl_is_never_stuck() -> void:
	var detector := _detector()
	var at := Vector3.ZERO
	for _tick: int in 200:
		at += Vector3.RIGHT * CRAWL_SPEED * TICK
		assert_false(detector.note(at, Vector3.RIGHT, TICK), "a straight crawl read as stuck")


## Built the way Clinger._ready builds it, so a designer moving a slider until the creature
## breaks fails here rather than in a playtest.
func test_the_shipped_defaults_leave_the_shipped_crawl_alone() -> void:
	var settings := PlayerSettings.new()
	var detector := ClingerStuck.new()
	detector.window = settings.clinger_stuck_window
	detector.progress_metres = settings.clinger_stuck_progress_metres()
	detector.wander_limit = settings.clinger_stuck_wander_limit
	detector.turn_rate_limit = settings.clinger_stuck_turn_rate
	var at := Vector3.ZERO
	for _tick: int in 600:
		at += Vector3.RIGHT * settings.clinger_crawl_speed * TICK
		assert_false(detector.note(at, Vector3.RIGHT, TICK), "the shipped crawl read as stuck")


## A shed one circling you is doing what it means to do, and escape leaps are allowed while
## it orbits -- so this is the case that stops it abandoning an encounter mid-circle.
func test_a_legitimate_orbit_is_left_alone() -> void:
	var settings := PlayerSettings.new()
	var detector := _detector()
	var radius := settings.clinger_orbit_radius()
	var phase := 0.0
	for _tick: int in 600:
		phase += ClingerState.orbit_step(settings.clinger_crawl_speed, radius, TICK)
		var at := Vector3(cos(phase), 0.0, sin(phase)) * radius
		var heading := Vector3(-sin(phase), 0.0, cos(phase))
		assert_false(detector.note(at, heading, TICK), "circling the player read as stuck")


func test_a_crawl_that_covers_no_ground_is_stuck() -> void:
	var detector := _detector()
	assert_true(_run_frozen(detector, 3.5), "a body that never moved was not noticed")
	assert_true(detector.moved < detector.progress_metres, "the displacement limb did not fire")


## The other two limbs are turned off, so the pass is the wander limb's alone.
##
## ISOLATED RATHER THAN ARRANGED, because at the shipped numbers the two progress limbs
## overlap: 3 s of crawling lays 3.3 m of path, so wander fires below 0.83 m of net travel
## and displacement below 0.5 m, and a closed loop lands under both. Contriving a radius in
## the band between them would pass on arithmetic a later retune would silently break.
func test_the_wander_limb_alone_catches_a_body_walking_a_circle() -> void:
	var detector := _detector()
	detector.progress_metres = 0.01
	detector.turn_rate_limit = 100.0
	var radius := 0.6
	var stuck := false
	var travelled := 0.0
	for _tick: int in 200:
		travelled += CRAWL_SPEED * TICK
		var phase := travelled / radius
		var at := Vector3(cos(phase), 0.0, sin(phase)) * radius
		var heading := Vector3(-sin(phase), 0.0, cos(phase))
		stuck = detector.note(at, heading, TICK) or stuck
	assert_true(stuck, "a body going round in circles was not noticed")
	assert_true(detector.moved > detector.progress_metres, "the displacement limb fired instead")
	assert_true(detector.wander > detector.wander_limit, "the wander limb did not fire")


## The churn limb alone has to catch this: the body makes perfectly good progress, it just
## will not settle on a heading.
func test_a_body_turning_constantly_is_stuck_even_though_it_is_covering_ground() -> void:
	var detector := _detector()
	var at := Vector3.ZERO
	var heading := Vector3.RIGHT
	var stuck := false
	for tick: int in 200:
		at += Vector3.RIGHT * CRAWL_SPEED * TICK
		if tick % 12 == 0:
			heading = heading.rotated(Vector3.UP, deg_to_rad(40.0))
		stuck = detector.note(at, heading, TICK) or stuck
	assert_true(stuck, "a body that would not settle on a heading was not noticed")
	assert_true(detector.moved > detector.progress_metres, "it covered ground, so not that limb")
	assert_true(
		detector.wander < detector.wander_limit, "it went somewhere, so not that limb either"
	)
	assert_true(detector.turn_rate > detector.turn_rate_limit, "the churn limb did not fire")


func test_one_verdict_per_window_rather_than_every_tick_after_the_first() -> void:
	var detector := _detector()
	_run_frozen(detector, 6.5)
	assert_eq(detector.trips, 2, "six seconds of a wedged body should report twice, not every tick")


## A settle is not evidence. Banking those seconds against the ones after it starts again
## would have every landing report a wedge before the body had taken a step.
func test_a_reset_forgets_the_window_rather_than_pausing_it() -> void:
	var detector := _detector()
	assert_false(_run_frozen(detector, 2.9), "fired before the window was even full")
	detector.reset()
	assert_false(_run_frozen(detector, 2.9), "the reset banked the seconds before it")


## THE REGRESSION. A shed clinger circling a player in a sixteen-metre room turns hard once
## as it rounds a corner between two walls and its goal jumps into a new tangent plane. At
## one window that transient was enough to send it across the room mid-encounter.
func test_a_single_bad_window_is_not_enough() -> void:
	var detector := _detector()
	detector.windows_needed = 2
	assert_false(_run_frozen(detector, 3.5), "one bad window escaped on a corner")
	# Then a healthy one, which has to clear the streak rather than bank it.
	var at := Vector3.ZERO
	for _tick: int in 200:
		at += Vector3.RIGHT * CRAWL_SPEED * TICK
		assert_false(
			detector.note(at, Vector3.RIGHT, TICK), "a good window did not clear the streak"
		)
	assert_eq(detector.streak, 0, "the streak survived a healthy window")


func test_two_consecutive_bad_windows_are_enough() -> void:
	var detector := _detector()
	detector.windows_needed = 2
	assert_true(_run_frozen(detector, 6.5), "a body wedged for two windows was never noticed")
	assert_eq(detector.trips, 1, "two windows should be one verdict, not two")


func test_a_zero_window_reports_rather_than_dividing_by_zero() -> void:
	var detector := _detector()
	detector.window = 0.0
	detector.note(Vector3.ZERO, Vector3.RIGHT, TICK)
	detector.note(Vector3.ZERO, Vector3.RIGHT, 0.0)
	assert_true(is_finite(detector.turn_rate), "a zero window produced INF")


func test_a_frozen_body_reports_rather_than_dividing_by_zero() -> void:
	var detector := _detector()
	_run_frozen(detector, 3.5)
	assert_true(is_finite(detector.wander), "zero net displacement produced INF")


## A NaN in a heading never recovers -- it propagates into the basis and the body spins for
## the rest of the run.
func test_a_zero_heading_is_ignored_rather_than_producing_nan() -> void:
	var detector := _detector()
	var at := Vector3.ZERO
	for _tick: int in 240:
		at += Vector3.RIGHT * CRAWL_SPEED * TICK
		detector.note(at, Vector3.ZERO, TICK)
	assert_false(is_nan(detector.turn_rate), "a zero heading produced NaN")


## One window, so a case that is about a limb is about that limb and not about the streak.
## test_a_single_bad_window_is_not_enough covers the streak on its own.
func _detector() -> ClingerStuck:
	var detector := ClingerStuck.new()
	detector.window = 3.0
	detector.windows_needed = 1
	detector.progress_metres = 0.5
	detector.wander_limit = 4.0
	detector.turn_rate_limit = 2.0
	return detector


## Holds the body still for `seconds`, and reports whether it was ever judged stuck.
func _run_frozen(detector: ClingerStuck, seconds: float) -> bool:
	var stuck := false
	var ticks := int(seconds / TICK)
	for _tick: int in ticks:
		stuck = detector.note(Vector3.ZERO, Vector3.RIGHT, TICK) or stuck
	return stuck
