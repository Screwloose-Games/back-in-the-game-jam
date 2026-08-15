class_name PlayerSpring
extends RefCounted

## Two-body spring arithmetic for the grip and the tether. Springs are specified
## as a frequency and a damping ratio and the stiffness is derived per link from
## the masses, so the numbers stay meaningful when either mass changes.


## The effective mass of a two-body pair.
static func reduced_mass(mass_a: float, mass_b: float) -> float:
	if mass_a <= 0.0 or mass_b <= 0.0:
		return 0.0
	return 1.0 / (1.0 / mass_a + 1.0 / mass_b)


## Spring stiffness in newtons per metre for a given frequency in hertz.
static func stiffness(mass: float, frequency_hz: float) -> float:
	var angular_frequency := TAU * frequency_hz
	return mass * angular_frequency * angular_frequency


## Damping coefficient for a damping ratio, where 1.0 is critical.
static func damping(mass: float, frequency_hz: float, ratio: float) -> float:
	return 2.0 * ratio * TAU * frequency_hz * mass


## One frame of spring force, clamped so a bad frame cannot launch either body.
static func force(
	offset: Vector3,
	relative_velocity: Vector3,
	spring_stiffness: float,
	spring_damping: float,
	ceiling: float
) -> Vector3:
	return (offset * spring_stiffness - relative_velocity * spring_damping).limit_length(ceiling)


## Rope tension: pulls only, never pushes, and never past the ceiling.
static func rope_tension(
	stretch: float,
	stretch_rate: float,
	spring_stiffness: float,
	spring_damping: float,
	ceiling: float
) -> float:
	return minf(maxf(stretch * spring_stiffness + stretch_rate * spring_damping, 0.0), ceiling)


## The velocity of a point on a spinning body.
static func point_velocity(
	linear_velocity: Vector3, angular_velocity: Vector3, lever_arm: Vector3
) -> Vector3:
	return linear_velocity + angular_velocity.cross(lever_arm)


## A rotation as the axis it turns about scaled by the radians it turns, which
## is what makes an orientation error something a spring can work on.
static func measure_rotation(rotation_basis: Basis) -> Vector3:
	var rotation := Quaternion(rotation_basis.orthonormalized())
	# Negating picks the short way round rather than the long one.
	if rotation.w < 0.0:
		rotation = -rotation
	var angle := rotation.get_angle()
	if is_zero_approx(angle):
		return Vector3.ZERO
	return rotation.get_axis() * angle


## The axis-aligned orientation nearest the one given, so squaring a roughly
## cubic object up never rotates it most of a turn to reach an identical face.
static func snap_basis_to_axes(source: Basis) -> Basis:
	var snapped_z := nearest_cardinal(source.z, Vector3.ZERO)
	var snapped_y := nearest_cardinal(source.y, snapped_z)
	return Basis(snapped_y.cross(snapped_z), snapped_y, snapped_z)


## The signed cardinal a direction points most nearly along, skipping the line
## already spoken for so the result can be part of a valid basis.
static func nearest_cardinal(direction: Vector3, claimed_axis: Vector3) -> Vector3:
	var cardinals := [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	var nearest := Vector3.RIGHT
	var best_alignment := -INF
	for candidate: Vector3 in cardinals:
		if not is_zero_approx(candidate.dot(claimed_axis)):
			continue
		var alignment := candidate.dot(direction)
		if alignment > best_alignment:
			best_alignment = alignment
			nearest = candidate
	return nearest
