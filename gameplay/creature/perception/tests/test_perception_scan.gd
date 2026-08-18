extends GutTest

## PerceptionScan (perception.md sections 19, 23).
##
## Pure timing, so every one of these runs with no scene, no physics and no clock.
## The three that matter are the IDLE/FINISHED distinction, the budget summing to
## exactly the total, and finish_immediately() -- each of which, if wrong, hangs
## Behavior's request-then-poll loop with no error anywhere.

const TICK: float = 1.0 / 60.0

var _scan: PerceptionScan = null


func before_each() -> void:
	_scan = PerceptionScan.new()


func _run_to_completion(max_ticks: int = 1200) -> int:
	var ticks: int = 0
	while _scan.is_active() and ticks < max_ticks:
		_scan.advance(TICK)
		ticks += 1
	return ticks


func test_a_fresh_scan_is_idle_and_not_complete() -> void:
	assert_false(_scan.is_active())
	assert_false(
		_scan.is_complete(),
		"IDLE must not report complete, or a request that never started looks finished"
	)
	assert_eq(_scan.progress(), 0.0)


func test_beginning_a_scan_makes_it_active() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 0.5, 2.0, 10)
	assert_true(_scan.is_active())
	assert_false(_scan.is_complete())
	assert_eq(_scan.samples_total, 10)
	assert_eq(_scan.samples_done, 0)


func test_a_scan_completes_after_its_duration() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 1.0, 20)
	var ticks := _run_to_completion()

	assert_true(_scan.is_complete())
	assert_false(_scan.is_active())
	assert_almost_eq(float(ticks) * TICK, 1.0, TICK * 1.5, "it ends when its duration ends")


func test_progress_climbs_from_zero_to_one() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 1.0, 20)
	assert_eq(_scan.progress(), 0.0)
	for _i: int in 30:
		_scan.advance(TICK)
	assert_between(_scan.progress(), 0.3, 0.7, "halfway through the duration")
	_run_to_completion()
	assert_eq(_scan.progress(), 1.0)


## The budget is what keeps a thorough scan from landing 256 shape queries in one
## frame. It must still add up to exactly the total, or the scan silently samples
## less than it claims.
func test_the_sample_budget_sums_to_exactly_the_total() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 1.0, 137)
	var spent: int = 0
	var largest: int = 0
	while _scan.is_active():
		var due := _scan.advance(TICK)
		spent += due
		largest = maxi(largest, due)

	assert_eq(spent, 137)
	assert_eq(_scan.samples_done, 137)
	assert_lt(largest, 20, "the cost is spread, not landed in one frame")


func test_a_zero_duration_scan_completes_on_its_first_tick() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 0.0, 5)
	var due := _scan.advance(TICK)

	assert_eq(due, 5, "an instant look spends its whole budget at once")
	assert_true(_scan.is_complete())


func test_just_finished_fires_exactly_once() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 0.2, 4)
	var fired: int = 0
	for _i: int in 60:
		_scan.advance(TICK)
		if _scan.just_finished():
			fired += 1
	assert_eq(fired, 1, "the facade must emit its outcome once, not every tick after")


func test_finish_immediately_ends_a_scan_that_cannot_run() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 10.0, 50)
	_scan.finish_immediately()

	assert_true(_scan.is_complete())
	assert_true(_scan.just_finished(), "the facade still gets one chance to emit the outcome")
	assert_eq(_scan.progress(), 1.0)


func test_cancel_returns_a_scan_to_idle_not_to_complete() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 10.0, 50)
	_scan.advance(TICK)
	_scan.cancel()

	assert_false(_scan.is_active())
	assert_false(_scan.is_complete(), "a cancelled scan did not find nothing; it did not happen")


## Behavior re-issues a search as it moves. Queueing would build a backlog nobody
## ever drains.
func test_re_requesting_while_running_replaces_rather_than_queues() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 10.0, 50)
	for _i: int in 60:
		_scan.advance(TICK)
	_scan.note_positive()
	assert_gt(_scan.samples_done, 0)

	var second := AABB(Vector3(9, 9, 9), Vector3.ONE)
	_scan.begin(second, 0.5, 1.0, 8)

	assert_eq(_scan.region, second)
	assert_eq(_scan.samples_done, 0, "the new scan starts from nothing")
	assert_eq(_scan.elapsed, 0.0)
	assert_false(_scan.found_any, "and does not inherit the old one's result")


func test_completion_latches_until_the_next_request() -> void:
	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 0.1, 2)
	_run_to_completion()
	assert_true(_scan.is_complete())

	for _i: int in 30:
		_scan.advance(TICK)
	assert_true(_scan.is_complete(), "still complete; Behavior may poll whenever it likes")

	_scan.begin(AABB(Vector3.ZERO, Vector3.ONE), 1.0, 1.0, 2)
	assert_false(_scan.is_complete(), "and clears the moment a new scan starts")


func test_thoroughness_is_clamped_and_recorded() -> void:
	_scan.begin(AABB(), 5.0, 1.0, 1)
	assert_eq(_scan.thoroughness, 1.0)
	_scan.begin(AABB(), -1.0, 1.0, 1)
	assert_eq(_scan.thoroughness, 0.0)


## Deterministic sampling: two runs of the same scan look in the same places, which
## is what makes a search reproducible in a test.
func test_sample_points_stay_inside_the_region_and_are_reproducible() -> void:
	var region := AABB(Vector3(-3, -1, 2), Vector3(6, 2, 4))
	_scan.begin(region, 1.0, 1.0, 32)

	var first: Array[Vector3] = []
	for index: int in 32:
		var point := _scan.sample_point(index)
		assert_true(region.has_point(point), "a sample outside the region searches somewhere else")
		first.append(point)

	var other := PerceptionScan.new()
	other.begin(region, 1.0, 1.0, 32)
	for index: int in 32:
		assert_eq(other.sample_point(index), first[index])


func test_sample_points_spread_across_the_region() -> void:
	var region := AABB(Vector3.ZERO, Vector3(10, 10, 10))
	_scan.begin(region, 1.0, 1.0, 64)

	var lowest := Vector3.ONE * 999.0
	var highest := Vector3.ONE * -999.0
	for index: int in 64:
		var point := _scan.sample_point(index)
		lowest = lowest.min(point)
		highest = highest.max(point)
	assert_gt(
		(highest - lowest).length(), 10.0, "a search that only looks in one corner is not a search"
	)


func test_advancing_an_idle_scan_costs_nothing() -> void:
	assert_eq(_scan.advance(TICK), 0)
	assert_false(_scan.is_active())
	assert_false(_scan.is_complete())
