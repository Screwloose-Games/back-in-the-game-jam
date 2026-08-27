extends McpTestSuite

## PlayerHealthModel: the attrition arithmetic. The design turns on a hard knock
## being expensive and a scrape being free, and on nothing but the stalker killing
## outright, so those two asymmetries are what these pin.

const EPSILON := 0.0001
const MIN_SPEED := 4.0
const REFERENCE_SPEED := 8.0
const DAMAGE_AT_REFERENCE := 18.0
const HARDNESS_CAP := 3.0
const MAX_HEALTH := 100.0
const REGEN_DELAY := 6.0
const REGEN_PER_SECOND := 2.0


func suite_name() -> String:
	return "player_health"


func _damage(closing_speed: float) -> float:
	return PlayerHealthModel.impact_damage(
		closing_speed, MIN_SPEED, REFERENCE_SPEED, DAMAGE_AT_REFERENCE, HARDNESS_CAP
	)


func test_a_scrape_under_the_deadband_is_free() -> void:
	assert_eq(_damage(-1.0), 0.0, "brushing a wall is not a hit")
	assert_eq(_damage(-MIN_SPEED), 0.0, "and the deadband itself is still a scrape")


func test_an_impact_at_the_reference_speed_costs_the_reference_figure() -> void:
	assert_true(absf(_damage(-REFERENCE_SPEED) - DAMAGE_AT_REFERENCE) < EPSILON)


func test_damage_climbs_with_closing_speed() -> void:
	assert_true(_damage(-6.0) > _damage(-5.0), "harder hits cost more")
	assert_true(_damage(-6.0) < _damage(-REFERENCE_SPEED))


func test_the_sign_of_the_closing_speed_is_irrelevant() -> void:
	assert_eq(_damage(-6.0), _damage(6.0), "the signal delivers it negative; the model absfs it")


## Pillar 1: the stalker owns instant death. A wall must never be able to take it,
## however fast you were going when you found it.
func test_the_worst_crash_is_capped() -> void:
	var worst := _damage(-40.0)
	assert_true(absf(worst - DAMAGE_AT_REFERENCE * HARDNESS_CAP) < EPSILON)
	assert_true(worst < MAX_HEALTH, "no impact may empty a full pool on its own")


## A reference speed at or under the deadband would divide by zero or by a negative.
func test_a_deadband_past_the_reference_speed_costs_nothing_rather_than_erroring() -> void:
	assert_eq(
		PlayerHealthModel.impact_damage(-20.0, 9.0, 8.0, DAMAGE_AT_REFERENCE, HARDNESS_CAP), 0.0
	)


func test_recovery_waits_out_the_delay() -> void:
	assert_eq(PlayerHealthModel.regen_rate(0.0, REGEN_DELAY, REGEN_PER_SECOND), 0.0)
	assert_eq(PlayerHealthModel.regen_rate(5.9, REGEN_DELAY, REGEN_PER_SECOND), 0.0)
	assert_eq(PlayerHealthModel.regen_rate(6.0, REGEN_DELAY, REGEN_PER_SECOND), REGEN_PER_SECOND)


func test_the_pool_clamps_at_both_ends() -> void:
	assert_eq(PlayerHealthModel.step(95.0, MAX_HEALTH, 20.0), MAX_HEALTH)
	assert_eq(PlayerHealthModel.step(5.0, MAX_HEALTH, -20.0), 0.0)


func test_fraction_on_an_empty_pool_reads_zero_rather_than_dividing() -> void:
	assert_eq(PlayerHealthModel.fraction(10.0, 0.0), 0.0)
	assert_eq(PlayerHealthModel.fraction(50.0, MAX_HEALTH), 0.5)
