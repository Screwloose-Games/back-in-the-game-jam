class_name ElevatorCutscenePrototype
extends Node3D

## The tuning harness for the shipped elevator intro.
##
## THE CUTSCENE IS NOT HERE ANY MORE. It is levels/asteroid_level/intro/, and
## this scene instances the same elevator_intro.tscn the level does - so a shot
## composed here is the shot that ships, and there is no second copy to drift.
## What is still here is everything a director needs and a level must not have: a
## greybox shaft to see the car against, a replay key, and the tuning panel.
##
## What this prototype is testing, in one line each:
##   - a cutscene can take the camera off a live player and give it back cleanly
##   - keyframes and state changes can be kept apart, and skipping proves it
##   - a director can scrub the shot in the editor and see what will actually run

## Live-tunable values and what SAVE writes back to. Assigned in the .tscn.
@export var settings: ElevatorCutsceneSettings

var _rig: CutscenePlayerRig

@onready var _intro: ElevatorIntro = $Intro
@onready var _player: Node3D = $Player
@onready var _tuning: PrototypeTuningPanel = $Tuning/Panel


func _ready() -> void:
	# A fresh clone has no .tres yet, and anyone may delete it. A bare instance
	# holds exactly the knobs consts, so the fallback is the declared behaviour
	# rather than a crash.
	if settings == null:
		settings = ElevatorCutsceneSettings.new()
		push_warning(
			"No elevator_cutscene_settings.tres wired; running on elevator_intro_knobs.gd defaults."
		)
	settings.changed.connect(_apply_settings)
	_tuning.bind(settings)

	_rig = CutscenePlayerRig.for_player(_player)
	add_child(_rig)
	_intro.bind_player(_rig, _player.get_node_or_null("PlayerBody/UI/HudBinding"))
	# Decided here rather than left to tree order. Several cameras in this scene
	# each believe they may be current, and whichever readies last would win - a
	# property of the scene dock, not of anything anyone chose.
	_rig.get_head_camera().current = true

	_apply_settings()
	if settings.autoplay_on_start:
		# Deferred, so every child's _ready has run and the CSG geometry both the
		# camera and the exit check depend on actually exists.
		_intro.play.call_deferred()


## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while playing" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
func _apply_settings() -> void:
	_intro.apply_tuning(
		settings.rumble_amplitude,
		settings.rumble_frequency,
		settings.cutscene_fov,
		settings.ceiling_light_energy,
		settings.shaft_light_speed,
		settings.shaft_light_spacing,
		settings.playback_speed
	)
	_intro.get_cutscene().exit_blend_time = settings.exit_blend_time
	_intro.get_cutscene().data.skippable = settings.skippable

	for failure: String in settings.invariant_failures():
		push_warning("elevator_cutscene_settings: %s" % failure)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("elevator_skip"):
		_intro.skip()
		return
	if not event.is_action_pressed("elevator_replay"):
		return
	# Play it from anywhere, ignoring triggers - the ten-second edit-to-see loop
	# the spec asks for. Without it, testing a forty-second cinematic means
	# relaunching the scene every time, and it gets watched about four times
	# total before it ships.
	_intro.play()
