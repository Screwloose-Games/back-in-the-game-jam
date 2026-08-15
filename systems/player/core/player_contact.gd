class_name PlayerContact
extends RefCounted

## Pure collision-response arithmetic: restitution, friction, scrape and the
## torque a glancing hit puts on the body. Split from PlayerFlight because
## contact resolution is the half that needs a contact normal and a lever arm.


## The velocity left after a hull impact: the into-surface part thrown back out
## by restitution, the along-surface part scrubbed by friction.
static func hull_bounce(
	approach_velocity: Vector3, contact_normal: Vector3, restitution: float, friction: float
) -> Vector3:
	var closing_speed := approach_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		return approach_velocity
	var into_surface := contact_normal * closing_speed
	var along_surface := approach_velocity - into_surface
	return along_surface * (1.0 - friction) - into_surface * restitution


## The velocity left after a frame of scraping along a surface already touched.
static func scrape(velocity: Vector3, friction: float, delta: float) -> Vector3:
	return velocity.lerp(Vector3.ZERO, minf(friction * delta, 1.0))


## The along-surface component of an approach, which is what friction acts on.
static func along_surface(approach_velocity: Vector3, contact_normal: Vector3) -> Vector3:
	return approach_velocity - contact_normal * approach_velocity.dot(contact_normal)


## The effective mass of a two-body pair.
static func reduced_mass(mass_a: float, mass_b: float) -> float:
	if mass_a <= 0.0 or mass_b <= 0.0:
		return 0.0
	return 1.0 / (1.0 / mass_a + 1.0 / mass_b)


## The impulse magnitude of a two-body collision along the contact normal.
static func impulse_magnitude(
	closing_speed: float, restitution: float, pair_reduced_mass: float
) -> float:
	return -(1.0 + restitution) * closing_speed * pair_reduced_mass


## The body-local spin a velocity change applied off the centre of mass adds.
## The transfer factor stands in for a moment of inertia the suit does not model.
static func spin_from_impulse(
	body_basis: Basis, velocity_change: Vector3, lever_arm: Vector3, mass: float, transfer: float
) -> Vector3:
	if is_zero_approx(transfer) or mass <= 0.0:
		return Vector3.ZERO
	var world_angular_impulse := lever_arm.cross(velocity_change * mass)
	return body_basis.inverse() * world_angular_impulse * transfer / mass


## The body-local spin a world-space angular impulse adds.
static func spin_from_angular_impulse(
	body_basis: Basis, world_angular_impulse: Vector3, transfer: float, mass: float
) -> Vector3:
	if is_zero_approx(transfer) or mass <= 0.0:
		return Vector3.ZERO
	return body_basis.inverse() * world_angular_impulse * transfer / mass
