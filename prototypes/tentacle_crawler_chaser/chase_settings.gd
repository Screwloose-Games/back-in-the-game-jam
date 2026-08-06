class_name ChaseSettings
extends PrototypeSettings

## The chase prototype's live-tunable creature and pursuit, saved between runs.
##
## Defaults and slider bounds both come from chase_knobs.gd, so this file adds no
## numbers of its own - see PrototypeSettings for why that matters.
##
## These are the numbers that decide whether the chase reads as frightening or as
## an animal stuck in a corridor, and both failures look the same from a distance,
## so they are worth arguing about while the creature is actually chasing you.

const SAVE_PATH := "res://prototypes/tentacle_crawler_chaser/chase_settings.tres"

## Metres per second the follower travels at. The ceiling on how fast the creature
## can be dragged, and the first number to reach for when the chase feels wrong in
## either direction.
@export_range(1.0, 20.0, 0.5, "suffix:m/s") var follower_speed: float = ChaseKnobs.FOLLOWER_SPEED

## The creature's own top speed.
@export_range(1.0, 30.0, 0.5, "suffix:m/s")
var creature_max_speed: float = ChaseKnobs.CREATURE_MAX_SPEED

## Metres the creature may fall behind the marker before the leash pulls.
##
## The number that decides whether it can ever actually reach you: the standoffs
## add up, and at too much slack it arrives, settles a few metres off, and hovers
## there forever.
@export_range(0.0, 8.0, 0.1, "suffix:m")
var creature_leash_slack: float = ChaseKnobs.CREATURE_LEASH_SLACK

## How far off the nearest surface the creature holds itself.
##
## THE MAXIMUM HERE IS NOT ARBITRARY. The creature needs twice this to fit down a
## passage and CORRIDOR_WIDTH is 10 m, so anything above 5.0 makes every corridor
## impassable - which is exactly the 5 m hatch that cost an afternoon before
## anyone worked out it was a corridor narrower than the thing walking down it.
@export_range(1.0, 5.0, 0.1, "suffix:m")
var creature_probe_comfort: float = ChaseKnobs.CREATURE_PROBE_COMFORT

## Radius of the sphere that counts as caught. The creature's REACH, not its
## waist - the torso is 2.15 m across and the tentacles throw several metres past
## it. Applied to the live shape, so it can be argued about mid-chase.
@export_range(1.0, 15.0, 0.5, "suffix:m") var catch_radius: float = ChaseKnobs.CATCH_RADIUS

## The creature's own light. Set it to zero for the real test - unlit, it is
## invisible until about ten metres away, which is a fine horror game and a
## hopeless tuning environment.
@export_range(0.0, 4.0, 0.05) var creature_light_energy: float = ChaseKnobs.CREATURE_LIGHT_ENERGY


func settings_path() -> String:
	return SAVE_PATH


## The two cross-knob rules that used to be startup warnings, checked here so
## they run against the SAVED values rather than only against the consts.
func invariant_failures() -> PackedStringArray:
	var failures := super.invariant_failures()
	if 2.0 * creature_probe_comfort > ChaseKnobs.CORRIDOR_WIDTH:
		failures.append(
			(
				"creature_probe_comfort %.1f needs %.1f m of passage but corridors are %.1f m"
				% [creature_probe_comfort, 2.0 * creature_probe_comfort, ChaseKnobs.CORRIDOR_WIDTH]
			)
		)
	if catch_radius <= creature_leash_slack:
		failures.append(
			(
				"catch_radius %.1f is inside leash slack %.1f; the catch can never fire"
				% [catch_radius, creature_leash_slack]
			)
		)
	return failures
