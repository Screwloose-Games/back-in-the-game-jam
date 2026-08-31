class_name InteractionHold
extends RefCounted

## The arithmetic of a hold gesture, in one place. A press becomes a hold once it
## outlives the threshold; the bar then fills over the target's duration. Pure
## static helpers so the interactor, the settings default, and any HUD all agree
## on where a tap ends and a hold begins.

## How long the key is held before the press stops being a tap, in seconds.
const DEFAULT_THRESHOLD := 0.25


## Whether the press has outlived the tap window and become a hold.
static func is_hold(held_seconds: float, threshold: float) -> bool:
	return held_seconds >= threshold


## How full the bar is, 0.0 to 1.0. The clock starts at the threshold, not at the
## press -- the disambiguation delay is not progress toward the verb.
static func progress(held_seconds: float, threshold: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf((held_seconds - threshold) / duration, 0.0, 1.0)


## Whether the bar has filled.
static func is_complete(held_seconds: float, threshold: float, duration: float) -> bool:
	return held_seconds >= threshold + duration
