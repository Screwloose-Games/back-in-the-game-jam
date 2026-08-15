class_name PlayerNoise
extends RefCounted

## Pure noise arithmetic. Everything the player does that the creature can hear
## resolves to one strength here, so the perception layer has a single number to
## reason about rather than a list of sources.

## Sources the player can make noise from, in the order they override each other.
enum Source {
	THRUST,
	MINING,
	IMPACT,
}


## Thrust noise scales with how hard the thrusters are firing, and there is no
## silent setting above zero — the design has no quiet way to travel.
static func thrust_strength(thrust_fraction: float, full_strength: float) -> float:
	return clampf(thrust_fraction, 0.0, 1.0) * full_strength


## Impact noise scales with how hard the hit was, up to the full strength.
static func impact_strength(
	closing_speed: float, reference_speed: float, full_strength: float
) -> float:
	if reference_speed <= 0.0:
		return 0.0
	return clampf(absf(closing_speed) / reference_speed, 0.0, 1.0) * full_strength


## The loudest of several concurrent sources. Noise does not sum here because
## the creature is steered by the strongest thing it can hear, not by a total.
static func loudest(strengths: PackedFloat32Array) -> float:
	var highest := 0.0
	for strength: float in strengths:
		highest = maxf(highest, strength)
	return highest


## How far a noise of this strength carries, in metres.
static func audible_radius(strength: float, metres_per_unit: float) -> float:
	return maxf(strength, 0.0) * maxf(metres_per_unit, 0.0)
