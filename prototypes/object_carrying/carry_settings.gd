class_name CarrySettings
extends PrototypeSettings

## The object-carrying prototype's live-tunable grip, tether and murk, saved
## between runs.
##
## Defaults and slider bounds both come from carry_knobs.gd, so this file adds no
## numbers of its own - see PrototypeSettings for why that matters.
##
## The rope's segment count, radius, iteration count and friction are all absent
## on purpose. carry_knobs.gd says outright that tether_break_stretch is the knob
## to reach for and those are not, and a panel that disagrees with the knobs file
## about which number matters is worse than no panel.

const SAVE_PATH := "res://prototypes/object_carrying/carry_settings.tres"

## Thruster strength in metres per second squared, per axis. Typed float
## explicitly - the knob is written `10`, so inference would make this an int.
@export_range(1.0, 40.0, 0.5) var thrust_acceleration: float = CarryKnobs.THRUST_ACCELERATION

## Ceiling on drift speed. Applies to the suit whether or not it is carrying.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_speed: float = CarryKnobs.MAX_SPEED

## How stiff the hands are. Higher snaps the load to the carry pose; lower lets
## it swing behind you and lag through direction changes.
@export_range(0.2, 8.0, 0.1) var grip_spring_frequency: float = CarryKnobs.GRIP_SPRING_FREQUENCY

## How far the load may drift from the carry pose before the hands give out.
@export_range(0.2, 4.0, 0.05, "suffix:m")
var grip_break_distance: float = CarryKnobs.GRIP_BREAK_DISTANCE

## Rope length. Applied when a load is CLIPPED, not while one is on the line -
## the rope is laid out straight at that moment and its segment count comes from
## this. Move the slider, press T twice, and the new length is what you get.
@export_range(2.0, 30.0, 0.5, "suffix:m") var tether_length: float = CarryKnobs.TETHER_LENGTH

## How far past its length the tether stretches before it lets go.
@export_range(0.2, 6.0, 0.1, "suffix:m")
var tether_break_stretch: float = CarryKnobs.TETHER_BREAK_STRETCH

## What the load weighs while the hands are on it.
##
## The whole prototype turns on this one: it decides whether the module is
## something you haul or something you are moored to.
@export_range(20.0, 2000.0, 10.0, "suffix:kg")
var carry_object_held_mass: float = CarryKnobs.CARRY_OBJECT_HELD_MASS

## Metres at which geometry is fully swallowed by fog.
@export_range(5.0, 80.0, 1.0, "suffix:m") var fog_depth_end: float = CarryKnobs.FOG_DEPTH_END

## Hard clip distance. Keep it above fog_depth_end or geometry pops out before
## the fog has hidden it - see the invariant below.
@export_range(5.0, 120.0, 1.0, "suffix:m") var camera_far: float = CarryKnobs.CAMERA_FAR


func settings_path() -> String:
	return SAVE_PATH


## The startup warning that used to live in object_carrying_prototype.gd, moved
## here so it is checked against the SAVED values rather than only the consts.
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
