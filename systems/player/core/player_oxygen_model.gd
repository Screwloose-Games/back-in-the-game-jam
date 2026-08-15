class_name PlayerOxygenModel
extends RefCounted

## Pure oxygen arithmetic. Power converts to oxygen while the tether is live;
## with no power the personal supply drains, and thrusting untethered spends it
## directly — the design's "move or breathe, pick one".


## Oxygen gained or lost this second, in capacity units. Positive regenerates.
static func rate_per_second(
	tethered: bool,
	has_power: bool,
	thrust_fraction: float,
	regen_per_second: float,
	idle_drain_per_second: float,
	thrust_cost_per_second: float
) -> float:
	if tethered and has_power:
		return regen_per_second
	var rate := -idle_drain_per_second
	# Thrust costs air only once the shared box is no longer paying for it.
	if not tethered:
		rate -= thrust_cost_per_second * clampf(thrust_fraction, 0.0, 1.0)
	return rate


## The oxygen level after one step, clamped to the tank.
static func step(oxygen: float, capacity: float, rate_per_sec: float, delta: float) -> float:
	return clampf(oxygen + rate_per_sec * delta, 0.0, maxf(capacity, 0.0))


## How full the tank is, 0 to 1.
static func fraction(oxygen: float, capacity: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(oxygen / capacity, 0.0, 1.0)


## Seconds of air left at the current rate, or INF while it is not draining.
static func seconds_remaining(oxygen: float, rate_per_sec: float) -> float:
	if rate_per_sec >= 0.0:
		return INF
	return maxf(oxygen, 0.0) / absf(rate_per_sec)
