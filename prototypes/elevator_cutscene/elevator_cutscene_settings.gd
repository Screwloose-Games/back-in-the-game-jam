class_name ElevatorCutsceneSettings
extends PrototypeSettings

## The elevator cutscene prototype's live-tunable values, saved between runs.
##
## Defaults and slider bounds both come from elevator_cutscene_knobs.gd, so this
## file adds no numbers of its own - see PrototypeSettings for why that matters.
##
## THERE IS NO SLIDER FOR SHOT TIMING, AND THAT IS DELIBERATE. Shot times and
## camera poses are baked into animations/elevator_intro.anim.tres by the build
## script; a slider on SHOT2_CUT_TIME would move a number that nothing reads until
## the script is re-run, which is worse than no control at all. playback_speed is
## the one timing lever that can honestly be live. Retime a shot by editing the
## knobs and re-running the build script, or by dragging the key in the Animation
## Dock.

const SAVE_PATH := "res://prototypes/elevator_cutscene/elevator_cutscene_settings.tres"

## How far cutscene_fov may sit from the gameplay camera's before the handover
## snaps visibly. Eyeballed, and generous - the point is to catch someone who has
## dragged the slider to an extreme and forgotten, not to police a few degrees.
const FOV_HANDOVER_TOLERANCE := 25.0

## AnimationPlayer.speed_scale, applied to the clip and to the authoritative
## clock together so effects keep landing on their frames.
@export_range(
	ElevatorCutsceneKnobs.PLAYBACK_SPEED_MIN, ElevatorCutsceneKnobs.PLAYBACK_SPEED_MAX, 0.05
)
var playback_speed: float = ElevatorCutsceneKnobs.PLAYBACK_SPEED

## Seconds to blend the camera back to the player at CLEANUP. Whether handing
## control back reads as a cut or as a settle is a feel question, and feel
## questions can only be answered at speed.
@export_range(
	ElevatorCutsceneKnobs.EXIT_BLEND_TIME_MIN,
	ElevatorCutsceneKnobs.EXIT_BLEND_TIME_MAX,
	0.05,
	"suffix:s"
)
var exit_blend_time: float = ElevatorCutsceneKnobs.EXIT_BLEND_TIME

## Field of view of the cutscene camera. Sets how much of the cramped car is in
## the wide shot, so it changes the composition of every frame at once.
@export_range(
	ElevatorCutsceneKnobs.CUTSCENE_FOV_MIN,
	ElevatorCutsceneKnobs.CUTSCENE_FOV_MAX,
	1.0,
	"suffix:deg"
)
var cutscene_fov: float = ElevatorCutsceneKnobs.CUTSCENE_FOV

## Metres of camera shake while the car is descending.
@export_range(
	ElevatorCutsceneKnobs.RUMBLE_AMPLITUDE_MIN,
	ElevatorCutsceneKnobs.RUMBLE_AMPLITUDE_MAX,
	0.001,
	"suffix:m"
)
var rumble_amplitude: float = ElevatorCutsceneKnobs.RUMBLE_AMPLITUDE

## Shake rate. Low reads as swaying, high as machinery - genuinely different
## scenes, which is why it is a separate dial from the amplitude.
@export_range(
	ElevatorCutsceneKnobs.RUMBLE_FREQUENCY_MIN, ElevatorCutsceneKnobs.RUMBLE_FREQUENCY_MAX, 0.5
)
var rumble_frequency: float = ElevatorCutsceneKnobs.RUMBLE_FREQUENCY

## How fast the shaft lights stream past the wall slot. The descending knob.
@export_range(
	ElevatorCutsceneKnobs.SHAFT_LIGHT_SPEED_MIN,
	ElevatorCutsceneKnobs.SHAFT_LIGHT_SPEED_MAX,
	0.5,
	"suffix:m/s"
)
var shaft_light_speed: float = ElevatorCutsceneKnobs.SHAFT_LIGHT_SPEED

## Metres between shaft lights. The other descending knob - speed and spacing
## trade off, so the pair has to be felt together rather than dialled in turn.
@export_range(
	ElevatorCutsceneKnobs.SHAFT_LIGHT_SPACING_MIN,
	ElevatorCutsceneKnobs.SHAFT_LIGHT_SPACING_MAX,
	0.1,
	"suffix:m"
)
var shaft_light_spacing: float = ElevatorCutsceneKnobs.SHAFT_LIGHT_SPACING

## Ceiling light strength inside the car. How dark it is decides whether the
## quota screen reads at all.
@export_range(
	ElevatorCutsceneKnobs.CEILING_LIGHT_ENERGY_MIN,
	ElevatorCutsceneKnobs.CEILING_LIGHT_ENERGY_MAX,
	0.1
)
var ceiling_light_energy: float = ElevatorCutsceneKnobs.CEILING_LIGHT_ENERGY

## Whether the skip key does anything.
@export var skippable: bool = ElevatorCutsceneKnobs.SKIPPABLE

## Whether the cutscene plays on load, or waits for the replay key.
@export var autoplay_on_start: bool = ElevatorCutsceneKnobs.AUTOPLAY_ON_START


func settings_path() -> String:
	return SAVE_PATH


## Cross-knob rules no single node can see.
##
## Both of these are reachable from a slider at runtime, which is why they live
## here rather than as a startup warning against the consts - a check against the
## consts would pass on a saved .tres that violates them.
func invariant_failures() -> PackedStringArray:
	var failures := super.invariant_failures()

	# The exit blend interpolates position and rotation but not fov, so a cutscene
	# fov far from the gameplay camera's snaps on the handover: a zoom the blend
	# was supposed to hide.
	var fov_gap := absf(cutscene_fov - ElevatorCutsceneKnobs.GAMEPLAY_FOV)
	if fov_gap > FOV_HANDOVER_TOLERANCE:
		(
			failures
			. append(
				(
					"cutscene_fov %.0f is %.0f degrees from the gameplay camera's %.0f; the exit blend does not interpolate fov, so the handover will snap"
					% [cutscene_fov, fov_gap, ElevatorCutsceneKnobs.GAMEPLAY_FOV]
				)
			)
		)

	# The opening close-up is framed so the glass covers the frame EXACTLY at
	# CUTSCENE_FOV, so the fov is not just a composition choice there: wider shows
	# the plate's bezel, narrower starts cropping the crew line.
	var closeup_gap := absf(cutscene_fov - ElevatorCutsceneKnobs.CUTSCENE_FOV)
	if closeup_gap > ElevatorCutsceneKnobs.CLOSEUP_FOV_TOLERANCE:
		(
			failures
			. append(
				(
					"cutscene_fov %.0f is %.0f degrees off the %.0f the opening close-up was framed at; the prologue will show bezel or crop the readout"
					% [cutscene_fov, closeup_gap, ElevatorCutsceneKnobs.CUTSCENE_FOV]
				)
			)
		)

	# The bar column has to be longer than the slot it is seen through, or it
	# visibly runs out and restarts - which reads as the lift stopping and
	# starting rather than as a spacing problem.
	var column_length := shaft_light_spacing * ElevatorCutsceneKnobs.SHAFT_LIGHT_COUNT
	var minimum_length := ElevatorCutsceneKnobs.SHAFT_SLOT_HEIGHT * 2.0
	if column_length < minimum_length:
		failures.append(
			(
				"shaft light column is %.1f m for a %.1f m slot; the stream will visibly gap"
				% [column_length, ElevatorCutsceneKnobs.SHAFT_SLOT_HEIGHT]
			)
		)

	return failures
