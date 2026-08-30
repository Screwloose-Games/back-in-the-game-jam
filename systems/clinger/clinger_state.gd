class_name ClingerState
extends RefCounted

## The clinger's phases and the arithmetic behind the transitions between them, with no
## node, no tree and no physics -- so the whole table can be driven by a test that never
## builds a scene. `Clinger` holds the state; this decides what it should be.

## Dormant on a wall until something wakes it; crawling toward whatever it heard; in
## flight; riding a visor; circling a player it has been shed by; dead and counting
## down to a despawn; or crossing the room to get off a surface it cannot navigate.
## ALERTED is not here on purpose -- it has one guard and one exit, so it is a timer inside
## DORMANT rather than a row in the table.
##
## SURFACE_LEAPING IS APPENDED AND NOT FILED NEXT TO LEAPING. phase_name() is
## `Phase.keys()[phase]` and `state_changed` carries the raw int, so inserting a value
## renumbers every phase after it and silently relabels anything already connected.
enum Phase { DORMANT, CRAWLING, LEAPING, ATTACHED, ORBITING, DEAD, SURFACE_LEAPING }


static func phase_name(phase: Phase) -> String:
	return Phase.keys()[phase] as String


## Whether a noise of `strength` made at `at` reaches a listener standing at `listener`.
## Both halves matter: quiet noises never wake one however close, and loud ones stop at
## the creature's own hearing range however loud.
static func hears(
	strength: float,
	at: Vector3,
	listener: Vector3,
	wake_strength: float,
	metres_per_unit: float,
	hearing_range: float
) -> bool:
	if strength < wake_strength or strength <= 0.0:
		return false
	var reach := minf(PlayerNoise.audible_radius(strength, metres_per_unit), hearing_range)
	return listener.distance_to(at) <= reach


## The cooldown is a floor on leaps STARTING, not on landings, which is what makes
## `clinger_attack_cooldown` read as "at most once every n seconds".
static func can_leap(cooldown_left: float, distance: float, jump_range: float) -> bool:
	return cooldown_left <= 0.0 and distance <= jump_range


## The escape leap's gate, and deliberately NOT can_leap's. That one asks whether a victim
## is in reach; this one asks whether the body has anywhere better to be.
##
## SEPARATE COOLDOWNS ON PURPOSE. An escape that spent `clinger_attack_cooldown` would have
## getting unstuck silently cost the creature its next attack, and a stuck clinger is one
## the player has already been ignoring.
##
## CRAWLING OR ORBITING. A clinger thrashing on a rock beside the player is the most visible
## way this fails, so the orbit is not exempt -- and at the shipped numbers an orbit cannot
## trip the detector anyway. The invariant in PlayerSettings keeps that true if the orbit is
## ever retuned.
static func can_surface_leap(cooldown_left: float, stuck: bool, phase: Phase) -> bool:
	if not stuck or cooldown_left > 0.0:
		return false
	return phase == Phase.CRAWLING or phase == Phase.ORBITING


## How far off the glass `presses` have taken it, 0 to 1. Mashing past the count does not
## overfill it; the shed has already happened.
static func peel_fraction(presses: int, needed: int) -> float:
	if needed <= 0:
		return 1.0
	return clampf(float(presses) / float(needed), 0.0, 1.0)


## What a per-second rate costs over `delta`. Never negative, so a hazard cannot heal.
static func bill(rate: float, delta: float) -> float:
	return maxf(rate, 0.0) * maxf(delta, 0.0)


## Radians around the player one tick of circling covers. Derived from the crawl speed, so
## the goal can never outrun the body chasing it.
static func orbit_step(crawl_speed: float, radius: float, delta: float) -> float:
	return maxf(crawl_speed, 0.0) / maxf(radius, 0.01) * maxf(delta, 0.0)
