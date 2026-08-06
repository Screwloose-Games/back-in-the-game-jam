class_name NavigationSettings
extends PrototypeSettings

## The navigation prototype's live-tunable flight feel and murk, saved between
## runs.
##
## Defaults and slider bounds both come from prototype_knobs.gd, so this file
## adds no numbers of its own - see PrototypeSettings for why that matters.
##
## This is the set the zero-G controller reads, and ZeroGPlayer is instanced by
## the tunnel prototype too. A player nobody binds a resource to falls back to a
## bare instance, which holds exactly the consts, so binding this here does not
## reach across into the other prototype.

const SAVE_PATH := "res://prototypes/navigation/navigation_settings.tres"

## Thruster strength in metres per second squared, per axis. Sprint multiplies
## this, so moving it moves sprinting and cruising together.
##
## Typed float explicitly rather than inferred: a knob written without a decimal
## point would make this an int and the slider step in whole units.
@export_range(1.0, 40.0, 0.5) var thrust_acceleration: float = PrototypeKnobs.THRUST_ACCELERATION

## Ceiling on drift speed, before sprint. SPRINT_SPEED_MULTIPLIER is a ratio on
## top of this, so the sprint ceiling follows it up and down.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_speed: float = PrototypeKnobs.MAX_SPEED

## Radians of rotation per pixel of mouse movement.
@export_range(0.0002, 0.01, 0.0001) var mouse_sensitivity: float = PrototypeKnobs.MOUSE_SENSITIVITY

## Fraction of tumble rate shed per second with no input held.
##
## The dial between the two rotation modes: at 0.0 a flick spins you until you
## counter it, and as it climbs the spin dies sooner, approaching DIRECT.
@export_range(0.0, 8.0, 0.1) var angular_drag: float = PrototypeKnobs.ANGULAR_DRAG

## How much of the into-the-wall speed is thrown back out on impact. 0.0 absorbs
## the hit dead, 1.0 is a perfect elastic bounce.
@export_range(0.0, 1.0, 0.05) var collision_restitution: float = PrototypeKnobs.COLLISION_RESTITUTION

## Metres at which geometry is fully swallowed by fog. The number that actually
## sets how far you can see.
@export_range(4.0, 60.0, 1.0, "suffix:m") var fog_depth_end: float = PrototypeKnobs.FOG_DEPTH_END

## Hard clip distance. Keep it above fog_depth_end or geometry pops out before
## the fog has hidden it - which is what the [clip] invariant below checks.
##
## Independent rather than derived, unlike the tunnel prototype, because that is
## how prototype_knobs.gd has it and the two prototypes are allowed to differ.
@export_range(4.0, 90.0, 1.0, "suffix:m") var camera_far: float = PrototypeKnobs.CAMERA_FAR

## How far the helmet lamp throws.
@export_range(4.0, 80.0, 1.0, "suffix:m")
var helmet_lamp_range: float = PrototypeKnobs.HELMET_LAMP_RANGE


func settings_path() -> String:
	return SAVE_PATH


## The startup warning that used to live in navigation_prototype.gd, moved here
## so it is checked against the SAVED values rather than only against the consts.
func invariant_failures() -> PackedStringArray:
	var failures := super.invariant_failures()
	if camera_far <= fog_depth_end:
		failures.append(
			(
				"camera_far %.1f is not past fog_depth_end %.1f; geometry pops at the clip"
				% [camera_far, fog_depth_end]
			)
		)
	return failures
