extends McpTestSuite

## MineralLedger: counting per type and totalling count * value into a score.


func suite_name() -> String:
	return "mineral_ledger"


## A ledger on its own settings rather than the shipped .tres, whose mining_multiplier a
## designer is free to retune -- these cases are about counting, not about that knob. The
## crew total is reset too, since add() credits the global Score.
func _make_ledger() -> MineralLedger:
	var ledger := MineralLedger.new()
	ledger.settings = PlayerSettings.new()
	Score.score = 0
	return ledger


func _make_type(value: int) -> MineralType:
	var type := MineralType.new()
	type.value = value
	return type


func test_adding_a_unit_counts_it_once() -> void:
	var ledger := _make_ledger()
	var common := _make_type(1)
	ledger.add(common)
	assert_eq(ledger.count_for(common), 1, "one unit added, one counted")


func test_adding_more_than_one_unit_at_a_time() -> void:
	var ledger := _make_ledger()
	var common := _make_type(1)
	ledger.add(common, 3)
	assert_eq(ledger.count_for(common), 3, "amount is additive, not a flag")


func test_an_uncounted_type_reads_as_zero() -> void:
	var ledger := _make_ledger()
	assert_eq(ledger.count_for(_make_type(1)), 0, "nothing collected yet")


func test_total_score_sums_count_times_value_across_types() -> void:
	var ledger := _make_ledger()
	var common := _make_type(1)
	var uncommon := _make_type(2)
	var rare := _make_type(4)
	ledger.add(common, 5)
	ledger.add(uncommon, 3)
	ledger.add(rare, 1)
	assert_eq(ledger.total_score(), 5 * 1 + 3 * 2 + 1 * 4, "5x1 + 3x2 + 1x4 = 15")


## Retuning a mineral's value mid-session (a live inspector edit, or a designer
## swapping a MiningTuning override) must not move a score already paid out.
func test_a_banked_units_value_is_locked_in_at_collection() -> void:
	var ledger := _make_ledger()
	var common := _make_type(1)
	ledger.add(common, 3)
	assert_eq(ledger.total_score(), 3, "3 units at value 1")
	common.value = 100
	assert_eq(ledger.total_score(), 3, "retuning the type does not reprice units already banked")
	ledger.add(common, 1)
	assert_eq(ledger.total_score(), 103, "only the new unit sees the new value")


## The designer knob the shipped resource turns up to 10. It scales what is banked, so
## the ledger and the crew total move together.
func test_the_mining_multiplier_scales_what_is_banked() -> void:
	var ledger := _make_ledger()
	ledger.settings.mining_multiplier = 10
	ledger.add(_make_type(2), 3)
	assert_eq(ledger.total_score(), 3 * 2 * 10, "3 units at value 2, times ten")
	assert_eq(Score.score, ledger.total_score(), "and the crew total saw the same number")
