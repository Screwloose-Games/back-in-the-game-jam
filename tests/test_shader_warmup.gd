extends McpTestSuite

## ShaderWarmup: the frame counting the laser's first draw depends on.
##
## The one worth pinning is the ordering. _process runs before the draw, so a
## warm-up that released on the same step as its last hold would never have the
## last held frame drawn - and would warm nothing while looking like it worked.

var _holds := 0
var _releases := 0
var _finishes := 0


func suite_name() -> String:
	return "shader_warmup"


func setup() -> void:
	_holds = 0
	_releases = 0
	_finishes = 0


func test_it_holds_for_every_requested_frame_before_releasing() -> void:
	var warmup := _build()
	warmup.run(_on_hold, _on_release, 3)

	for _i: int in 3:
		warmup.step()

	assert_eq(_holds, 3, "held once per requested frame")
	assert_eq(_releases, 0, "and has not released while frames were still owed")


func test_it_releases_once_on_the_step_after_the_last_held_frame() -> void:
	var warmup := _build()
	warmup.run(_on_hold, _on_release, 2)

	for _i: int in 3:
		warmup.step()

	assert_eq(_holds, 2, "no extra hold after the count ran out")
	assert_eq(_releases, 1, "released exactly once")
	assert_eq(_finishes, 1, "and said so exactly once")


func test_stepping_a_finished_warmup_does_nothing_further() -> void:
	var warmup := _build()
	warmup.run(_on_hold, _on_release, 1)

	for _i: int in 4:
		warmup.step()

	assert_eq(_releases, 1, "a finished warm-up does not release again")
	assert_eq(_finishes, 1, "nor report finishing again")


func test_a_frame_count_below_one_still_draws_once() -> void:
	var warmup := _build()
	warmup.run(_on_hold, _on_release, 0)
	warmup.step()

	assert_eq(_holds, 1, "zero frames is clamped to one, not skipped entirely")
	assert_true(warmup.is_running() == false, "and the single frame was the last one")


## Built out of tree and handed to the runner to free, so stepping the machine
## needs no SceneTree and no clock.
func _build() -> ShaderWarmup:
	var warmup := ShaderWarmup.new()
	warmup.finished.connect(_on_finished)
	track(warmup)
	return warmup


func _on_hold() -> void:
	_holds += 1


func _on_release() -> void:
	_releases += 1


func _on_finished() -> void:
	_finishes += 1
