class_name TunnelSettings
extends PrototypeSettings

## The tunnel prototype's live-tunable optics, saved between runs.
##
## Defaults and slider bounds both come from tunnel_knobs.gd, so this file adds
## no numbers of its own - see PrototypeSettings for why that matters.
##
## HELMET_LAMP_RANGE AND CAMERA_FAR ARE DELIBERATELY ABSENT. Both are derived
## from FOG_DEPTH_END in the knobs, and set_view_distance() re-derives them from
## view_distance here. Giving either one its own slider would turn an invariant
## that is currently structural back into three numbers that can disagree, which
## is exactly what the knobs docstring was written to prevent.

const SAVE_PATH := "res://prototypes/tunnel_system/tunnel_settings.tres"

## How far you can see, in metres. Moves fog, lamp throw and clip plane together.
@export_range(TunnelKnobs.VIEW_DISTANCE_MIN, TunnelKnobs.VIEW_DISTANCE_MAX, 1.0, "suffix:m")
var view_distance: float = TunnelKnobs.FOG_DEPTH_END

## Half-angle of the helmet lamp cone in degrees, so 45 is a 90 degree spread.
@export_range(TunnelKnobs.LAMP_ANGLE_MIN, TunnelKnobs.LAMP_ANGLE_MAX, 1.0)
var helmet_lamp_angle: float = TunnelKnobs.HELMET_LAMP_ANGLE

## Fill light on rock the lamp never reaches. Near-black by default; there is no
## sky down here, so this is the whole difference between "dark" and "invisible".
@export_range(0.0, 0.5, 0.005) var ambient_energy: float = TunnelKnobs.AMBIENT_ENERGY

## How sharply fog ramps between begin and end. Higher reads as thicker murk.
@export_range(0.0, 4.0, 0.05) var fog_density: float = TunnelKnobs.FOG_DENSITY

## Lamp shadows. On by default, and the knobs file explains at length why the
## banding artefact is the better trade - turn it off to see the alternative.
@export var helmet_lamp_shadows: bool = TunnelKnobs.HELMET_LAMP_SHADOWS


func settings_path() -> String:
	return SAVE_PATH
