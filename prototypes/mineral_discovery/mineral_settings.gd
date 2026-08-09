class_name MineralSettings
extends PrototypeSettings

## The mineral-discovery values worth moving mid-playtest, saved between runs.
##
## Two material sets (the ore and the rock it sits in), the proximity-marker
## controls, and the mining timings - the exact dials the four questions in the
## issue ask a tester to turn. Every default and every slider bound comes from
## MineralKnobs; this file adds no numbers of its own, so RESET always lands back
## on the knobs file. See PrototypeSettings for why that matters.
##
## Floats are typed explicitly: a knob written without a decimal point would infer
## int and step the slider in whole units.

const SAVE_PATH := "res://prototypes/mineral_discovery/mineral_settings.tres"

# --- Deposit material (Q1) -------------------------------------------------

@export_range(MineralKnobs.DEPOSIT_HUE_MIN, MineralKnobs.DEPOSIT_HUE_MAX, 0.01)
var deposit_hue: float = MineralKnobs.DEPOSIT_HUE

@export_range(MineralKnobs.DEPOSIT_SATURATION_MIN, MineralKnobs.DEPOSIT_SATURATION_MAX, 0.01)
var deposit_saturation: float = MineralKnobs.DEPOSIT_SATURATION

@export_range(MineralKnobs.DEPOSIT_LIGHTNESS_MIN, MineralKnobs.DEPOSIT_LIGHTNESS_MAX, 0.01)
var deposit_lightness: float = MineralKnobs.DEPOSIT_LIGHTNESS

@export_range(
	MineralKnobs.DEPOSIT_EMISSION_ENERGY_MIN, MineralKnobs.DEPOSIT_EMISSION_ENERGY_MAX, 0.05
)
var deposit_emission_energy: float = MineralKnobs.DEPOSIT_EMISSION_ENERGY

@export_range(MineralKnobs.DEPOSIT_ROUGHNESS_MIN, MineralKnobs.DEPOSIT_ROUGHNESS_MAX, 0.01)
var deposit_roughness: float = MineralKnobs.DEPOSIT_ROUGHNESS

@export_range(MineralKnobs.DEPOSIT_SPECULAR_MIN, MineralKnobs.DEPOSIT_SPECULAR_MAX, 0.01)
var deposit_specular: float = MineralKnobs.DEPOSIT_SPECULAR

# --- Environment material (Q1 contrast) ------------------------------------

@export_range(MineralKnobs.ENV_HUE_MIN, MineralKnobs.ENV_HUE_MAX, 0.01)
var env_hue: float = MineralKnobs.ENV_HUE

@export_range(MineralKnobs.ENV_SATURATION_MIN, MineralKnobs.ENV_SATURATION_MAX, 0.01)
var env_saturation: float = MineralKnobs.ENV_SATURATION

@export_range(MineralKnobs.ENV_LIGHTNESS_MIN, MineralKnobs.ENV_LIGHTNESS_MAX, 0.01)
var env_lightness: float = MineralKnobs.ENV_LIGHTNESS

@export_range(MineralKnobs.ENV_ROUGHNESS_MIN, MineralKnobs.ENV_ROUGHNESS_MAX, 0.01)
var env_roughness: float = MineralKnobs.ENV_ROUGHNESS

@export_range(MineralKnobs.ENV_SPECULAR_MIN, MineralKnobs.ENV_SPECULAR_MAX, 0.01)
var env_specular: float = MineralKnobs.ENV_SPECULAR

# --- Proximity markers (Q4) ------------------------------------------------

## Draw the HUD markers at all. Toggle off to feel the see-and-decide loop
## without an assist.
@export var markers_enabled: bool = MineralKnobs.MARKERS_ENABLED

@export_range(MineralKnobs.MARKER_PROXIMITY_MIN, MineralKnobs.MARKER_PROXIMITY_MAX, 0.5, "suffix:m")
var marker_proximity: float = MineralKnobs.MARKER_PROXIMITY

# --- Mining ----------------------------------------------------------------

@export_range(MineralKnobs.EXTRACT_TIME_MIN, MineralKnobs.EXTRACT_TIME_MAX, 0.1, "suffix:s")
var extract_time: float = MineralKnobs.EXTRACT_TIME

@export_range(MineralKnobs.EXTRACT_RANGE_MIN, MineralKnobs.EXTRACT_RANGE_MAX, 0.5, "suffix:m")
var extract_range: float = MineralKnobs.EXTRACT_RANGE


func settings_path() -> String:
	return SAVE_PATH
