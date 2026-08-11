class_name CoreLoopSettings
extends PrototypeSettings

## The core loop prototype's live-tunable numbers, saved between runs.
##
## Defaults and slider bounds both come from core_loop_knobs.gd, so this file
## adds no numbers of its own - see PrototypeSettings for why that matters.
##
## TWELVE, AND THE COUNT IS DELIBERATE. The panel has no scroll container and
## grows upward from the bottom left corner, so at about fourteen rows it runs off
## the top of a 720p window and the SAVE button goes with it. Everything else
## stays a const in the knobs file and is one @export_range away from being a
## slider, which is the trade the shared panel is built around.
##
## What earned a row is what this prototype does not yet know the answer to: the
## whole monster block, the drill's power draw, how far noise carries, and the
## speed ratio that decides whether you can outrun the thing at all.

const SAVE_PATH := "res://prototypes/core_loop/core_loop_settings.tres"

## Cruising speed cap. Half of the escape question - see creature_max_speed.
@export_range(CoreLoopKnobs.MAX_SPEED_MIN, CoreLoopKnobs.MAX_SPEED_MAX, 0.1, "suffix:m/s")
var max_speed: float = CoreLoopKnobs.MAX_SPEED

## How fast the creature moves. The other half: sprinting multiplies max_speed by
## SPRINT_SPEED_MULTIPLIER, and if the product does not beat this you cannot get
## away by flying, only by hiding. The invariant below says so out loud.
@export_range(
	CoreLoopKnobs.CREATURE_MAX_SPEED_MIN, CoreLoopKnobs.CREATURE_MAX_SPEED_MAX, 0.5, "suffix:m/s"
)
var creature_max_speed: float = CoreLoopKnobs.CREATURE_MAX_SPEED

## How fast the rock surface recedes at the centre of the bore. Inherited from the
## drill prototype and kept tunable here on purpose - see core_loop_knobs.gd.
@export_range(CoreLoopKnobs.CARVE_RATE_MIN, CoreLoopKnobs.CARVE_RATE_MAX, 0.05, "suffix:m/s")
var carve_rate: float = CoreLoopKnobs.CARVE_RATE

## How wide a hole the beam opens, as against how fast it deepens it. The half
## that decides whether one straight bore can ever free a crystal.
@export_range(CoreLoopKnobs.CARVE_RADIUS_MIN, CoreLoopKnobs.CARVE_RADIUS_MAX, 0.01, "suffix:m")
var carve_radius: float = CoreLoopKnobs.CARVE_RADIUS

## Charge per second the drill takes out of the suit while cutting. The number
## this whole prototype exists to find: it is what turns mining from something you
## do into something you spend.
@export_range(CoreLoopKnobs.DRILL_POWER_MIN, CoreLoopKnobs.DRILL_POWER_MAX, 0.5, "suffix:/s")
var drill_power_per_second: float = CoreLoopKnobs.DRILL_POWER_PER_SECOND

## How far drilling carries, in metres. Also the radius cranking uses. Loud enough
## and the creature is a tax on mining; quiet enough and it never arrives.
@export_range(CoreLoopKnobs.DRILL_NOISE_MIN, CoreLoopKnobs.DRILL_NOISE_MAX, 1.0, "suffix:m")
var drill_noise_radius: float = CoreLoopKnobs.DRILL_NOISE_RADIUS

## How far thrusters and stabilizers carry, in metres. This is what decides
## whether going quiet is a move you can actually play.
@export_range(CoreLoopKnobs.THRUST_NOISE_MIN, CoreLoopKnobs.THRUST_NOISE_MAX, 1.0, "suffix:m")
var thrust_noise_radius: float = CoreLoopKnobs.THRUST_NOISE_RADIUS

## Chance per second, while a loud noise is being made, that a dormant creature
## wakes up. The dial between "the tunnels are empty" and "you cannot work".
@export_range(CoreLoopKnobs.SPAWN_CHANCE_MIN, CoreLoopKnobs.SPAWN_CHANCE_MAX, 0.01, "suffix:/s")
var spawn_chance_per_second: float = CoreLoopKnobs.SPAWN_CHANCE_PER_SECOND

## How close the creature has to be for a noise to give you away completely.
@export_range(CoreLoopKnobs.CHASE_TRIGGER_MIN, CoreLoopKnobs.CHASE_TRIGGER_MAX, 0.5, "suffix:m")
var chase_trigger_radius: float = CoreLoopKnobs.CHASE_TRIGGER_RADIUS

## How long a chase runs on one refresh. Short, so the escape is sprint away,
## break the trigger radius, then go silent and wait.
@export_range(CoreLoopKnobs.CHASE_DURATION_MIN, CoreLoopKnobs.CHASE_DURATION_MAX, 0.5, "suffix:s")
var chase_duration: float = CoreLoopKnobs.CHASE_DURATION

## How long the creature hears nothing before it gives up and despawns.
@export_range(CoreLoopKnobs.DESPAWN_SILENCE_MIN, CoreLoopKnobs.DESPAWN_SILENCE_MAX, 1.0, "suffix:s")
var despawn_silence: float = CoreLoopKnobs.DESPAWN_SILENCE

## The creature's reach. Has to beat the standoff chain or contact never fires at
## all - see the invariant below, which is the failure this slider exists for.
@export_range(CoreLoopKnobs.CATCH_RADIUS_MIN, CoreLoopKnobs.CATCH_RADIUS_MAX, 0.1, "suffix:m")
var catch_radius: float = CoreLoopKnobs.CATCH_RADIUS


func settings_path() -> String:
	return SAVE_PATH


## The standoff the creature settles at in the widest route it can enter.
##
## Three distances stack and none of them is the catch: the marker stops at the
## middle of the corridor, holds FOLLOWER_CLEARANCE off any wall, and the creature
## trails it by CREATURE_LEASH_SLACK. Reported as a function rather than inlined
## because the verifier asserts against the same number the warning quotes.
static func standoff_distance() -> float:
	return (
		CoreLoopKnobs.WIDTH_TRUNK * 0.5
		+ CoreLoopKnobs.FOLLOWER_CLEARANCE
		+ CoreLoopKnobs.CREATURE_LEASH_SLACK
	)


## Cross-knob rules. Every one of these is reachable by dragging a slider, which
## is why they live here rather than as a startup check against the consts.
func invariant_failures() -> PackedStringArray:
	var failures := super.invariant_failures()

	# The one that cost the chase prototype an afternoon, generalised. A creature
	# that arrives and hovers forever looks like broken pathfinding, and the fail
	# state exists on paper only.
	var standoff := standoff_distance()
	if catch_radius <= standoff:
		(
			failures
			. append(
				(
					"catch_radius %.1f m does not beat the %.1f m standoff, so the creature will arrive and hover and contact will never fire"
					% [catch_radius, standoff]
				)
			)
		)

	# Sprint is the only escape that does not need geometry. Without this the
	# player can be outrun in an open trunk with nothing to do about it.
	var sprint_speed := max_speed * CoreLoopKnobs.SPRINT_SPEED_MULTIPLIER
	if sprint_speed <= creature_max_speed:
		(
			failures
			. append(
				(
					"sprinting tops out at %.1f m/s against a creature at %.1f m/s; you cannot outrun it in open tunnel"
					% [sprint_speed, creature_max_speed]
				)
			)
		)

	# The two ends of the noise scale have to sit either side of the spawn
	# threshold, or the loop loses one of its two halves.
	if drill_noise_radius < CoreLoopKnobs.SPAWN_TRIGGER_MIN_RADIUS:
		(
			failures
			. append(
				(
					"drill_noise_radius %.0f m is under the %.0f m spawn threshold, so drilling can never wake the creature"
					% [drill_noise_radius, CoreLoopKnobs.SPAWN_TRIGGER_MIN_RADIUS]
				)
			)
		)
	if thrust_noise_radius >= CoreLoopKnobs.SPAWN_TRIGGER_MIN_RADIUS:
		(
			failures
			. append(
				(
					"thrust_noise_radius %.0f m is at or over the %.0f m spawn threshold, so merely flying summons the creature"
					% [thrust_noise_radius, CoreLoopKnobs.SPAWN_TRIGGER_MIN_RADIUS]
				)
			)
		)

	# Chasing refreshes the silence timer, so a chase longer than the patience it
	# is measured against can never end in a despawn.
	if despawn_silence <= chase_duration:
		(
			failures
			. append(
				(
					"despawn_silence %.1f s is not longer than chase_duration %.1f s; the creature can never lose interest"
					% [despawn_silence, chase_duration]
				)
			)
		)

	# A crystal that cannot come loose is a drill that does nothing, and the two
	# numbers live in different regions of the knobs file.
	if CoreLoopKnobs.ESCAPE_CLEARANCE > carve_radius:
		(
			failures
			. append(
				(
					"escape_clearance %.2f m is wider than the %.2f m bore; a straight hole can never free a crystal"
					% [CoreLoopKnobs.ESCAPE_CLEARANCE, carve_radius]
				)
			)
		)

	return failures
