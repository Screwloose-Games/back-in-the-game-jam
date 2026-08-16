extends "res://gameplay/director/tests/director_test_case.gd"

## director.md's worked encounter, end to end (director.md, "Worked encounter").
##
## ```text
## t+0    QUIET     lull .6 after two quiet minutes -> bias +.3, roam +.6
## t+12   player drills -> INVESTIGATING. BUILD, lull zeroed.
## t+31   player seen -> HUNTING. permit_hunt true, target Player 1, lethality GRACE.
## t+44   attack window -> near-miss. lethality flips to LETHAL for the rest.
## t+52   player reaches a tunnel it cannot enter. menace .87 on lurk pressure.
## t+58   menace 1.00 -> PEAK. force_disengage, SATED. RELIEF: bias -.4, roam -.8.
## t+71   separation met -> UNALERTED
## t+79   cooldown expires -> QUIET, lull begins rising again
## ```
##
## "No system contains this script. Each value moved for its own reason" -- so this asserts
## the SHAPE and the stated values, in bands rather than to the frame. The trace's own
## intermediate menace figures are not reproducible under any single linear rate (0 to .87 in
## 21 s is .041/s, then .87 to 1.00 in 6 s is .022/s, with strictly more terms on in the
## second window), so the calibration target is the headline claim: a hunt begun at t+31
## sates at t+58, which is 27 seconds.


func test_the_whole_encounter() -> void:
	var player: Node3D = _player("Player1", Vector3(30.0, 0.0, 0.0))
	_director.players = [player]

	# t+0 -- two quiet minutes.
	_advance(120.0)
	assert_almost_eq(_director.lull, 0.6, 0.02, "t+0: lull .6")
	assert_almost_eq(_directive().escalation_bias, 0.3, 0.02, "t+0: bias +.3")
	assert_almost_eq(_directive().roam_bias, 0.6, 0.02, "t+0: roam +.6")
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "t+0: QUIET")
	assert_eq(_directive().roam_anchor, player.position, "and drifting toward the party")

	# t+12 -- the drill becomes a lead. Behavior transitions; the Director reads the state.
	_state(CreatureState.State.INVESTIGATING)
	_tick()
	assert_eq(_phase(), EncounterDirective.Phase.BUILD, "t+12: BUILD")
	assert_eq(_director.lull, 0.0, "t+12: lull zeroed")

	# t+31 -- seen. Permission was never withheld, and the first encounter teaches.
	_advance(19.0)
	for _i: int in 20:
		_see(player, Vector3(6.0, 0.0, 0.0))
		_advance(0.05)
	_hunt(8.0, true)
	_tick()
	assert_true(_directive().permit_hunt, "t+31: permit_hunt true")
	assert_eq(_directive().target, player, "t+31: target = Player 1")
	assert_eq(_directive().lethality, EncounterDirective.Lethality.GRACE, "t+31: GRACE")

	# t+44 -- the window opens, the near-miss lands, and the grace is spent.
	_hunt(2.0, true, true)
	_advance(13.0)
	_creature.strike(EncounterDirective.Lethality.GRACE)
	_tick()
	assert_eq(_directive().lethality, EncounterDirective.Lethality.LETHAL, "t+44: LETHAL, for good")

	# t+52 -- into a tunnel it cannot follow. It waits at the mouth, and that is pressure.
	_hunt(3.0, false, false, true)
	_advance(8.0)
	assert_gt(_track().menace, 0.6, "t+52: menace high on lurk pressure")

	# t+58 -- the meter fills. The earned exit.
	_advance(20.0)
	assert_eq(_disengages, [EncounterDirective.Reason.SATED], "t+58: force_disengage, SATED")
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF, "t+58: RELIEF")
	assert_false(_directive().permit_hunt, "t+58: permit_hunt false")
	assert_almost_eq(_directive().escalation_bias, -0.4, 0.02, "t+58: bias -.4")
	assert_almost_eq(_directive().roam_bias, -0.8, 0.02, "t+58: roam -.8")

	# t+71 -- Behavior reaches UNALERTED on its own separation rule.
	_state(CreatureState.State.UNALERTED, Vector3(40.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_phase(), EncounterDirective.Phase.RELIEF, "t+71: still cooling down")

	# t+79 -- the cooldown expires and the cycle turns over.
	_advance(_config.cooldown_s)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "t+79: QUIET")
	assert_true(_directive().permit_hunt, "and the alien may hunt again")

	# THE LULL DOES NOT RESTART THE MOMENT THE PHASE DOES, and that is the calm gate rather
	# than a bug. The creature still fully believes the player is there -- the Director never
	# damped that to end the encounter -- and a player who is still being believed in is not
	# experiencing dead air. The clock starts once belief has decayed on its own.
	_advance(10.0)
	assert_gt(
		_suspicion.get_overall_suspicion(), _config.calm_suspicion_threshold, "still believed"
	)
	assert_eq(_director.lull, 0.0, "so it is not dead air yet")

	_advance(90.0)
	assert_lt(_suspicion.get_overall_suspicion(), _config.calm_suspicion_threshold, "belief faded")
	assert_gt(_director.lull, 0.0, "t+79 onward: lull begins rising again")


func test_the_phase_log_reads_as_the_diagram() -> void:
	var player: Node3D = _player("Player1")
	_director.players = [player]
	_state(CreatureState.State.INVESTIGATING)
	_advance(2.0)
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3(60.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 2.0)
	assert_eq(
		_phase_names(),
		["build", "peak", "relief", "quiet"],
		"quiet -> build -> peak -> relief -> quiet, which is the whole cycle"
	)


func test_a_hunt_begun_at_full_pressure_sates_in_the_calibrated_window() -> void:
	# The trace's t+31 to t+58 is 27 seconds. That is what the menace weights were solved to,
	# so a change that moves it means the config's own calibration comments have gone stale.
	_hunt(0.0, true)
	var began: float = _director.clock
	for _i: int in 3000:
		_tick()
		if not _disengages.is_empty():
			break
	assert_between(_director.clock - began, 24.0, 32.0, "27 s, to within a few seconds")
	assert_eq(_disengages, [EncounterDirective.Reason.SATED], "and it earned the exit")
