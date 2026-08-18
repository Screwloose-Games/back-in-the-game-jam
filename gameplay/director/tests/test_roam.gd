extends "res://gameplay/director/tests/director_test_case.gd"

## Ambient placement bias (director.md, "Ambient placement bias").
##
## The Director's only reach into where the alien goes, and it is a WEIGHTING rather than a
## destination. The anchor weights a list of nests the creature already knows; it is never
## itself a goal, and it never creates one.


func test_the_anchor_is_the_party_centroid() -> void:
	var second: Node3D = autofree(Node3D.new())
	second.position = Vector3(0.0, 0.0, 40.0)
	_director.players = [_member, second]
	_advance(1.0)
	assert_eq(
		_directive().roam_anchor,
		(_member.position + second.position) * 0.5,
		"the middle of the party, not the nearest member"
	)


func test_the_anchor_follows_the_party_as_it_moves() -> void:
	_advance(1.0)
	assert_eq(_directive().roam_anchor, Vector3(20.0, 0.0, 0.0))
	_member.position = Vector3(-15.0, 0.0, 8.0)
	_advance(1.0)
	assert_eq(_directive().roam_anchor, Vector3(-15.0, 0.0, 8.0))


func test_a_freed_party_member_is_dropped_rather_than_averaged_in() -> void:
	var doomed: Node3D = Node3D.new()
	doomed.position = Vector3(0.0, 0.0, 100.0)
	_director.players = [_member, doomed]
	_advance(0.5)
	doomed.free()
	_advance(0.5)
	assert_eq(_directive().roam_anchor, _member.position, "back to the one member left")


func test_boredom_drifts_the_alien_toward_the_party() -> void:
	_advance(_config.lull_full_s)
	assert_almost_eq(_directive().roam_bias, _config.max_roam_bias, 0.01, "fully drawn in")


func test_a_retreat_clears_the_alien_out() -> void:
	# "negative bias during RELIEF clears it out, so a retreat actually creates space."
	_hunt(0.0, true, true)
	_advance(22.0)
	assert_lt(_directive().roam_bias, 0.0, "pushed away rather than merely not drawn in")


func test_the_roam_term_actually_moves_a_nest_score() -> void:
	# The consumer is CreatureNestMemory.score, which is where the directive's roam_bias lands.
	# Asserting the sign here rather than only in Behavior keeps the two halves of one formula
	# honest about which way they push.
	var behavior := BehaviorConfig.new()
	var near_the_party: float = CreatureNestMemory.score(20.0, 999.0, 2.0, 0.0, false, behavior)
	var drawn_in: float = CreatureNestMemory.score(20.0, 999.0, 2.0, 1.0, false, behavior)
	var pushed_out: float = CreatureNestMemory.score(20.0, 999.0, 2.0, -1.0, false, behavior)
	assert_gt(drawn_in, near_the_party, "a positive roam makes a nest near the party better")
	assert_lt(pushed_out, near_the_party, "and a negative one makes it worse")


func test_the_anchor_is_never_offered_as_somewhere_to_go() -> void:
	# director.md: "It is never a navigation destination, and it never creates a nest." There
	# is no goal, destination or position field on the directive at all -- the anchor is the
	# only Vector3 that leaves the module, and Behavior spends it as a weight.
	var directive: EncounterDirective = _directive()
	assert_false(directive.has_method(&"set_goal"))
	var names := PackedStringArray()
	for entry: Dictionary in directive.get_property_list():
		names.append(entry.name)
	assert_does_not_have(names, "goal", "no goal on the directive")
	assert_does_not_have(names, "destination", "and nowhere it is being sent")
	assert_does_not_have(names, "target_position", "and no position for the target either")
