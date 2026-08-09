class_name MineralKnobs
extends RefCounted

## Every default this prototype adds, and the MIN/MAX bounds its sliders clamp
## to. The single place a mineral-discovery number is written down; the settings
## resource reads its defaults and its slider ends from here and holds none of
## its own.
##
## Power, lamp, tether and movement values are NOT copied here. The suit and the
## lamp response already read them from MovementKnobs / PowerKnobs, so this file
## points at those rather than keeping a second copy that could drift. What lives
## here is only what mineral discovery invents: how the ore and the rock look,
## how the proximity markers behave, and how mining plays out.

# --- Deposit material ------------------------------------------------------
#
# The look the tuning panel drags to answer Q1: does this read as "valuable ore"
# under the headlamp without becoming a glowing arcade pickup? Colour is one
# shared material across every deposit ON PURPOSE - richer deposits are harder to
# reach, not differently coloured - so these move all of them at once. Colour is
# authored in HSV (hue, saturation, lightness/value) so brightness stays its own
# slider rather than being tangled into the albedo.

## Warm gold, the ore's hue. 0..1 around the colour wheel.
const DEPOSIT_HUE := 0.11
const DEPOSIT_HUE_MIN := 0.0
const DEPOSIT_HUE_MAX := 1.0

## How saturated the ore reads.
const DEPOSIT_SATURATION := 0.75
const DEPOSIT_SATURATION_MIN := 0.0
const DEPOSIT_SATURATION_MAX := 1.0

## HSV value: how light the albedo is before the lamp reaches it.
const DEPOSIT_LIGHTNESS := 0.62
const DEPOSIT_LIGHTNESS_MIN := 0.0
const DEPOSIT_LIGHTNESS_MAX := 1.0

## Self-glow. Kept low by default so the ore catches the eye by how it takes the
## lamp, not by lighting itself like a pickup. Zero is a legitimate answer.
const DEPOSIT_EMISSION_ENERGY := 0.3
const DEPOSIT_EMISSION_ENERGY_MIN := 0.0
const DEPOSIT_EMISSION_ENERGY_MAX := 4.0

## Surface roughness. Low is glassy and throws a hard highlight; high is matte.
const DEPOSIT_ROUGHNESS := 0.35
const DEPOSIT_ROUGHNESS_MIN := 0.0
const DEPOSIT_ROUGHNESS_MAX := 1.0

## Specular strength, StandardMaterial3D.metallic_specular. How bright the
## headlamp glint is - the other half of "reads as metal" alongside roughness.
const DEPOSIT_SPECULAR := 0.65
const DEPOSIT_SPECULAR_MIN := 0.0
const DEPOSIT_SPECULAR_MAX := 1.0

# --- Environment material --------------------------------------------------
#
# The rock the ore sits in. Q1 is really a contrast question, so the surrounding
# material is tunable too: legibility is the gap between these and the deposit
# values, not either one alone.

## Cool grey rock hue.
const ENV_HUE := 0.6
const ENV_HUE_MIN := 0.0
const ENV_HUE_MAX := 1.0

const ENV_SATURATION := 0.08
const ENV_SATURATION_MIN := 0.0
const ENV_SATURATION_MAX := 1.0

const ENV_LIGHTNESS := 0.26
const ENV_LIGHTNESS_MIN := 0.0
const ENV_LIGHTNESS_MAX := 1.0

const ENV_ROUGHNESS := 0.9
const ENV_ROUGHNESS_MIN := 0.0
const ENV_ROUGHNESS_MAX := 1.0

const ENV_SPECULAR := 0.2
const ENV_SPECULAR_MIN := 0.0
const ENV_SPECULAR_MAX := 1.0

# --- Proximity markers -----------------------------------------------------
#
# The HUD assist Q4 weighs: help, or a crutch that replaces looking with a
# waypoint? Both the on/off and the range are meant to be moved mid-playtest.

## Whether markers draw at all. The one Q4 exists to answer, so it starts ON to
## be judged and toggled off to feel the loop without it.
const MARKERS_ENABLED := true

## How near a deposit has to be, in metres, before its marker appears.
const MARKER_PROXIMITY := 12.0
const MARKER_PROXIMITY_MIN := 2.0
const MARKER_PROXIMITY_MAX := 40.0

## Straight-line budget, in metres, that splits a marker into "reachable" and
## "risky" colours - measured from the mooring buoy, so it answers Q2's "can I
## get there on the leash?" at a glance. Defaults to the tether's own length.
const MARKER_REACH_RANGE := MovementKnobs.TETHER_LENGTH

# --- Mining ----------------------------------------------------------------
#
# A stand-in interaction: look at a deposit and hold to extract. Just enough to
# give reaching one a payoff. Drill FEEL is the Drill Prototype's job, not this.

## Seconds of continuous extraction to empty one deposit.
const EXTRACT_TIME := 2.0
const EXTRACT_TIME_MIN := 0.5
const EXTRACT_TIME_MAX := 6.0

## How close the crosshair-to-deposit ray reaches, in metres.
const EXTRACT_RANGE := 3.0
const EXTRACT_RANGE_MIN := 1.0
const EXTRACT_RANGE_MAX := 8.0

## Physics layer 5 as a bitmask. Deposits sit here rather than on the carryable
## layer so the suit's own grab/tether ray never targets ore - mining is a
## separate ray this prototype casts. Layers 1..4 are hull/player/debris/
## carryable in project.godot; 5 is free.
const MINERAL_LAYER_BIT := 1 << 4

# --- Spawns ----------------------------------------------------------------

## Where the suit starts. Matches the movement prototypes so the feel carries
## over. The suit faces -Z (Vector3.FORWARD) from here.
const SUIT_SPAWN := Vector3(0.0, 0.0, 6.0)

## The mooring buoy, set just ahead of the suit and inside GRAB_RANGE so the
## start-of-run auto-clip finds it under the crosshair. Being moored is the
## default state; unclipping to chase far ore is the deliberate, draining risk.
const BUOY_SPAWN := Vector3(0.0, 0.0, 4.4)

# --- Lamp ------------------------------------------------------------------

## Whether the helmet lamp dims and flickers as the suit battery falls. ON so
## that unclipping has a VISIBLE cost, not just a number ticking down. While
## moored the tether out-charges the drain, so the lamp sits steady - which is
## also the stable light Q1's material read wants, for free.
const LAMP_RESPONDS_TO_POWER := true
