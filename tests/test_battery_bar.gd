extends McpTestSuite

## BatteryBar: the fraction-to-segments rule the cube's gauge is built on. The
## shader draws whatever it is handed, so these are the only assertions that
## reach the spec at all - "each segment is 20%" lives here or nowhere.

const FULL := Color(0.0, 1.0, 0.0)
const WARN := Color(1.0, 1.0, 0.0)
const CRITICAL := Color(1.0, 0.0, 0.0)


func suite_name() -> String:
	return "battery_bar"


func test_a_full_box_lights_every_segment() -> void:
	assert_eq(BatteryBar.lit_segments(1.0), 5, "five fifths is five segments")


func test_an_empty_box_lights_nothing() -> void:
	assert_eq(BatteryBar.lit_segments(0.0), 0, "empty reads as dark, not as one bar")


func test_a_nearly_empty_box_still_shows_one() -> void:
	assert_eq(BatteryBar.lit_segments(0.0001), 1, "still worth swimming back to")


func test_each_segment_is_a_fifth() -> void:
	assert_eq(BatteryBar.lit_segments(0.2), 1, "one fifth exactly")
	assert_eq(BatteryBar.lit_segments(0.4), 2, "two fifths exactly")
	assert_eq(BatteryBar.lit_segments(0.6), 3, "three fifths exactly")
	assert_eq(BatteryBar.lit_segments(0.8), 4, "four fifths exactly")


func test_a_hair_over_a_boundary_lights_the_next_segment() -> void:
	assert_eq(BatteryBar.lit_segments(0.2001), 2, "past one fifth")
	assert_eq(BatteryBar.lit_segments(0.4001), 3, "past two fifths")
	assert_eq(BatteryBar.lit_segments(0.6001), 4, "past three fifths")
	assert_eq(BatteryBar.lit_segments(0.8001), 5, "past four fifths")


func test_a_fraction_outside_the_range_clamps() -> void:
	assert_eq(BatteryBar.lit_segments(1.5), 5, "cannot light a sixth segment")
	assert_eq(BatteryBar.lit_segments(-1.0), 0, "cannot light a negative one")


func test_a_healthy_box_is_green() -> void:
	assert_eq(_band(5), FULL, "five segments")
	assert_eq(_band(4), FULL, "four segments")


func test_a_box_worth_worrying_about_is_yellow() -> void:
	assert_eq(_band(3), WARN, "three segments")
	assert_eq(_band(2), WARN, "two segments")


func test_the_last_segment_is_red() -> void:
	assert_eq(_band(1), CRITICAL, "one segment")


func test_only_the_last_segment_blinks() -> void:
	assert_true(BatteryBar.blinks(1), "one segment is the alarm")
	assert_false(BatteryBar.blinks(0), "an empty box is dark, not alarming")
	assert_false(BatteryBar.blinks(2), "two segments is a warning, not an alarm")
	assert_false(BatteryBar.blinks(5), "a full box says nothing")


func test_the_segment_count_matches_the_shader() -> void:
	assert_eq(BatteryBar.SEGMENTS, 5, "battery_bar.gdshader lays out this many cells")


## Sentinels rather than the bar's own exported colours, so these pin which band
## a count falls in and not what shade someone last tuned it to.
func _band(lit: int) -> Color:
	return BatteryBar.band_color(lit, FULL, WARN, CRITICAL)
