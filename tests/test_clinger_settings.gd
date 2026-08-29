extends McpTestSuite

## The clinger invariants PlayerSettings enforces, split out of test_player_settings.gd
## because that file is at gdlint's twenty-public-method ceiling and every test is a public
## method. Same resource, same invariant_failures(), different file.
##
## THE NUMBERS HERE GUARD EACH OTHER RATHER THAN A DESIGN GOAL. An escape leap has to
## out-range the pounce, a stuck window has to outlast a settle, and the orbit has to stay
## calmer than the thrash threshold -- get any of them backwards and the creature still
## runs, it just behaves like a different animal.

const EPSILON := 0.0001


func suite_name() -> String:
	return "clinger_settings"


## An escape that cannot leave the pounce's reach is an attack with extra steps: it leaps,
## lands inside jump range, and is on the same unnavigable face it started on.
func test_an_escape_leap_that_does_not_out_range_the_pounce_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_surface_leap_range = settings.clinger_jump_range
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_surface_leap_range")


## Without a floor a clinger with nowhere to go searches every window forever, and "only
## rarely" becomes "constantly".
func test_an_escape_leap_with_no_cooldown_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_surface_leap_cooldown = 0.0
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_surface_leap_cooldown")


## Every landing would read as a wedge and the creature would bounce from wall to wall.
func test_a_stuck_window_inside_the_settle_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_stuck_window = PlayerSettings.CLINGER_SETTLE_SECONDS
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "clinger_stuck_window")


## Escape leaps are allowed while it circles you, so a tight orbit that reads as thrashing
## would have it abandon the encounter and cross the room.
func test_an_orbit_tight_enough_to_read_as_thrashing_is_reported() -> void:
	var settings := PlayerSettings.new()
	settings.clinger_stuck_turn_rate = settings.clinger_orbit_turn_rate()
	assert_gt(settings.invariant_failures().size(), 0)
	assert_contains(settings.invariant_failures()[0], "orbits")


## The mirror is the risk. PlayerSettings cannot import the node script that already imports
## it, so the settle time is written twice and this is what stops the two drifting.
func test_the_mirrored_settle_has_not_drifted_from_the_clinger() -> void:
	assert_eq(PlayerSettings.CLINGER_SETTLE_SECONDS, Clinger.SETTLE_SECONDS)


## Derived rather than authored, so the detector tracks the creature instead of a designer's
## memory of how fast it used to crawl.
func test_the_stuck_progress_floor_follows_the_crawl_speed() -> void:
	var settings := PlayerSettings.new()
	var before := settings.clinger_stuck_progress_metres()
	settings.clinger_crawl_speed = settings.clinger_crawl_speed * 0.5
	assert_true(absf(settings.clinger_stuck_progress_metres() - before * 0.5) < 0.0001)


## At one window a shed clinger escapes on the hard turn it takes rounding a corner, which
## ends the encounter it was meant to be having. Measured, not guessed: verify_clinger's
## re-attack case failed exactly this way before the streak existed.
func test_a_single_window_is_not_enough_to_call_a_crawl_stuck() -> void:
	var settings := PlayerSettings.new()
	assert_gt(settings.clinger_stuck_windows, 1)
