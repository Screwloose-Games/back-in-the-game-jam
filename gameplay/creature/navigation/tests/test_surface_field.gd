extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## The surface sampler: the fan, section 9.3's enclosure and section 9.1's medial push.
##
## Split from test_surface_crawl.gd because the two answer different questions -- this
## file is about what the geometry says, that one is about what the alien does with it --
## and because gdlint caps a script at 20 public methods, which a merged suite exceeded.
##
## Everything here is static and takes plain samples, so none of it needs a probe, a body
## or a scene. That is the point of NavSurfaceReading existing as a record.


func _fan_of(samples: Array[NavSurfaceSample]) -> Array[NavSurfaceSample]:
	return samples


func test_the_fan_is_the_same_every_time_it_is_taken() -> void:
	assert_eq(
		NavSurfaceField.fan_directions(9),
		NavSurfaceField.fan_directions(9),
		"a steering decision that differs between two runs is a bug nobody can reproduce"
	)


func test_the_fan_covers_the_sphere_rather_than_one_hemisphere() -> void:
	var sum := Vector3.ZERO
	for direction: Vector3 in NavSurfaceField.fan_directions(12):
		assert_almost_eq(direction.length(), 1.0, 0.0001, "fan directions must be unit")
		sum += direction
	assert_lt(sum.length(), 1.0, "an evenly spread fan very nearly cancels out")


func test_enclosure_is_zero_in_the_open_and_one_inside_a_pipe() -> void:
	var open: Array[NavSurfaceSample] = []
	var closed: Array[NavSurfaceSample] = []
	for direction: Vector3 in NavSurfaceField.fan_directions(6):
		open.append(NavSurfaceSample.missed(direction, 3.0))
		closed.append(NavSurfaceSample.make(direction, direction, -direction, 1.0))
	assert_eq(NavSurfaceField.enclosure_of(open, 3.0), 0.0)
	assert_eq(NavSurfaceField.enclosure_of(closed, 3.0), 1.0)


func test_a_surface_beyond_reach_does_not_enclose() -> void:
	var samples: Array[NavSurfaceSample] = _fan_of(
		[NavSurfaceSample.make(Vector3.UP, Vector3.UP * 9.0, Vector3.DOWN, 9.0)]
	)
	assert_eq(
		NavSurfaceField.enclosure_of(samples, 3.0),
		0.0,
		"a ceiling nine metres up is not a tunnel wall"
	)


func test_the_medial_direction_points_away_from_the_nearer_wall() -> void:
	var samples: Array[NavSurfaceSample] = _fan_of(
		[
			NavSurfaceSample.make(Vector3.LEFT, Vector3.LEFT, Vector3.RIGHT, 1.0),
			NavSurfaceSample.make(Vector3.RIGHT, Vector3.RIGHT * 3.0, Vector3.LEFT, 3.0),
		]
	)
	assert_gt(
		NavSurfaceField.medial_of(samples, 4.0).x,
		0.5,
		"a wall 1 m to the left outweighs one 3 m to the right"
	)


func test_opposing_walls_at_equal_distance_cancel() -> void:
	var samples: Array[NavSurfaceSample] = _fan_of(
		[
			NavSurfaceSample.make(Vector3.LEFT, Vector3.LEFT * 2.0, Vector3.RIGHT, 2.0),
			NavSurfaceSample.make(Vector3.RIGHT, Vector3.RIGHT * 2.0, Vector3.LEFT, 2.0),
		]
	)
	assert_true(
		NavSurfaceField.medial_of(samples, 4.0).is_zero_approx(),
		"already centred means no push, which is what makes this a medial axis"
	)


func test_nothing_within_reach_produces_no_medial_push() -> void:
	var samples: Array[NavSurfaceSample] = _fan_of([NavSurfaceSample.missed(Vector3.UP, 3.0)])
	assert_true(NavSurfaceField.medial_of(samples, 3.0).is_zero_approx())


func test_a_reading_taken_in_a_corridor_reports_the_nearer_wall() -> void:
	# A 4 m corridor along x: walls 2 m away in z, floor and ceiling 2 m away in y.
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		Vector3.ZERO, _probe, _config.locomotion_profile, _config.world_mask
	)
	assert_true(reading.has_surface())
	assert_lt(reading.nearest_distance(), 2.5, "the walls of a 4 m corridor are 2 m off")
	assert_gt(
		reading.enclosure,
		_config.locomotion_profile.tunnel_enter_enclosure,
		"a 4 m corridor is section 9.3's confined space, decided from geometry alone"
	)


func test_a_reading_taken_in_the_open_encloses_nothing() -> void:
	_flat_floor()
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		Vector3(0.0, FLOOR_STANDOFF, 0.0), _probe, _config.locomotion_profile, _config.world_mask
	)
	assert_true(reading.has_surface(), "the floor is right there")
	assert_lt(
		reading.enclosure,
		_config.locomotion_profile.tunnel_exit_enclosure,
		"one floor is not a tunnel, however close it is"
	)
