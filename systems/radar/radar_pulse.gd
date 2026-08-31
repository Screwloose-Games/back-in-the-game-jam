class_name RadarPulse
extends RefCounted

## The geometry of a radar sweep, in one place. Pure static helpers so the detector
## growing the sphere and the HUD drawing the rings agree on how long a pulse takes
## and where a contact sits relative to the suit.


## A world-space contact in the body's own frame -- the FULL basis, not just a
## translation, so something ahead of you reads as ahead whichever way the suit
## happens to be pointed.
static func local_offset(body_transform: Transform3D, world_point: Vector3) -> Vector3:
	return body_transform.affine_inverse() * world_point


## How long a pulse takes to grow from the suit to full reach, in seconds.
static func sweep_seconds(range_m: float, pulse_speed: float) -> float:
	if pulse_speed <= 0.0:
		return 0.0
	return range_m / pulse_speed
