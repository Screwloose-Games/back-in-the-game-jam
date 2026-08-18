extends "res://gameplay/director/tests/director_test_case.gd"

## Target arbitration (director.md, "Suspicion -- read only").
##
## Stickiness lives in the Director rather than in Suspicion because Suspicion's job is to be
## accurate, and accuracy oscillates. Committing to a slightly-wrong target is a Director
## decision, and these are the rules for making it.


func test_the_director_names_the_only_candidate_there_is() -> void:
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_advance(0.5)
	assert_eq(_directive().target, player, "somebody has to be first")


func test_a_marginally_better_rival_does_not_take_the_encounter() -> void:
	# director.md's first worked line: P1 .72, P2 .76, margin .04 -> stay on Player 1.
	var one: Node3D = _player("Player1")
	var two: Node3D = _player("Player2")
	_see(one, Vector3(4.0, 0.0, 0.0))
	_advance(_config.min_target_commit_s + 1.0)
	assert_eq(_directive().target, one, "committed to Player 1 first")

	_see(two, Vector3(6.0, 0.0, 0.0), 0.2)
	_advance(1.0)
	var lead: float = _suspicion.get_player_suspicion(two) - _suspicion.get_player_suspicion(one)
	assert_lt(lead, _config.retarget_margin, "the rival is ahead, but not decisively")
	assert_eq(_directive().target, one, "so the encounter stays where it is")


func test_a_decisively_better_rival_takes_it() -> void:
	# The second worked line: P1 .55, P2 .94, margin .39 -> switch to Player 2.
	var one: Node3D = _player("Player1")
	var two: Node3D = _player("Player2")
	_see(one, Vector3(4.0, 0.0, 0.0), 0.3)
	_advance(_config.min_target_commit_s + 1.0)
	assert_eq(_directive().target, one)

	for _i: int in 30:
		_see(two, Vector3(6.0, 0.0, 0.0), 1.0)
		_advance(0.1)
	var lead: float = _suspicion.get_player_suspicion(two) - _suspicion.get_player_suspicion(one)
	assert_gt(lead, _config.retarget_margin, "decisively more compelling")
	assert_eq(_directive().target, two, "and the encounter follows")


func test_no_rival_wins_inside_the_commitment_window() -> void:
	var one: Node3D = _player("Player1")
	var two: Node3D = _player("Player2")
	_see(one, Vector3(4.0, 0.0, 0.0), 0.2)
	_advance(0.5)
	assert_eq(_directive().target, one)

	for _i: int in 20:
		_see(two, Vector3(6.0, 0.0, 0.0), 1.0)
		_advance(0.05)
	assert_eq(_directive().target, one, "however far ahead, not before min_target_commit_s")

	_advance(_config.min_target_commit_s)
	assert_eq(_directive().target, two, "and the moment the window closes, it switches")


func test_losing_sight_of_everybody_does_not_drop_a_committed_target() -> void:
	# Hunting is a commitment that survives brief perception loss. HuntingState already falls
	# back to the strongest lead when the target has no attributed hotspot, so a Director that
	# released on a null candidate would be undoing that from above.
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_directive().target, player)

	_suspicion.reset()
	_advance(2.0)
	assert_null(_suspicion.get_best_player_candidate(), "belief is gone")
	assert_eq(_directive().target, player, "the commitment is not")


func test_a_freed_target_is_released_at_once_rather_than_published_dangling() -> void:
	var player: Node3D = Node3D.new()
	player.name = "Player1"
	_see(player, Vector3(4.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_directive().target, player)

	_suspicion.reset()
	player.free()
	_advance(0.1)
	assert_null(_directive().target, "released, and the commit window deliberately did not apply")


func test_the_encounter_ending_breaks_the_commitment() -> void:
	# Stickiness is a commitment to an ENCOUNTER, not to a person. The same player may well be
	# re-arbitrated on the very next tick -- belief still names them, and pretending otherwise
	# would be the Director editing belief -- but the COMMITMENT must not carry over, or
	# min_target_commit_s measured from the last encounter would make the next one
	# unswitchable for its first eight seconds however compelling somebody else became.
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_hunt(0.0, true, true)
	_advance(2.0)
	var committed_at: float = _track().target_committed_at
	assert_eq(_directive().target, player, "committed during the encounter")

	_advance(20.0)
	_state(CreatureState.State.UNALERTED, Vector3(100.0, 0.0, 0.0))
	_advance(_config.cooldown_s + 2.0)
	assert_eq(_phase(), EncounterDirective.Phase.QUIET, "the encounter is over")
	assert_gt(_track().target_committed_at, committed_at, "and the commitment was taken fresh")


func test_every_change_of_target_is_announced() -> void:
	var player: Node3D = _player("Player1")
	_see(player, Vector3(4.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_targets.size(), 1, "one change, announced once")
	assert_eq(_targets[0], [null, player], "from nobody, to Player 1")
	_advance(5.0)
	assert_eq(_targets.size(), 1, "and not re-announced every tick")


func test_the_directive_names_a_node_and_never_leaks_where_it_is() -> void:
	# THE ASYMMETRY THE WHOLE MODULE RESTS ON. The alien is told WHO, and still has to find
	# them itself. roam_anchor is the only Vector3 that leaves the Director, it is the party
	# centroid rather than the target's transform, and it weights a list of nests the creature
	# already knows rather than being navigated to.
	var player: Node3D = _player("Player1", Vector3(37.0, 0.0, -4.0))
	_see(player, Vector3(4.0, 0.0, 0.0))
	_advance(1.0)
	assert_eq(_directive().target, player, "a Node, not a place")
	assert_eq(_directive().roam_anchor, _member.position, "the anchor is the party, not the target")
	assert_ne(
		_directive().roam_anchor, player.position, "and standing somewhere else does not move it"
	)


func test_a_creature_with_no_belief_gets_no_target_rather_than_an_error() -> void:
	var bare: Node = autofree(Node.new())
	_director.register(bare)
	_director.advance(0.1)
	assert_null(_director.track_for(bare).directive.target, "nothing to arbitrate between")
