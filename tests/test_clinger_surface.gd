extends McpTestSuite

## ClingerSurface: the tangent-plane maths a body crawling on walls runs on.
##
## THE HANDEDNESS CASE IS THE ONE THAT MATTERS. Forward and up can both be correct in a
## basis whose determinant is -1, and the only symptom is a single-sided mesh rendering
## its own interior -- which reads as an art bug, in a file nobody would open looking for
## one. The rest of the suite pins the degenerate inputs that return NaN instead of a
## direction, because a NaN in an orientation never recovers: it poisons every frame after
## it and the creature simply disappears.

const EPSILON := 0.0001


func suite_name() -> String:
	return "clinger_surface"


func test_a_basis_faces_forward_with_the_normal_as_up() -> void:
	var basis := ClingerSurface.basis_from(Vector3.FORWARD, Vector3.UP)
	assert_true((-basis.z).is_equal_approx(Vector3.FORWARD), "-Z is not the heading")
	assert_true(basis.y.is_equal_approx(Vector3.UP), "+Y is not the surface normal")


func test_every_basis_is_right_handed() -> void:
	# A mirrored basis flips the winding, and the palette material is single-sided.
	for normal: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3.BACK, Vector3(-4, 1, 0)]:
		var basis := ClingerSurface.basis_from(Vector3(1, 2, 3), normal)
		assert_true(
			basis.determinant() > 0.0, "det <= 0 on normal %v; the shell is inside out" % normal
		)


func test_a_basis_is_orthonormal() -> void:
	var basis := ClingerSurface.basis_from(Vector3(1, 2, 3), Vector3(-4, 1, 0))
	assert_true(basis.is_equal_approx(basis.orthonormalized()), "the basis is skewed")


func test_a_heading_parallel_to_the_normal_returns_identity_not_nan() -> void:
	var basis := ClingerSurface.basis_from(Vector3.UP, Vector3.UP)
	assert_true(basis.is_equal_approx(Basis.IDENTITY), "a degenerate pair produced a live basis")
	assert_false(is_nan(basis.x.x), "a degenerate pair produced NaN")


func test_projection_leaves_nothing_pointing_into_the_surface() -> void:
	var normal := Vector3(0.3, 0.9, -0.2).normalized()
	var flat := ClingerSurface.project(Vector3(1, 2, 3), normal)
	assert_true(absf(flat.dot(normal)) < EPSILON, "the heading still aims into the rock")


func test_a_turn_is_limited_and_a_short_one_arrives() -> void:
	var turned := ClingerSurface.turn_limited(Vector3.FORWARD, Vector3.RIGHT, deg_to_rad(10.0))
	assert_true(absf(Vector3.FORWARD.angle_to(turned) - deg_to_rad(10.0)) < EPSILON, "overshot")
	var arrived := ClingerSurface.turn_limited(Vector3.FORWARD, Vector3.RIGHT, PI)
	assert_true(arrived.is_equal_approx(Vector3.RIGHT), "a reachable goal was not reached")


## Exactly opposed vectors have no unique rotation axis, and normalising that zero returns
## NaN -- which then travels into the orientation and stays there.
func test_turning_through_an_exact_reversal_stays_finite() -> void:
	var turned := ClingerSurface.turn_limited(Vector3.FORWARD, Vector3.BACK, deg_to_rad(30.0))
	assert_false(is_nan(turned.x) or is_nan(turned.y) or is_nan(turned.z), "reversal produced NaN")
	assert_true(absf(turned.length() - 1.0) < EPSILON, "reversal produced a non-unit heading")


## Two independently turned vectors do not stay perpendicular. Two hundred slews is a few
## seconds of crawling, and shear compounds every one of them.
func test_slewing_stays_orthonormal_and_right_handed() -> void:
	var forward := Vector3.FORWARD
	var up := Vector3.UP
	var target := ClingerSurface.basis_from(Vector3(1, 0, -1), Vector3(0.2, 0.9, 0.1))
	for _step: int in 200:
		var basis := ClingerSurface.slew(forward, up, target, deg_to_rad(3.0))
		forward = -basis.z
		up = basis.y
		assert_true(basis.determinant() > 0.0, "a slew mirrored the body")
	var final_basis := ClingerSurface.basis_from(forward, up)
	assert_true(final_basis.is_equal_approx(final_basis.orthonormalized()), "the pose sheared")


func test_an_orbit_point_sits_on_the_circle_and_on_the_surface() -> void:
	var player := Vector3(2, 0, 0)
	var normal := Vector3.UP
	var at := ClingerSurface.orbit_target(player, Vector3(5, 0, 0), normal, 4.0, 0.7)
	assert_true(absf(player.distance_to(at) - 4.0) < EPSILON, "off the circle")
	assert_true(absf((at - player).dot(normal)) < EPSILON, "off the surface plane")


## A clinger standing exactly where the player is has no outward direction to rotate, and
## the fallback is what stops it returning NaN for the rest of the run.
func test_an_orbit_from_the_player_position_still_lands_on_the_circle() -> void:
	var player := Vector3(2, 0, 0)
	var at := ClingerSurface.orbit_target(player, player, Vector3.UP, 4.0, 0.0)
	assert_true(absf(player.distance_to(at) - 4.0) < EPSILON, "the degenerate case drifted")


func test_smoothing_is_bounded_and_zero_on_a_zero_step() -> void:
	assert_true(absf(ClingerSurface.smoothing(12.0, 0.0)) < EPSILON, "a zero step moved something")
	var weight := ClingerSurface.smoothing(12.0, 1.0)
	assert_true(weight > 0.0 and weight < 1.0, "the weight left 0..1")


func test_parallel_detection_catches_the_case_that_spins_the_body() -> void:
	assert_true(ClingerSurface.too_parallel(Vector3.UP, Vector3.UP), "identical vectors passed")
	assert_true(ClingerSurface.too_parallel(Vector3.UP, Vector3.DOWN), "opposed vectors passed")
	assert_false(ClingerSurface.too_parallel(Vector3.UP, Vector3.RIGHT), "a right angle failed")
	assert_true(ClingerSurface.too_parallel(Vector3.ZERO, Vector3.UP), "a zero vector passed")


## LOOPED OVER FIVE UP VECTORS ON PURPOSE. A fan that only worked on a floor would search
## walls and ceilings badly and silently, and the clinger spends most of its life on both.
func test_the_leap_fan_never_aims_into_the_rock_it_stands_on() -> void:
	for up: Vector3 in [
		Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3(1, 2, -3).normalized()
	]:
		for direction: Vector3 in ClingerSurface.leap_fan(up, 18):
			assert_true(absf(direction.length() - 1.0) < EPSILON, "a fan ray was not unit length")
			assert_true(
				direction.dot(up) >= ClingerSurface.LEAP_FAN_FLOOR - EPSILON,
				"a ray off %s aimed into the surface" % up
			)


func test_the_leap_fan_returns_the_count_it_was_asked_for() -> void:
	assert_eq(ClingerSurface.leap_fan(Vector3.UP, 18).size(), 18, "the fan lost rays")


func test_a_degenerate_leap_fan_returns_nothing_rather_than_nan() -> void:
	assert_true(ClingerSurface.leap_fan(Vector3.ZERO, 18).is_empty(), "a zero up produced a fan")
	assert_true(ClingerSurface.leap_fan(Vector3.UP, 0).is_empty(), "a zero count produced a fan")


func test_disc_offsets_ring_the_patch_in_its_own_plane() -> void:
	var normal := Vector3(1, 2, -3).normalized()
	var offsets := ClingerSurface.disc_offsets(normal, 1.2, 8)
	assert_eq(offsets.size(), 8, "the ring lost probes")
	for offset: Vector3 in offsets:
		assert_true(absf(offset.dot(normal)) < EPSILON, "an offset left the tangent plane")
		assert_true(absf(offset.length() - 1.2) < EPSILON, "an offset was the wrong radius")


func test_a_degenerate_disc_returns_nothing_rather_than_nan() -> void:
	assert_true(ClingerSurface.disc_offsets(Vector3.ZERO, 1.2, 8).is_empty(), "a zero normal rang")
	assert_true(ClingerSurface.disc_offsets(Vector3.UP, 0.0, 8).is_empty(), "a zero radius rang")
	assert_true(ClingerSurface.disc_offsets(Vector3.UP, 1.2, 0).is_empty(), "a zero count rang")
