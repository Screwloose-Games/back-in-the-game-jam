extends "res://gameplay/director/tests/director_test_case.gd"

## Kill grace (director.md, "Kill grace").
##
## Behavior owns the animation and the damage; the Director owns only the flag. These assert
## the flag, and in particular the latch -- because a horror game the player knows cannot
## kill them has no remaining mechanism.


func test_the_first_encounter_of_a_session_teaches_rather_than_kills() -> void:
	_hunt(0.0, true, true)
	_advance(10.0)
	assert_gt(_track().menace, _config.lethal_menace_threshold, "menace would otherwise be lethal")
	assert_eq(_directive().lethality, EncounterDirective.Lethality.GRACE, "but nothing has peaked")


func test_turning_off_first_encounter_grace_removes_that_clause() -> void:
	_config.first_encounter_grace = false
	_hunt(0.0, true, true)
	_advance(10.0)
	assert_eq(_directive().lethality, EncounterDirective.Lethality.LETHAL, "a level that taught")


func test_an_encounter_that_has_not_earned_its_payoff_resolves_as_a_near_miss() -> void:
	_config.first_encounter_grace = false
	_hunt(0.0, true, true)
	_advance(1.0)
	assert_lt(_track().menace, _config.lethal_menace_threshold, "barely started")
	assert_eq(_directive().lethality, EncounterDirective.Lethality.GRACE)


func test_a_session_that_has_peaked_kills_from_then_on() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 2.0)

	_hunt(0.0, true, true)
	_advance(10.0)
	assert_eq(
		_directive().lethality,
		EncounterDirective.Lethality.LETHAL,
		"the first one taught; this one does not have to"
	)


func test_one_near_miss_per_encounter_and_then_it_is_lethal() -> void:
	# THE LATCH, AND IT OUTRANKS EVERY OTHER CLAUSE. After a grace hit lands the encounter is
	# lethal for the rest of its length even with menace still under the threshold -- without
	# it a player eventually notices they are safe.
	_hunt(0.0, true, true)
	_advance(1.0)
	assert_eq(_directive().lethality, EncounterDirective.Lethality.GRACE, "the first swing")

	_creature.strike(EncounterDirective.Lethality.GRACE)
	_advance(0.1)
	assert_eq(_directive().lethality, EncounterDirective.Lethality.LETHAL, "the grace is spent")
	assert_true(_track().grace_consumed)


func test_a_lethal_strike_spends_no_grace() -> void:
	_config.first_encounter_grace = false
	_hunt(0.0, true, true)
	_advance(10.0)
	_creature.strike(EncounterDirective.Lethality.LETHAL)
	_advance(0.1)
	assert_false(_track().grace_consumed, "there was nothing to spend")


func test_the_latch_clears_when_the_encounter_does() -> void:
	_config.first_encounter_grace = false
	_hunt(0.0, true, true)
	_advance(1.0)
	_creature.strike(EncounterDirective.Lethality.GRACE)
	_advance(0.1)
	assert_true(_track().grace_consumed)

	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_track().menace / _config.menace_relief_rate + 1.0)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "the encounter is over")
	assert_false(_track().grace_consumed, "and the next one gets its own near-miss")


func test_a_freshly_respawned_player_keeps_grace() -> void:
	_config.first_encounter_grace = false
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_hunt(0.0, true, true)
	_advance(10.0)
	assert_eq(_directive().lethality, EncounterDirective.Lethality.LETHAL, "lethal to begin with")

	_director.note_respawn(player)
	_advance(0.1)
	assert_eq(
		_directive().lethality, EncounterDirective.Lethality.GRACE, "not straight off a spawn"
	)


func test_respawn_grace_expires() -> void:
	_config.first_encounter_grace = false
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_hunt(0.0, true, true)
	_advance(5.0)
	_director.note_respawn(player)
	_advance(_config.respawn_grace_s + 1.0)
	assert_eq(_directive().lethality, EncounterDirective.Lethality.LETHAL, "the grace ran out")


func test_lethality_is_announced_once_per_change_rather_than_once_per_tick() -> void:
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_eq(_lethalities.size(), 2, "GRACE at the start, LETHAL once the session peaked")
	assert_eq(_lethalities[0], EncounterDirective.Lethality.GRACE)
	assert_eq(_lethalities[1], EncounterDirective.Lethality.LETHAL)
