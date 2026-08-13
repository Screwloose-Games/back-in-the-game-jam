class_name DrillSettings
extends PrototypeSettings

## The drill and mining prototype's live-tunable numbers, saved between runs.
##
## Defaults and slider bounds both come from drill_knobs.gd, so this file adds no
## numbers of its own - see PrototypeSettings for why that matters.
##
## Only what is worth arguing about while flying is here. Everything else stays a
## const, and retiring an answered question means deleting its @export_range from
## this file rather than switching something off: the shared tuning panel builds
## itself from whatever it finds here, so the annotation is the only opt-in there
## is.

const SAVE_PATH := "res://prototypes/drill_and_mining/drill_settings.tres"

## How fast the rock surface recedes at the centre of the bore. The number that
## decides whether the drill feels like it is eating material or timing it.
@export_range(DrillKnobs.CARVE_RATE_MIN, DrillKnobs.CARVE_RATE_MAX, 0.05, "suffix:m/s")
var carve_rate: float = DrillKnobs.CARVE_RATE

## How wide a hole the beam opens, as against how fast it deepens it. The other
## half of the same question, and the one that decides whether a single straight
## bore is enough to free a crystal.
@export_range(DrillKnobs.CARVE_RADIUS_MIN, DrillKnobs.CARVE_RADIUS_MAX, 0.01, "suffix:m")
var carve_radius: float = DrillKnobs.CARVE_RADIUS

## How far the beam reaches. Short keeps the zero-G positioning problem in play;
## long lets you stand off and ignore it.
@export_range(DrillKnobs.DRILL_RANGE_MIN, DrillKnobs.DRILL_RANGE_MAX, 0.5, "suffix:m")
var drill_range: float = DrillKnobs.DRILL_RANGE

## How wide a clear tube out of the rock the crystal needs before it comes loose.
@export_range(DrillKnobs.ESCAPE_CLEARANCE_MIN, DrillKnobs.ESCAPE_CLEARANCE_MAX, 0.01, "suffix:m")
var escape_clearance: float = DrillKnobs.ESCAPE_CLEARANCE

## Fragments thrown per second while the beam is cutting.
@export_range(DrillKnobs.DEBRIS_SPAWN_RATE_MIN, DrillKnobs.DEBRIS_SPAWN_RATE_MAX, 1.0, "suffix:/s")
var debris_spawn_rate: float = DrillKnobs.DEBRIS_SPAWN_RATE

## How hard a fragment is thrown. What "the drill is powerful" is actually made
## of, and now independent of how fast the hole deepens.
@export_range(DrillKnobs.DEBRIS_KNOCK_MIN, DrillKnobs.DEBRIS_KNOCK_MAX, 0.5)
var debris_knock: float = DrillKnobs.DEBRIS_KNOCK

## How long loose rock stays in the room. Also the frame-rate lever.
@export_range(DrillKnobs.DEBRIS_LIFETIME_MIN, DrillKnobs.DEBRIS_LIFETIME_MAX, 0.1, "suffix:s")
var debris_lifetime: float = DrillKnobs.DEBRIS_LIFETIME

## How close you have to get to a freed crystal to collect it, measured from its
## centre. The suit is a 0.4 m sphere, so the gap you close is this minus that.
@export_range(DrillKnobs.COLLECT_RADIUS_MIN, DrillKnobs.COLLECT_RADIUS_MAX, 0.05, "suffix:m")
var collect_radius: float = DrillKnobs.COLLECT_RADIUS

## Metres at which geometry is fully swallowed by fog - how far you can see.
@export_range(DrillKnobs.FOG_DEPTH_END_MIN, DrillKnobs.FOG_DEPTH_END_MAX, 1.0, "suffix:m")
var fog_depth_end: float = DrillKnobs.FOG_DEPTH_END

## Hard clip distance. Keep it above fog_depth_end or geometry pops out before
## the fog has hidden it, which is what the first invariant below checks.
@export_range(DrillKnobs.CAMERA_FAR_MIN, DrillKnobs.CAMERA_FAR_MAX, 1.0, "suffix:m")
var camera_far: float = DrillKnobs.CAMERA_FAR

## The floor under everything the helmet lamp is not pointed at. A slider because
## how dark this prototype should be is genuinely unsettled, and because it is
## the fastest way to tell rock that is unreadable from rock that is merely unlit.
@export_range(DrillKnobs.AMBIENT_ENERGY_MIN, DrillKnobs.AMBIENT_ENERGY_MAX, 0.01)
var ambient_energy: float = DrillKnobs.AMBIENT_ENERGY


func settings_path() -> String:
	return SAVE_PATH


## Cross-knob rules. All three are reachable by dragging a slider, which is why
## they live here rather than as a startup check against the consts.
func invariant_failures() -> PackedStringArray:
	var failures := super.invariant_failures()
	if camera_far <= fog_depth_end:
		failures.append(
			(
				"camera_far %.1f is not past fog_depth_end %.1f; geometry pops at the clip"
				% [camera_far, fog_depth_end]
			)
		)
	if escape_clearance > carve_radius:
		(
			failures
			. append(
				(
					"escape_clearance %.2f m is wider than the %.2f m bore; a straight hole can never free a crystal and you have to sweep one open"
					% [escape_clearance, carve_radius]
				)
			)
		)
	# Heft stretches a heavy fragment's life, so the average one outlives the
	# slider. Rate times MEAN life is what is actually in the air.
	var mean_lifetime := (
		debris_lifetime
		* lerpf(1.0, DrillKnobs.DEBRIS_HEAVY_LIFETIME_SCALE, DrillKnobs.DEBRIS_MEAN_HEFT)
	)
	var live_debris := debris_spawn_rate * mean_lifetime
	if live_debris > float(DrillKnobs.DEBRIS_POOL_SIZE):
		(
			failures
			. append(
				(
					"%.0f/s for a mean %.1fs implies %.0f fragments in the air against a pool of %d; the pool wins and both sliders stop meaning what they say"
					% [
						debris_spawn_rate,
						mean_lifetime,
						live_debris,
						DrillKnobs.DEBRIS_POOL_SIZE,
					]
				)
			)
		)
	return failures
