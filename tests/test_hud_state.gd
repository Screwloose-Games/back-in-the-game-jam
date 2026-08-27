extends McpTestSuite

## HudState: the contract all four HUD variants bind to.
##
## The two things worth pinning are the ones that are invisible when they break.
## First the change gate: without it a smooth drain emits several hundred signals a
## second and redraws the whole HUD on each, which does not look wrong, it just
## quietly costs a frame budget nobody goes looking for. Second announce_all(): it is
## the only reason swapping a variant mid-run shows the truth instead of a HUD full
## of defaults, and a HUD full of defaults looks exactly like a HUD that works.


func suite_name() -> String:
	return "hud_state"


func _make_state() -> HudState:
	return track(HudState.new()) as HudState


func test_a_sub_epsilon_change_says_nothing() -> void:
	var state := _make_state()
	state.power = 0.5
	var heard := []
	state.power_changed.connect(func(fraction: float) -> void: heard.append(fraction))
	state.power = 0.5 + HudState.CHANGE_EPSILON * 0.5
	assert_eq(heard.size(), 0, "a move smaller than the epsilon is not announced")


func test_a_real_change_says_so_once() -> void:
	var state := _make_state()
	state.power = 0.5
	var heard := []
	state.power_changed.connect(func(fraction: float) -> void: heard.append(fraction))
	state.power = 0.75
	assert_eq(heard.size(), 1, "one change, one signal")
	assert_eq(heard[0], 0.75, "carrying the new value")


func test_fractions_are_clamped_before_they_are_stored() -> void:
	var state := _make_state()
	state.power = 2.0
	assert_eq(state.power, 1.0, "over-full is full")
	state.oxygen = -1.0
	assert_eq(state.oxygen, 0.0, "and below empty is empty")


## The readout shows whole metres, so a tether creeping across a metre boundary is
## the only movement that can change what is on screen.
func test_the_tether_only_speaks_in_whole_metres() -> void:
	var state := _make_state()
	state.tether_attached = true
	state.tether_metres = 33.1
	var heard := []
	state.tether_changed.connect(
		func(attached: bool, metres: float) -> void: heard.append([attached, metres])
	)
	state.tether_metres = 33.4
	assert_eq(heard.size(), 0, "still thirty-three metres, so still nothing to say")
	state.tether_metres = 33.6
	assert_eq(heard.size(), 1, "thirty-four is a different readout")


func test_unclipping_always_speaks_even_at_the_same_distance() -> void:
	var state := _make_state()
	state.tether_attached = true
	state.tether_metres = 12.0
	var heard := []
	state.tether_changed.connect(func(_attached: bool, _metres: float) -> void: heard.append(true))
	state.tether_attached = false
	assert_eq(heard.size(), 1, "the attachment changed even though the number did not")


func test_status_only_speaks_on_a_change() -> void:
	var state := _make_state()
	state.status = HudState.Status.STRAINED
	var heard := []
	state.status_changed.connect(func(value: int) -> void: heard.append(value))
	state.status = HudState.Status.STRAINED
	assert_eq(heard.size(), 0, "the same face is not news")
	state.status = HudState.Status.CRITICAL
	assert_eq(heard.size(), 1, "a different one is")


## The thresholds live here rather than in the demo driver so the HUD cannot disagree
## with itself about when to look worried. Pinned by value, because a face that
## changes at a different number than the team agreed is a silent regression.
func test_the_face_changes_at_the_stated_thresholds() -> void:
	assert_eq(HudState.status_for(1.0), HudState.Status.NOMINAL, "full is green")
	assert_eq(
		HudState.status_for(HudState.STRAINED_BELOW - 0.01),
		HudState.Status.STRAINED,
		"just under the strain threshold is yellow"
	)
	assert_eq(
		HudState.status_for(HudState.STRAINED_BELOW),
		HudState.Status.NOMINAL,
		"and exactly on it is still green"
	)
	assert_eq(
		HudState.status_for(HudState.CRITICAL_BELOW - 0.01),
		HudState.Status.CRITICAL,
		"just under the critical threshold is red"
	)
	assert_eq(HudState.status_for(0.0), HudState.Status.CRITICAL, "empty is red")


func test_the_objective_ignores_a_move_it_cannot_show() -> void:
	var state := _make_state()
	state.set_objective(true, Vector2(0.5, 0.5))
	var heard := []
	state.objective_changed.connect(func(_shown: bool, _at: Vector2) -> void: heard.append(true))
	state.set_objective(true, Vector2(0.5, 0.5))
	assert_eq(heard.size(), 0, "same place, same state")
	state.set_objective(false, Vector2(0.5, 0.5))
	assert_eq(heard.size(), 1, "losing it is a change")


## This is what makes hot-swapping a variant correct. Every widget in the incoming
## HUD connects and then gets told where things stand, in one pass.
func test_announce_all_fires_every_signal_exactly_once() -> void:
	var state := _make_state()
	var heard := {}
	state.power_changed.connect(func(_f: float) -> void: _tally(heard, "power"))
	state.oxygen_changed.connect(func(_f: float) -> void: _tally(heard, "oxygen"))
	state.tether_changed.connect(func(_a: bool, _m: float) -> void: _tally(heard, "tether"))
	state.contacts_changed.connect(func(_c: PackedVector3Array) -> void: _tally(heard, "contacts"))
	state.objective_changed.connect(func(_s: bool, _a: Vector2) -> void: _tally(heard, "objective"))
	state.status_changed.connect(func(_s: int) -> void: _tally(heard, "status"))
	state.health_changed.connect(func(_f: float) -> void: _tally(heard, "health"))
	state.electrified_changed.connect(func(_a: bool) -> void: _tally(heard, "electrified"))
	state.damaged.connect(func(_s: float) -> void: _tally(heard, "damaged"))

	state.announce_all()

	for key in [
		"power", "oxygen", "health", "electrified", "tether", "contacts", "objective", "status"
	]:
		assert_eq(heard.get(key, 0), 1, "%s announced exactly once" % key)
	# An event rather than state: there is no last hit to re-announce, and a visor
	# that flashed red every time a HUD bound would be lying about what just happened.
	assert_eq(heard.get("damaged", 0), 0, "damaged is an event, not state")


func _tally(counts: Dictionary, key: String) -> void:
	counts[key] = counts.get(key, 0) + 1


## The bug this catches is a HUD that binds at 10 health and draws a clean visor,
## which is indistinguishable from a HUD that works.
func test_health_gates_and_clamps_like_every_other_fraction() -> void:
	var state := _make_state()
	state.health = 0.5
	var heard := []
	state.health_changed.connect(func(fraction: float) -> void: heard.append(fraction))
	state.health = 0.5 + HudState.CHANGE_EPSILON * 0.5
	assert_eq(heard.size(), 0, "a move smaller than the epsilon is not announced")
	state.health = 2.0
	assert_eq(state.health, 1.0, "clamped before it is stored")
	state.health = -1.0
	assert_eq(state.health, 0.0)
	assert_eq(heard.size(), 2, "one signal per real change")
