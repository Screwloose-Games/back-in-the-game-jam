extends GutTest

## The nest scoring function, on its own.
##
## ```text
## nest_score = distance_term + recency_term + roam_bias * proximity_to(roam_anchor)
## ```
##
## Pure and static, so every term can be isolated. The tree suite proves the alien uses this;
## this proves it says what fsm.md says it should. The one thing neither document settles is
## the SIGN of the distance term for a retreat, which wants a far nest where wandering wants
## a near one -- `roam_bias` biases away from the ANCHOR, which is not the same as away from
## the alien, so it cannot serve.

var _config: BehaviorConfig = null


func before_each() -> void:
	_config = BehaviorConfig.new()


func test_a_nearer_nest_scores_higher_when_wandering() -> void:
	assert_gt(_score(5.0), _score(40.0), "ambient wandering should prefer a near nest")


func test_a_further_nest_scores_higher_when_retreating() -> void:
	assert_gt(
		_score(40.0, 0.0, 0.0, 0.0, true),
		_score(5.0, 0.0, 0.0, 0.0, true),
		"a retreat that picked the nearest nest would not create any space"
	)


## The anti-ping-pong rule. A nest visited a moment ago has to score worse than one the
## creature has not seen in a while, or it shuffles between the two nearest forever.
func test_a_recently_visited_nest_scores_worse() -> void:
	assert_gt(_score(10.0, _config.nest_recent_penalty_s), _score(10.0, 1.0))


## Credit saturates: a nest not visited for ten minutes is no more attractive than one not
## visited for one, so an old nest cannot out-score every distance consideration forever.
func test_recency_credit_stops_accruing_past_the_penalty_window() -> void:
	var full: float = _score(10.0, _config.nest_recent_penalty_s)
	var ancient: float = _score(10.0, _config.nest_recent_penalty_s * 10.0)
	assert_almost_eq(ancient, full, 0.001)


func test_a_positive_roam_bias_favours_nests_near_the_anchor() -> void:
	assert_gt(
		_score(20.0, 0.0, 0.0, 1.0),
		_score(20.0, 0.0, _config.nest_roam_span, 1.0),
		"a bored Director should drift the alien toward the party"
	)


func test_a_negative_roam_bias_favours_nests_away_from_the_anchor() -> void:
	assert_lt(
		_score(20.0, 0.0, 0.0, -1.0),
		_score(20.0, 0.0, _config.nest_roam_span, -1.0),
		"a retreat should clear the alien out, not park it next door"
	)


func test_with_no_roam_bias_the_anchor_changes_nothing() -> void:
	assert_eq(_score(20.0, 0.0, 0.0, 0.0), _score(20.0, 0.0, 100.0, 0.0))


## The whole reason the Director gets this lever rather than a destination: it moves the
## odds, and the alien's movement stays explicable in terms of nests it already knows.
func test_the_roam_bias_can_only_reorder_nests_that_already_exist() -> void:
	var weight: float = _score(0.0, 0.0, 0.0, 1.0) - _score(0.0, 0.0, 0.0, 0.0)
	assert_almost_eq(weight, 1.0, 0.001, "one full bias is worth exactly one roam term")


func test_the_terms_are_bounded_so_no_single_one_can_dominate() -> void:
	var extremes: Array = [0.0, 1_000_000.0]
	for travel: float in extremes:
		for since: float in extremes:
			for anchor: float in extremes:
				var value: float = CreatureNestMemory.score(
					travel, since, anchor, 1.0, false, _config
				)
				assert_between(
					value, -4.0, 4.0, "a term ran away at %f/%f/%f" % [travel, since, anchor]
				)


func test_a_fresh_memory_prefers_no_nest_on_recency_alone() -> void:
	var memory := CreatureNestMemory.new()
	memory.remember(PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]), _config)
	assert_eq(memory.visited_at(0), memory.visited_at(1))


func test_a_visited_nest_is_stamped() -> void:
	var memory := CreatureNestMemory.new()
	memory.remember(PackedVector3Array([Vector3.ZERO]), _config)
	memory.mark_visited(0, 12.0)
	assert_eq(memory.visited_at(0), 12.0)


func test_an_out_of_range_index_is_answered_rather_than_crashing() -> void:
	var memory := CreatureNestMemory.new()
	memory.remember(PackedVector3Array([Vector3.ZERO]), _config)
	assert_eq(memory.position_of(9), Vector3.ZERO)
	assert_eq(memory.visited_at(9), -INF)
	memory.mark_visited(9, 1.0)


func test_the_nest_underfoot_is_found_and_a_distant_one_is_not() -> void:
	var memory := CreatureNestMemory.new()
	memory.remember(PackedVector3Array([Vector3(30.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]), _config)

	assert_eq(memory.nest_within(Vector3.ZERO, 3.0), 1)
	assert_eq(memory.nest_within(Vector3(0.0, 0.0, 100.0), 3.0), -1)


func _score(
	travel: float,
	since_visit: float = 0.0,
	anchor_distance: float = 0.0,
	roam_bias: float = 0.0,
	prefer_distant: bool = false
) -> float:
	return CreatureNestMemory.score(
		travel, since_visit, anchor_distance, roam_bias, prefer_distant, _config
	)
