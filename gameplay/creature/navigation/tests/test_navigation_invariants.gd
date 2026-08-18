extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Section 42's invariants, as assertions rather than as prose.
##
## EVERY ONE OF THESE PASSES THE REST OF THE SUITE WHILE BREAKING THE DESIGN. A NavGraph
## that grew a `can_traverse()` would satisfy every edge-validation test and would also
## be the exact confusion Invariant 2 exists to prevent. A CreatureNavigation that
## remembered where the player was last seen would make the alien work noticeably
## better, and nothing else here would notice.


## Invariant 1 and section 2.2. Anchors are places the topology connects, not positions
## the centre of mass must occupy -- decimation deliberately keeps the MOST OPEN
## candidate in each neighbourhood, so in a chamber the anchor sits near the middle
## while the alien crawls the wall.
func test_the_graph_does_not_claim_physical_traversability() -> void:
	var forbidden: Array[String] = [
		"can_traverse", "can_move_through", "is_traversable", "is_walkable", "move_along"
	]
	var graph := NavGraph.new()
	for name: String in forbidden:
		assert_false(
			graph.has_method(name),
			(
				"NavGraph.%s would assert what Invariant 2 forbids: connectivity is not permission to move"
				% name
			)
		)


## Invariant 9 and section 27. The graph is a plain data structure that knows nothing
## about where it came from, which is what lets a believed graph and a real one be the
## same type when Spatial Memory lands.
func test_the_graph_holds_no_reference_to_a_probe_or_builder() -> void:
	var graph: NavGraph = _bake(_open_room())
	for property: Dictionary in _declared_properties(graph):
		var value: Variant = graph.get(property["name"])
		assert_false(
			value is NavigationProbe,
			(
				"NavGraph.%s holds a probe; the graph must not be able to re-measure the world"
				% property["name"]
			)
		)
		assert_false(
			value is NavGraphBuilder,
			(
				"NavGraph.%s holds a builder; a believed graph would have nothing to put there"
				% property["name"]
			)
		)


## Section 44's boundary: navigation does not own player detection, and section 31
## forbids it from remembering anything about a target beyond the goal it was handed.
func test_navigation_remembers_nothing_about_the_player() -> void:
	var navigation := CreatureNavigation.new()
	var forbidden: Array[String] = [
		"last_known_position", "player", "quarry", "target_node", "suspicion", "alertness"
	]
	var declared: Array[String] = []
	for property: Dictionary in _declared_properties(navigation):
		declared.append(property["name"])
	for name: String in forbidden:
		assert_does_not_have(
			declared, name, "CreatureNavigation.%s would make the alien omniscient for free" % name
		)
	navigation.free()


## Section 44 again. This module replaces NavigationServer3D rather than wrapping it,
## and a stray agent means two navigation systems quietly disagreeing about where the
## alien should be.
func test_navigation_exposes_no_godot_navigation_agent() -> void:
	var navigation := CreatureNavigation.new()
	for property: Dictionary in _declared_properties(navigation):
		assert_false(
			navigation.get(property["name"]) is NavigationAgent3D,
			"CreatureNavigation.%s is a NavigationAgent3D" % property["name"]
		)
	navigation.free()


## Only what the SCRIPT declares, never the whole inherited property list.
##
## Reading every property of a Node3D that was never added to a tree makes the engine
## evaluate `global_transform` and log "Condition !is_inside_tree() is true" five times,
## which GUT counts as an unexpected error and fails the test on. The inherited half is
## Godot's anyway, and no invariant here is about it.
func _declared_properties(target: Object) -> Array:
	var script: Script = target.get_script() as Script
	if script == null:
		return []
	return script.get_script_property_list()


## Invariant 3. The only mode allowed to cross unsupported open space is LEAP, and LEAP
## is Phase 6. Until then nothing may approve a shortcut on the grounds that it is
## merely unobstructed.
func test_no_mode_approves_unsupported_open_space() -> void:
	var follower: RouteFollower = _follower()
	# No geometry at all: everything is open, everything is unsupported.
	assert_false(
		follower.can_skip_to(Vector3.ZERO, Vector3(30, 0, 0), NavLocomotion.Mode.SURFACE_CRAWL)
	)
	assert_false(follower.can_skip_to(Vector3.ZERO, Vector3(30, 0, 0), NavLocomotion.Mode.LEAP))


## Section 6 and Invariant 5. Body size is the only thing that decides accessibility,
## so a profile is the only input a passability question takes.
func test_passability_comes_from_the_profile_alone() -> void:
	var profile: ClearanceProfile = _config.clearance_profile
	var wide := ClearanceProfile.new()
	wide.squeezed_radius_equivalent = 4.0
	wide.normal_radius_equivalent = 5.0

	assert_gt(
		wide.min_traversal_clearance(),
		profile.min_traversal_clearance(),
		"a bigger alien must need more room, with no flag anywhere saying so"
	)


## An unbound probe must make the alien immobile, never omniscient. Perception's probe
## defaults the other way on purpose -- a deaf creature is visibly broken, while a
## creature that fits through walls looks like it is working.
func test_an_unbound_probe_refuses_everything() -> void:
	var probe := NavigationProbe.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0

	assert_false(probe.is_bound())
	assert_eq(
		probe.clearance_at(Vector3.ZERO, 1, 6.0, 6), 0.0, "unbound must not report open space"
	)
	assert_false(probe.shape_fits(sphere, Transform3D.IDENTITY, 1))
	assert_false(probe.shape_sweep_clear(sphere, Vector3.ZERO, Vector3(5, 0, 0), 1))


## Section 30. Navigation issues inspection requests and nothing else; the behaviour
## system decides what an inspection looks like. The request has to carry enough for a
## consumer to act without asking navigation anything further.
func test_an_inspection_request_carries_where_why_and_which_chunk() -> void:
	var request := NavInspectionRequest.make(
		Vector3(40.0, 4.0, 8.0), NavInspectionRequest.Reason.STALE_ROUTE, 16.0
	)
	assert_eq(request.position, Vector3(40.0, 4.0, 8.0))
	assert_eq(request.reason, NavInspectionRequest.Reason.STALE_ROUTE)
	assert_eq(request.affected_chunk, Vector3i(2, 0, 0), "section 25's chunk id")
