class_name PlayerHealthModel
extends RefCounted

## Pure damage and recovery arithmetic. An impact is priced against the same
## reference speed the noise is, and recovery starts only once nothing has hit you
## for a while -- attrition you cannot outheal is what makes depth cost something.


## Damage one impact costs: nothing under the deadband, linear above it, capped at
## `hardness_cap` multiples of the reference figure.
static func impact_damage(
	closing_speed: float,
	min_speed: float,
	reference_speed: float,
	damage_at_reference: float,
	hardness_cap: float
) -> float:
	# The signal fires only when the suit is moving INTO a surface, so the speed
	# arrives negative. A reference speed at or under the deadband would divide by
	# zero or by a negative, and no impact could ever reach full strength anyway.
	var speed := absf(closing_speed)
	if speed <= min_speed or reference_speed <= min_speed:
		return 0.0
	var hardness := (speed - min_speed) / (reference_speed - min_speed)
	return minf(hardness, maxf(hardness_cap, 0.0)) * maxf(damage_at_reference, 0.0)


## Health recovered per second, which is nothing until the suit has been unhurt for
## `delay` seconds.
static func regen_rate(seconds_since_damage: float, delay: float, per_second: float) -> float:
	if seconds_since_damage < delay:
		return 0.0
	return maxf(per_second, 0.0)


## The health level after one change, clamped to the pool.
static func step(health: float, max_health: float, delta_health: float) -> float:
	return clampf(health + delta_health, 0.0, maxf(max_health, 0.0))


## How intact the suit is, 0 to 1.
static func fraction(health: float, max_health: float) -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)
