extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## NavigationConfig and ClearanceProfile.
##
## Every invariant below describes a setting that produces a WORKING BUILD and a broken
## alien. A zero world mask does not error -- it makes every shape cast report clear
## space, so the bake connects every node to every other through solid rock and the
## overlay looks busy and healthy. `invariant_failures()` is what turns each of those
## into a line in the log, and `verify_navigation_static.gd` fails CI if the shipped
## defaults ever violate one.


func test_the_shipped_defaults_satisfy_every_invariant() -> void:
	assert_eq(
		NavigationConfig.new().invariant_failures(),
		PackedStringArray(),
		"the defaults a bare CreatureNavigation runs on must themselves be valid"
	)


func test_a_bare_config_is_usable_without_a_tres() -> void:
	var config := NavigationConfig.new()
	assert_not_null(config.clearance_profile, "the one Resource-typed field needs a default too")
	assert_gt(config.clearance_profile.normal_body().get_class().length(), 0)


func test_a_zero_world_mask_is_rejected() -> void:
	_config.world_mask = 0
	assert_gt(
		_config.invariant_failures().size(),
		0,
		"a mask of 0 makes every cast report clear space: an alien that fits everywhere"
	)


func test_decimation_that_would_accept_the_whole_lattice_is_rejected() -> void:
	_config.candidate_spacing = 4.0
	_config.node_separation = 2.0
	assert_gt(_config.invariant_failures().size(), 0)


func test_an_edge_radius_that_cannot_reach_a_neighbour_is_rejected() -> void:
	_config.node_separation = 8.0
	_config.edge_search_radius = 8.0
	assert_gt(
		_config.invariant_failures().size(),
		0,
		"no accepted node can be within node_separation of another, so no edge could form"
	)


func test_a_wiggle_speed_that_is_not_slower_is_rejected() -> void:
	_config.wiggle_speed = _config.normal_speed
	assert_gt(_config.invariant_failures().size(), 0, "section 10.2 requires wiggle to be slower")


func test_a_clearance_ceiling_below_the_body_is_rejected() -> void:
	_config.clearance_ceiling = 0.5
	assert_gt(
		_config.invariant_failures().size(),
		0,
		"every node would measure tighter than the normal body and the graph would read as wiggle-only"
	)


func test_a_squeeze_that_enlarges_the_alien_is_rejected() -> void:
	_config.clearance_profile.squeezed_radius_equivalent = 4.0
	_config.clearance_profile.normal_radius_equivalent = 1.0
	assert_gt(_config.clearance_profile.invariant_failures().size(), 0)


func test_profile_clearances_include_the_safety_margin() -> void:
	var profile := ClearanceProfile.new()
	profile.normal_radius_equivalent = 1.0
	profile.squeezed_radius_equivalent = 0.5
	profile.safety_margin = 0.2

	assert_almost_eq(profile.normal_clearance(), 1.2, 0.001)
	# Section 12.1's candidate reject threshold, and the whole of Invariant 5.
	assert_almost_eq(profile.min_traversal_clearance(), 0.7, 0.001)


func test_the_default_squeeze_is_about_a_metre_of_diameter() -> void:
	var profile := ClearanceProfile.new()
	var reduction: float = (
		(profile.normal_radius_equivalent - profile.squeezed_radius_equivalent) * 2.0
	)
	assert_almost_eq(reduction, 1.0, 0.05, "section 6 puts the squeeze at ~1.0 m of diameter")


func test_the_fallback_bodies_track_their_radii() -> void:
	var profile := ClearanceProfile.new()
	var before: float = (profile.normal_body() as SphereShape3D).radius
	profile.normal_radius_equivalent += 1.0
	var after: float = (profile.normal_body() as SphereShape3D).radius

	assert_almost_eq(
		after - before,
		1.0,
		0.001,
		"a cached sphere would keep validating edges against the body size the alien had two seconds ago"
	)


func test_an_explicit_shape_wins_over_the_radius() -> void:
	var profile := ClearanceProfile.new()
	var capsule := SphereShape3D.new()
	capsule.radius = 9.0
	profile.normal_shape = capsule

	assert_eq(
		profile.normal_body(),
		capsule,
		"section 6: actual feasibility is determined using the collision shapes"
	)
