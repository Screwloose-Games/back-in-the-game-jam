extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## Per-player belief, and what the Director reads (suspicion.md, "Player Suspicion").
##
## Two things are being kept apart throughout: WHERE the creature thinks activity is,
## and WHO it thinks is responsible. A hotspot can be strong and completely anonymous,
## and one player can be behind three hotspots at once, so neither answer can be
## derived from the other.


func test_a_noise_makes_the_creature_suspicious_of_nobody_in_particular() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise()

	assert_gt(hotspot.suspicion, 0.0, "something is happening")
	assert_null(hotspot.likely_source, "but a noise is just a noise")
	assert_eq(hotspot.source_confidence, 0.0)
	assert_null(_suspicion.get_best_player_candidate())


func test_a_sighting_attributes_the_activity_to_that_player() -> void:
	var player: Node3D = _player("Player1")

	_suspicion.submit_evidence(_see(Vector3.ZERO, player))
	_settle()

	assert_gt(_suspicion.get_player_suspicion(player), 0.0)
	assert_gt(_suspicion.get_player_source_confidence(player), 0.5)
	assert_eq(_suspicion.get_strongest_hotspot().likely_source, player)


## The spec's worked example: a hotspot that starts anonymous acquires a likely source
## once corroborating evidence lands in it, without the hotspot itself being replaced.
func test_an_anonymous_hotspot_can_later_acquire_a_likely_source() -> void:
	var player: Node3D = _player("Player1")
	var hotspot_id: int = _hotspot_from_one_noise(Vector3.ZERO, 3.0).id
	assert_null(_suspicion.get_hotspot(hotspot_id).likely_source)

	_suspicion.submit_evidence(_see(Vector3(1, 0, 0), player))
	_advance(0.5)

	var hotspot: SuspicionHotspot = _suspicion.get_hotspot(hotspot_id)
	assert_not_null(hotspot, "the same hotspot, not a replacement")
	assert_eq(hotspot.likely_source, player)
	assert_gt(hotspot.source_confidence, 0.5)


func test_the_director_gets_the_most_suspicious_player_first() -> void:
	var loud: Node3D = _player("Player1")
	var quiet: Node3D = _player("Player2")

	for _repeat: int in 4:
		_suspicion.submit_evidence(_see(Vector3.ZERO, loud))
	_suspicion.submit_evidence(_see(Vector3(40, 0, 0), quiet, 0.3))
	_settle()

	var best: PlayerSuspicionCandidate = _suspicion.get_best_player_candidate()
	assert_eq(best.player, loud)
	assert_gt(_suspicion.get_player_suspicion(loud), _suspicion.get_player_suspicion(quiet))


## Attribution is a belief like any other: it fades when nothing renews it. A player
## who has been quiet for a minute is not still the prime suspect.
func test_player_suspicion_decays_when_nothing_names_them_again() -> void:
	var player: Node3D = _player("Player1")
	_suspicion.submit_evidence(_see(Vector3.ZERO, player))
	_settle()
	var fresh: float = _suspicion.get_player_suspicion(player)

	_advance_coarse(30.0)

	assert_gt(fresh, 0.0)
	assert_lt(_suspicion.get_player_suspicion(player), fresh * 0.5)


func test_asking_about_a_player_the_creature_has_never_perceived_is_zero() -> void:
	assert_eq(_suspicion.get_player_suspicion(_player("Stranger")), 0.0)
	assert_eq(_suspicion.get_player_source_confidence(_player("Stranger")), 0.0)


## A player who disconnects mid-run leaves a freed Node behind. Every read path has to
## survive that: a crash here would take the whole creature down for a reason that
## looks nothing like a suspicion bug.
func test_a_player_that_leaves_the_game_is_forgotten_rather_than_dereferenced() -> void:
	var leaver := Node3D.new()
	_suspicion.submit_evidence(_see(Vector3.ZERO, leaver))
	_settle()
	assert_gt(_suspicion.get_player_suspicion(leaver), 0.0)

	leaver.free()
	_advance(0.5)

	assert_null(_suspicion.get_best_player_candidate())
	assert_eq(_suspicion.get_strongest_hotspot().likely_source, null, "and the hotspot drops them")
	assert_gt(
		_suspicion.get_strongest_hotspot().suspicion, 0.0, "but stays suspicious of the place"
	)


func test_player_suspicion_changed_fires_when_new_evidence_names_someone() -> void:
	var player: Node3D = _player("Player1")

	_suspicion.submit_evidence(_see(Vector3.ZERO, player))
	_settle()

	assert_eq(_player_changes.size(), 1)
	assert_eq(_player_changes[0][0], player)
	assert_gt(float(_player_changes[0][1]), 0.0)


## Unattributed evidence must not quietly become somebody's fault.
func test_an_unattributed_noise_never_reaches_the_player_beliefs() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 1.0))
	_advance(1.0)

	assert_eq(_player_changes.size(), 0)
	assert_null(_suspicion.get_best_player_candidate())


## Once a second player is more confidently attributed, the hotspot follows the
## evidence. Nothing here is stickiness -- that is the Director's, and adding it here
## would make the Director's version impossible to reason about.
func test_a_hotspot_switches_to_a_better_attributed_player() -> void:
	var first: Node3D = _player("Player1")
	var second: Node3D = _player("Player2")
	var glimpse := _see(Vector3.ZERO, first)
	glimpse.source_confidence = 0.3

	_suspicion.submit_evidence(glimpse)
	_settle()
	assert_eq(_suspicion.get_strongest_hotspot().likely_source, first)

	_suspicion.submit_evidence(_see(Vector3(1, 0, 0), second))
	_advance(0.5)

	assert_eq(_suspicion.get_strongest_hotspot().likely_source, second)


func test_candidates_are_reported_strongest_first() -> void:
	var quiet: Node3D = _player("Quiet")
	var loud: Node3D = _player("Loud")
	_suspicion.submit_evidence(_see(Vector3(40, 0, 0), quiet, 0.2))
	for _repeat: int in 5:
		_suspicion.submit_evidence(_see(Vector3.ZERO, loud))
	_settle()

	var candidates: Array[PlayerSuspicionCandidate] = _suspicion.player_beliefs.get_candidates()
	assert_eq(candidates.size(), 2)
	assert_eq(candidates[0].player, loud)
	assert_gte(candidates[0].suspicion, candidates[1].suspicion)
