extends "res://gameplay/creature/navigation/tests/navigation_test_case.gd"

## Phase 4: confinement detection and medial centering (navigation.md section 9).
##
## The claim worth protecting here is section 9.3's: confinement is decided by LOCAL
## GEOMETRY, never by an authored flag. Nothing below tells the controller it is in a
## tunnel -- the tests build one and let the fan find out, which is the only way the same
## code can work on a passage the player mined a moment ago.


func _profile() -> LocomotionProfile:
	return _config.locomotion_profile


## A reading with a given enclosure and nothing else, for the threshold tests. Building
## real geometry to hit an exact fraction would make those tests about the geometry.
func _reading_with(enclosure: float) -> NavSurfaceReading:
	var reading := NavSurfaceReading.new()
	reading.enclosure = enclosure
	return reading


# ----- section 9.3, and the hysteresis -----


func test_an_open_room_is_not_a_tunnel() -> void:
	assert_eq(
		TunnelSwimController.mode_for(
			_reading_with(0.1), NavLocomotion.Mode.SURFACE_CRAWL, _profile()
		),
		NavLocomotion.Mode.SURFACE_CRAWL
	)


func test_enough_enclosure_starts_a_swim() -> void:
	assert_eq(
		TunnelSwimController.mode_for(
			_reading_with(_profile().tunnel_enter_enclosure),
			NavLocomotion.Mode.SURFACE_CRAWL,
			_profile()
		),
		NavLocomotion.Mode.TUNNEL_SWIM
	)


## The hysteresis, stated where it bites: a reading between the two thresholds keeps
## whichever mode is already held. One threshold would flip on both of these.
func test_a_reading_between_the_thresholds_changes_nothing() -> void:
	var between: float = (
		0.5 * (_profile().tunnel_enter_enclosure + _profile().tunnel_exit_enclosure)
	)
	assert_eq(
		TunnelSwimController.mode_for(
			_reading_with(between), NavLocomotion.Mode.SURFACE_CRAWL, _profile()
		),
		NavLocomotion.Mode.SURFACE_CRAWL,
		"not enclosed enough to start swimming"
	)
	assert_eq(
		TunnelSwimController.mode_for(
			_reading_with(between), NavLocomotion.Mode.TUNNEL_SWIM, _profile()
		),
		NavLocomotion.Mode.TUNNEL_SWIM,
		"and not open enough to stop, which is the same reading twice"
	)


func test_leaving_the_tunnel_ends_the_swim() -> void:
	assert_eq(
		TunnelSwimController.mode_for(
			_reading_with(_profile().tunnel_exit_enclosure),
			NavLocomotion.Mode.TUNNEL_SWIM,
			_profile()
		),
		NavLocomotion.Mode.SURFACE_CRAWL
	)


# ----- section 9.2, the blended heading -----


func test_the_heading_still_makes_progress_when_perfectly_centred() -> void:
	var reading := NavSurfaceReading.new()
	reading.medial = Vector3.ZERO
	var direction: Vector3 = TunnelSwimController.desired_direction(
		Vector3(10.0, 0.0, 0.0), reading, _profile()
	)
	assert_almost_eq(direction.x, 1.0, 0.001, "nothing to correct, so head straight for the goal")


func test_a_near_wall_bends_the_heading_away_from_it() -> void:
	var reading := NavSurfaceReading.new()
	reading.medial = Vector3.UP
	var direction: Vector3 = TunnelSwimController.desired_direction(
		Vector3(10.0, 0.0, 0.0), reading, _profile()
	)
	assert_gt(direction.y, 0.1, "the medial push has to show up in the heading")
	assert_gt(direction.x, 0.5, "but not so much that the alien stops travelling")


## Section 9.2 gives neither term the last word, so this is the case where they disagree
## completely: pushed exactly backwards, progress still wins.
func test_a_medial_push_directly_opposing_progress_does_not_stall_the_body() -> void:
	var reading := NavSurfaceReading.new()
	reading.medial = Vector3.LEFT
	_config.locomotion_profile.tunnel_centering_weight = 1.0
	var direction: Vector3 = TunnelSwimController.desired_direction(
		Vector3.RIGHT, reading, _profile()
	)
	assert_false(direction.is_zero_approx(), "an alien that cancels itself out never arrives")
	assert_almost_eq(direction.x, 1.0, 0.001)


# ----- steering, against real corridor geometry -----


func test_a_corridor_reads_as_confined_and_produces_a_swim() -> void:
	# 4 m square bore along x. Walls 2 m from the axis in y and z.
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		Vector3.ZERO, _probe, _profile(), _config.world_mask
	)
	assert_gte(
		reading.enclosure,
		_profile().tunnel_enter_enclosure,
		"a 4 m bore is section 9.3's confined space; nothing said so but the geometry"
	)

	var body: NavBodyState = _body_state(Vector3.ZERO, Vector3.RIGHT)
	var command: NavMotionCommand = TunnelSwimController.new().steer(
		body, Vector3(10.0, 0.0, 0.0), reading, 1.0 / 60.0, _probe, _config
	)
	assert_not_null(command, "the bore is clear ahead")
	assert_eq(command.mode, NavLocomotion.Mode.TUNNEL_SWIM)
	assert_gt(command.desired_direction.x, 0.8, "travel is along the bore")


func test_an_off_axis_body_is_pushed_back_toward_the_middle() -> void:
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	# Held near the floor of the bore rather than on its axis.
	var off_axis := Vector3(0.0, -0.6, 0.0)
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		off_axis, _probe, _profile(), _config.world_mask
	)
	var command: NavMotionCommand = TunnelSwimController.new().steer(
		_body_state(off_axis, Vector3.RIGHT),
		Vector3(10.0, -0.6, 0.0),
		reading,
		1.0 / 60.0,
		_probe,
		_config
	)
	assert_not_null(command)
	assert_gt(
		command.desired_direction.y,
		0.0,
		"section 9.1: the body tends toward the medial axis rather than the nearest wall"
	)


func test_swimming_refuses_rather_than_steering_into_a_blocked_bore() -> void:
	_probe.add_room(AABB(Vector3(-20.0, -2.0, -2.0), Vector3(40.0, 4.0, 4.0)))
	# A plug across the bore, one step ahead.
	_probe.add_solid(AABB(Vector3(1.0, -2.0, -2.0), Vector3(2.0, 4.0, 4.0)))
	var reading: NavSurfaceReading = NavSurfaceField.new().sample(
		Vector3.ZERO, _probe, _profile(), _config.world_mask
	)
	assert_null(
		TunnelSwimController.new().steer(
			_body_state(Vector3.ZERO, Vector3.RIGHT),
			Vector3(10.0, 0.0, 0.0),
			reading,
			1.0 / 60.0,
			_probe,
			_config
		),
		"a swimmer has no alternatives to score, so it hands the decision back"
	)
