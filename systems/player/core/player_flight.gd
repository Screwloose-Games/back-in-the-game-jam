class_name PlayerFlight
extends RefCounted

## Pure 6-DOF flight arithmetic: thrust, tumble, stabilisers and speed caps.
## Static functions over plain data, so the whole flight model is testable
## without a body, a viewport or a clock.

enum RotationMode {
	## Look input maps straight onto this frame's rotation; nothing accumulates.
	DIRECT,
	## Look input accelerates a spin that persists between frames.
	INERTIAL,
}


## Clamps the three thrust axes to a unit sphere so diagonals are not faster.
static func thrust_from_axes(right: float, up: float, back: float) -> Vector3:
	return Vector3(right, up, back).limit_length(1.0)


## The velocity a burst of thrust adds, in world space.
static func thrust_velocity_change(
	body_basis: Basis, thrust_input: Vector3, acceleration: float, delta: float
) -> Vector3:
	return body_basis * thrust_input * acceleration * delta


## The velocity the stabilisers shed this frame, as a negative change.
static func stabilizer_velocity_change(velocity: Vector3, rate: float, delta: float) -> Vector3:
	return -velocity * minf(rate * delta, 1.0)


## Folds look and roll input into a persistent tumble, capped at max_speed.
static func accumulate_spin(
	angular_velocity: Vector3,
	look: Vector2,
	roll: float,
	aim_gain: float,
	roll_rate: float,
	max_speed: float,
	delta: float
) -> Vector3:
	var spun := angular_velocity
	spun.x += -look.y * aim_gain
	spun.y += -look.x * aim_gain
	spun.z += -roll * roll_rate * delta
	return spun.limit_length(max_speed)


## Sheds a fraction of the tumble, which is what stops a flick spinning forever.
static func damp_spin(angular_velocity: Vector3, rate: float, delta: float) -> Vector3:
	if angular_velocity.is_zero_approx():
		return angular_velocity
	return angular_velocity.lerp(Vector3.ZERO, minf(rate * delta, 1.0))


## Rotates about the body's own axes in turn, so no world reference is involved.
static func rotate_about_own_axes(
	body_basis: Basis, pitch: float, yaw: float, roll: float
) -> Basis:
	var rotated := body_basis
	rotated = rotated.rotated(rotated.y, yaw)
	rotated = rotated.rotated(rotated.x, pitch)
	rotated = rotated.rotated(rotated.z, roll)
	# Repeated incremental rotations accumulate skew without this.
	return rotated.orthonormalized()


## The share of a manoeuvre handed straight to a held object so both bodies
## accelerate together instead of the load arriving through the hands.
static func braced_object_share(bracing: float, player_mass: float, object_mass: float) -> float:
	var total_mass := player_mass + object_mass
	if total_mass <= 0.0:
		return 0.0
	return bracing * object_mass / total_mass


## Converts a body-local tumble into world space.
static func world_spin(body_basis: Basis, angular_velocity: Vector3) -> Vector3:
	return body_basis * angular_velocity


## The sprint-scaled speed cap, easing back toward the base cap as sprint drops.
static func speed_cap(base_cap: float, sprint_multiplier: float, sprint_engaged: bool) -> float:
	return base_cap * sprint_multiplier if sprint_engaged else base_cap
