extends "res://gameplay/creature/behavior/tests/behavior_test_case.gd"

## fsm.md's transition table, one row at a time, plus the three rules that are not rows.
##
## Every guard here has a plausible wrong form that produces a creature which still runs.
## Keying investigate off overall suspicion instead of the strongest hotspot gives an alien
## that enters INVESTIGATING with nowhere to walk. Shifting `direct_hunt_threshold` by the
## Director's bias lets a bored Director make the creature murderous rather than curious.
## Reading `force_disengage` instead of latching it drops the disengage whenever
## `min_dwell_s` blocks the check, and the encounter never ends. None of them error.


func test_a_calm_creature_starts_unalerted() -> void:
	_tick()
	assert_eq(_state(), CreatureState.State.UNALERTED)
	assert_eq(_transitions.size(), 0, "nothing has happened yet")


func test_a_hotspot_over_the_threshold_starts_an_investigation() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	assert_eq(_state(), CreatureState.State.INVESTIGATING)
	assert_eq(_reasons(), [&"hotspot"])


## THE GUARD THIS ROW EXISTS FOR. Overall suspicion is a scalar with no location -- it can
## cross a threshold while giving Behavior nowhere to walk. Keying off the strongest hotspot
## guarantees that entering INVESTIGATING comes with a destination.
func test_investigating_is_entered_with_somewhere_to_go() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	var state := _behavior.hfsm.state_of(CreatureState.State.INVESTIGATING) as InvestigatingState
	assert_true(state.memory.has_location, "the state was entered with no location to walk to")
	assert_ne(state.memory.hotspot_id, -1)


func test_a_noise_too_faint_to_form_a_hotspot_changes_nothing() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 38.0), 1.0, &"footstep")
	_advance(0.5)

	assert_eq(_state(), CreatureState.State.UNALERTED)


## min_dwell_s is a pre-guard on every row, not a row. Without it an alien on a threshold
## boundary flickers between modes and every debug trace becomes unreadable.
func test_nothing_transitions_before_the_dwell_floor() -> void:
	_config.min_dwell_s = 2.0
	_hear(Vector3(0.0, 0.0, 6.0))
	_advance(1.0)
	assert_eq(_state(), CreatureState.State.UNALERTED, "the dwell floor was not honoured")

	_advance(1.5)
	assert_eq(_state(), CreatureState.State.INVESTIGATING)


## Positive bias makes the alien act on weaker evidence. This is the Director's whole reach
## into the investigate decision.
func test_a_positive_escalation_bias_lowers_the_investigate_threshold() -> void:
	_config.investigate_threshold = 0.9
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_advance(0.5)
	assert_eq(_state(), CreatureState.State.UNALERTED, "0.9 should be out of reach unaided")

	_direct().escalation_bias = 1.0
	_config.bias_span = 0.9
	_advance(0.5)
	assert_eq(_state(), CreatureState.State.INVESTIGATING)


func test_a_credible_sighting_turns_an_investigation_into_a_hunt() -> void:
	var player: Node3D = _player("p1")
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()
	assert_eq(_state(), CreatureState.State.INVESTIGATING)

	_advance(_config.min_dwell_s + 0.1)
	for _i: int in 6:
		_see(player, Vector3(0.0, 0.0, 6.0))
		_tick()

	assert_eq(_state(), CreatureState.State.HUNTING)
	assert_eq(_reasons()[-1], &"candidate")


## A hard veto, whatever the evidence says. False throughout the Director's RELIEF phase.
func test_permit_hunt_false_vetoes_the_hunt_at_any_suspicion() -> void:
	var player: Node3D = _player("p1")
	_direct().permit_hunt = false
	_advance(_config.min_dwell_s + 0.1)
	for _i: int in 30:
		_see(player, Vector3(0.0, 0.0, 6.0))
		_tick()

	assert_ne(_state(), CreatureState.State.HUNTING, "the Director's veto was ignored")


## Only vision and touch set source_confidence; hearing deliberately never does. So a noise
## brings the alien looking for you and cannot make it hunt you by name.
func test_noise_alone_never_reaches_the_hunt_guard() -> void:
	_advance(_config.min_dwell_s + 0.1)
	for _i: int in 40:
		_hear(Vector3(0.0, 0.0, 4.0))
		_tick()

	assert_eq(
		_state(), CreatureState.State.INVESTIGATING, "you investigate a where, you hunt a who"
	)


func test_an_investigation_with_nothing_left_to_check_ends() -> void:
	# The timeout is put out of reach so the OTHER half of this row is what fires. With the
	# shipped 45 s a drill's hotspot has not decayed below attention_floor yet, and the two
	# guards would race -- the test would pass on whichever number happened to be smaller.
	_config.investigate_timeout_s = 600.0
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()
	assert_eq(_state(), CreatureState.State.INVESTIGATING)

	# Decay is a closed-form function of age, so one big step is exact and hundreds of times
	# cheaper than ticking through two simulated minutes.
	_behavior.advance(120.0)

	assert_eq(_state(), CreatureState.State.UNALERTED)
	assert_eq(_reasons()[-1], &"nothing_left")


func test_an_investigation_that_takes_too_long_gives_up() -> void:
	_config.investigate_timeout_s = 3.0
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	# Kept alive by fresh noise, so only the timeout can end it.
	for _i: int in 300:
		_hear(Vector3(0.0, 0.0, 6.0))
		_tick()

	# Not the LAST reason: the noise is still arriving, so the hotspot is still there and the
	# alien goes straight back to look again. That is correct -- the timeout is a cap on one
	# investigation, not a refractory period on caring -- and asserting the end state instead
	# would be asserting the fixture's noise loop.
	assert_has(_reasons(), &"timeout", "the investigation ran past its cap and never gave up")


func test_the_director_can_force_a_hunt_to_end() -> void:
	_reach_hunting()
	_direct().force_disengage = true
	_advance(_config.min_dwell_s + 0.2)

	assert_eq(_state(), CreatureState.State.RETREATING)
	assert_eq(_reasons()[-1], &"director")


## LATCHED, NOT READ. director.md has the HFSM consume force_disengage "at its next
## transition check"; with min_dwell_s blocking that check, a directive rebuilt each tick
## would drop the request entirely and the encounter could never end.
func test_a_disengage_asked_for_during_the_dwell_floor_is_not_lost() -> void:
	_config.min_dwell_s = 3.0
	_reach_hunting()
	_direct().force_disengage = true
	_tick()
	_directive.force_disengage = false

	_advance(4.0)
	assert_eq(_state(), CreatureState.State.RETREATING, "the latch was dropped")


## THE ONE-WAY DOOR. There is no path back to HUNTING from a retreat, at any suspicion
## level, for any evidence type -- otherwise the Director cannot reliably terminate an
## encounter, and an encounter that cannot be terminated has no rhythm.
func test_a_retreating_creature_cannot_be_provoked_back_into_hunting() -> void:
	var player: Node3D = _player("p1")
	_reach_hunting()
	_direct().force_disengage = true
	_advance(_config.min_dwell_s + 0.2)
	assert_eq(_state(), CreatureState.State.RETREATING)

	_directive.force_disengage = false
	for _i: int in 120:
		_see(player, _body.position)
		_tick()

	assert_ne(_state(), CreatureState.State.HUNTING, "an alien walking away must stay walking away")


func test_a_retreat_ends_on_time_and_distance() -> void:
	_config.retreat_min_s = 1.0
	_config.retreat_separation_m = 10.0
	_reach_hunting()
	_direct().force_disengage = true
	_advance(_config.min_dwell_s + 0.2)
	assert_eq(_state(), CreatureState.State.RETREATING)

	_advance(2.0)
	assert_eq(_state(), CreatureState.State.RETREATING, "separation is not met yet")

	_place(Vector3(0.0, 0.0, 60.0))
	_advance(0.5)
	assert_eq(_state(), CreatureState.State.UNALERTED)
	assert_eq(_reasons()[-1], &"separated")


func test_every_transition_carries_a_named_reason() -> void:
	_reach_hunting()
	_direct().force_disengage = true
	_advance(_config.min_dwell_s + 0.2)

	assert_gt(_transitions.size(), 1)
	for reason: StringName in _reasons():
		assert_ne(reason, &"", "a transition with no reason is unattributable in debug")


func test_the_debug_line_names_the_value_that_fired_the_last_transition() -> void:
	_advance(_config.min_dwell_s + 0.1)
	_hear(Vector3(0.0, 0.0, 6.0))
	_tick()

	assert_string_contains(_behavior.describe(), "investigating")
	assert_string_contains(_behavior.describe(), "hotspot")


# ----- helpers -----


## Sightings until the hunt guard opens.
##
## Long enough to clear min_dwell_s TWICE, because it takes two transitions to get here from
## calm: a sighting also raises a hotspot, and the table checks the investigate row first, so
## the alien always comes to look before it commits. The dwell floor then holds it in
## INVESTIGATING for a beat before the hunt row can fire.
func _reach_hunting() -> void:
	var player: Node3D = _player("target")
	_advance(_config.min_dwell_s + 0.1)
	for _i: int in int(roundf((_config.min_dwell_s * 3.0 + 1.0) / TICK)):
		_see(player, Vector3(0.0, 0.0, 6.0))
		_tick()
		if _state() == CreatureState.State.HUNTING:
			return
	assert_eq(_state(), CreatureState.State.HUNTING, "the fixture never reached HUNTING")
