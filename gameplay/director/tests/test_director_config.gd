extends GutTest

## DirectorConfig's cross-field rules, and the defaults the worked encounter pins.
##
## One test per invariant, named for the failure it prevents rather than for the field it
## reads -- the same shape test_behavior_config.gd uses, and for the same reason: a rule
## nobody can state the consequence of is a rule nobody will keep.

var _config: DirectorConfig = null


func before_each() -> void:
	_config = DirectorConfig.new()


func test_a_bare_config_is_usable_on_its_own() -> void:
	assert_eq(_config.invariant_failures(), PackedStringArray(), "no .tres required")


func test_a_bare_config_sits_correctly_against_a_bare_behavior_config() -> void:
	# Three of the rules are about the fit between the two, and all three are silent: the
	# encounter runs and is quietly wrong about something nobody is measuring.
	assert_eq(_config.invariant_failures(BehaviorConfig.new()), PackedStringArray())


func test_menace_that_cannot_be_taken_off_the_board_by_an_unreachable_target() -> void:
	_config.w_stall = 0.0
	assert_string_contains(_failure(), "congratulates a player who did nothing")


func test_a_clock_fast_enough_to_earn_the_exit_on_its_own() -> void:
	_config.w_time = 0.5
	assert_string_contains(_failure(), "standing in a corridor")


func test_weights_too_small_to_ever_reach_the_peak() -> void:
	_config.w_time = 0.0
	_config.w_proximity = 0.0
	_config.w_sight = 0.0
	_config.w_attack = 0.0
	_config.w_lurk = 0.0
	assert_string_contains(_failure(), "would end STALLED")


func test_menace_that_never_sheds() -> void:
	_config.menace_relief_rate = 0.0
	assert_string_contains(_failure(), "sates instantly")


func test_a_cooldown_that_ends_on_the_tick_it_begins() -> void:
	_config.cooldown_s = 0.0
	assert_string_contains(_failure(), "permission to hunt again")


func test_an_exhale_that_drifts_the_alien_closer() -> void:
	_config.relief_roam_bias = 0.0
	assert_eq(_config.invariant_failures().size(), 0, "zero is merely neutral, not wrong")


func test_a_stalemate_that_re_arms_a_full_lull() -> void:
	_config.stalled_lull_retention = 1.0
	assert_string_contains(_failure(), "turns straight back around")


func test_arbitration_that_oscillates() -> void:
	_config.retarget_margin = 0.0
	assert_string_contains(_failure(), "stickiness exists to prevent")


func test_a_lethal_threshold_no_encounter_could_reach() -> void:
	_config.lethal_menace_threshold = 1.0
	assert_string_contains(_failure(), "no strike could ever be lethal")


func test_a_director_that_could_never_get_bored() -> void:
	_config.calm_suspicion_threshold = 0.0
	assert_string_contains(_failure(), "never get bored")


func test_a_cooldown_gate_that_outlasts_the_retreat_it_is_waiting_on() -> void:
	var behavior := BehaviorConfig.new()
	_config.cooldown_separation_m = behavior.retreat_separation_m + 10.0
	assert_string_contains(_failure(behavior), "nothing on screen says why")


func test_a_lull_that_goes_on_rising_after_the_creature_has_committed() -> void:
	var behavior := BehaviorConfig.new()
	_config.calm_suspicion_threshold = behavior.investigate_threshold
	assert_string_contains(_failure(behavior), "already building")


func test_a_target_swap_the_creature_is_still_committed_against() -> void:
	var behavior := BehaviorConfig.new()
	_config.min_target_commit_s = behavior.hunt_sustain_grace_s - 1.0
	assert_string_contains(_failure(behavior), "invisible in play")


func test_the_defaults_reproduce_the_worked_encounters_opening_line() -> void:
	# "lull .6 after two quiet minutes -> bias +.3, roam +.6". If lull_full_s or the ratio
	# move, the trace stops reproducing and every calibration comment in the config is stale.
	var lull: float = 120.0 / _config.lull_full_s
	assert_almost_eq(lull, 0.6, 0.01, "two quiet minutes")
	var outputs: Vector2 = _config.lull_outputs(lull)
	assert_almost_eq(outputs.y, 0.6, 0.01, "roam +.6")
	assert_almost_eq(outputs.x, 0.3, 0.01, "and bias +.3")


func test_the_defaults_reproduce_the_relief_line_at_the_same_ratio() -> void:
	var outputs: Vector2 = _config.relief_outputs()
	assert_almost_eq(outputs.y, -0.8, 0.01, "roam -.8")
	assert_almost_eq(outputs.x, -0.4, 0.01, "and bias -.4, which is the same 1:2")


func test_the_menace_rates_match_the_calibration_the_docstring_quotes() -> void:
	var report := EncounterReport.new()
	report.route_distance = 0.0
	report.has_visual_contact = true
	report.attack_window_open = true
	assert_almost_eq(_config.menace_rate(report, true), 0.05, 0.001, "full pressure, 20 s")

	report.attack_window_open = false
	assert_almost_eq(_config.menace_rate(report, true), 0.036, 0.001, "typical chase, 28 s")

	report.has_visual_contact = false
	report.lurking_at_tunnel_mouth = true
	assert_almost_eq(_config.menace_rate(report, true), 0.036, 0.001, "a lurk is worth a chase")


func test_bias_span_is_not_declared_here() -> void:
	# THE ONE DELIBERATE DEVIATION FROM director.md's CONFIGURATION BLOCK. The spec lists
	# bias_span under "Escalation gate", but BehaviorConfig already ships it with
	# threshold_shift(), and fsm.md applies it on the Behavior side. A second copy would be a
	# dial that looks live and does nothing -- only Behavior's multiplier is ever used, and
	# the moment either is tuned they disagree silently.
	var names := PackedStringArray()
	for entry: Dictionary in _config.get_property_list():
		names.append(entry.name)
	assert_does_not_have(names, "bias_span", "BehaviorConfig owns it, and only BehaviorConfig")
	assert_true(BehaviorConfig.new().get(&"bias_span") != null, "and it is genuinely there")


## EVERY failure, joined -- not the first one. Breaking one field routinely trips a second
## rule as well (setting w_time high enough to sate on the clock also puts it above w_stall),
## and a helper that only returned failures[0] would assert on whichever rule happened to be
## written first rather than on the one the test is named for.
func _failure(behavior: BehaviorConfig = null) -> String:
	var failures: PackedStringArray = _config.invariant_failures(behavior)
	return "\n".join(failures) if not failures.is_empty() else "<no failure reported>"
