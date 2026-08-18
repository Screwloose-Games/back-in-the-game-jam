extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Section 35: imperfect route selection that is not arbitrary.
##
## The section opens by forbidding the obvious implementation -- "do not create
## unpredictability with arbitrary bad decisions" -- and its worked example is the whole
## specification: costs 31, 34, 38 and 67, where the alien may take any of the first three
## and "should almost never choose D". These tests are that example.


## Section 35's own numbers. A function rather than a const, because
## `const x := PackedFloat32Array([...])` is not a constant expression in Godot -- the
## same trap `prototypes/tentacle_crawler/CLAUDE.md` records for PackedStringArray, and
## one gdlint cannot see: only the engine's own parser rejects it, so the suite silently
## stops collecting the file.
func _worked_example() -> PackedFloat32Array:
	return PackedFloat32Array([31.0, 34.0, 38.0, 67.0])


func _weights_for_example() -> PackedFloat32Array:
	return NavRouteChooser.weights(
		_worked_example(), _config.route_tolerance, _config.route_selection_sharpness
	)


func _route_costing(cost: float) -> NavRoute:
	var route := NavRoute.new()
	route.status = NavRoute.Status.COMPLETE
	route.anchors = PackedVector3Array([Vector3.ZERO, Vector3(cost, 0.0, 0.0)])
	route.cost = cost
	return route


func _example_routes() -> Array[NavRoute]:
	var routes: Array[NavRoute] = []
	for cost: float in _worked_example():
		routes.append(_route_costing(cost))
	return routes


# ----- section 35's worked example -----


func test_the_three_reasonable_routes_are_all_eligible() -> void:
	var scores: PackedFloat32Array = _weights_for_example()
	for index: int in 3:
		assert_gt(scores[index], 0.0, "route %d is reasonable and must be choosable" % index)


func test_the_unreasonable_route_is_not_merely_unlikely() -> void:
	assert_eq(
		_weights_for_example()[3],
		0.0,
		(
			"a small weight makes 'almost never' a frequency, so it happens on some "
			+ "playthrough and looks exactly like the arbitrary bad decision section 35 bans"
		)
	)


func test_cheaper_routes_are_preferred_among_the_eligible() -> void:
	var scores: PackedFloat32Array = _weights_for_example()
	assert_gt(scores[0], scores[1])
	assert_gt(scores[1], scores[2])


func test_higher_intelligence_narrows_the_selection() -> void:
	var casual: PackedFloat32Array = NavRouteChooser.weights(_worked_example(), 0.25, 1.0)
	var sharp: PackedFloat32Array = NavRouteChooser.weights(_worked_example(), 0.25, 20.0)
	assert_gt(
		sharp[0] / sharp[2],
		casual[0] / casual[2],
		"section 35: higher intelligence narrows selection toward better alternatives"
	)


# ----- determinism -----


func test_the_same_seed_makes_the_same_choice() -> void:
	var first := NavRouteChooser.new()
	var second := NavRouteChooser.new()
	first.rng.seed = 12345
	second.rng.seed = 12345
	for _step: int in 20:
		assert_eq(
			first.choose(_example_routes(), _config).cost,
			second.choose(_example_routes(), _config).cost,
			"a route that differs between two runs is a bug nobody can reproduce"
		)


func test_over_many_draws_the_best_route_wins_most_often() -> void:
	var chooser := NavRouteChooser.new()
	chooser.rng.seed = 99
	var tally: Dictionary = {}
	for _step: int in 400:
		var cost: float = chooser.choose(_example_routes(), _config).cost
		tally[cost] = int(tally.get(cost, 0)) + 1
	assert_gt(int(tally.get(31.0, 0)), int(tally.get(38.0, 0)), "cheap should win more often")
	assert_eq(int(tally.get(67.0, 0)), 0, "and the bad route should never win at all")


func test_variation_actually_happens() -> void:
	var chooser := NavRouteChooser.new()
	chooser.rng.seed = 7
	var seen: Dictionary = {}
	for _step: int in 200:
		seen[chooser.choose(_example_routes(), _config).cost] = true
	assert_gt(seen.size(), 1, "a chooser that always picks the best is not section 35 at all")


# ----- switching it off -----


func test_one_alternative_degenerates_to_the_cheapest() -> void:
	_config.route_alternatives = 1
	var chooser := NavRouteChooser.new()
	for _step: int in 20:
		assert_eq(
			chooser.choose(_example_routes(), _config).cost,
			31.0,
			"turning section 35 off has to be a config change, not a code path"
		)


func test_an_unusable_route_is_never_chosen() -> void:
	var routes: Array[NavRoute] = [NavRoute.unreachable(Vector3.ZERO), _route_costing(50.0)]
	assert_eq(NavRouteChooser.new().choose(routes, _config).cost, 50.0)


func test_no_usable_route_yields_null_rather_than_a_guess() -> void:
	var routes: Array[NavRoute] = [NavRoute.unreachable(Vector3.ZERO)]
	assert_null(NavRouteChooser.new().choose(routes, _config))
