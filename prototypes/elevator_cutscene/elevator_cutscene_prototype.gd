class_name ElevatorCutscenePrototype
extends Node3D

## Root of the elevator intro cutscene prototype.
##
## Wires the pieces together and owns the two things no single piece can: which
## camera is current, and what the tuning panel's values mean.
##
## What this prototype is testing, in one line each:
##   - a cutscene can take the camera off a live player and give it back cleanly
##   - keyframes and state changes can be kept apart, and skipping proves it
##   - a director can scrub the shot in the editor and see what will actually run

## Live-tunable values and what SAVE writes back to. Assigned in the .tscn.
@export var settings: ElevatorCutsceneSettings

@onready var _rig: CutscenePlayerRig = $PlayerRig
@onready var _rig_shape: CollisionShape3D = _rig.get_hull_shape()
@onready var _car: ElevatorCar = $ElevatorCar
@onready var _camera_driver: CutsceneCameraDriver = $CutsceneCamera
@onready var _cutscene: ElevatorCutscenePlayer = $Cutscenes/ElevatorIntro
@onready var _effects: ElevatorEffects = $Cutscenes/ElevatorIntro/Effects
@onready var _player_start: Node3D = $PlayerStart
@onready var _player_exit: Node3D = $PlayerExit
@onready var _hud: ElevatorCutsceneHud = $HUD
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


func _ready() -> void:
	# A fresh clone has no .tres yet, and anyone may delete it. A bare instance
	# holds exactly the knobs consts, so the fallback is the declared behaviour
	# rather than a crash.
	if settings == null:
		settings = ElevatorCutsceneSettings.new()
		push_warning(
			"No elevator_cutscene_settings.tres wired; running on elevator_cutscene_knobs.gd defaults."
		)
	settings.changed.connect(_apply_settings)
	_tuning.bind(settings)

	# The rig captures its spawn pose in its own _ready, and children ready before
	# parents - so moving it here means telling it about the move as well, or
	# Backspace would send the player back to wherever the .tscn happened to put
	# the node.
	_rig.global_transform = _player_start.global_transform
	_rig.set_spawn_transform(_player_start.global_transform)

	_free_pause_screen()
	# The cutscene camera is not the player's camera, so it does not inherit the
	# cull mask that keeps a first-person player out of their own frame. Without
	# this it photographs the player's own suit standing in the car.
	_camera_driver.cull_mask = PlayerRenderLayers.local_camera_cull_mask()

	_camera_driver.bind(_rig.get_head_camera())
	# Decided here rather than left to tree order. Three cameras in this scene
	# each believe they may be current, and whichever readies last would win -
	# a property of the scene dock, not of anything anyone chose. The parent
	# readies after all of them, so this is the last word.
	_rig.get_head_camera().current = true

	var miners: Array[MinerRig] = []
	for miner: MinerRig in $Miners.get_children():
		miners.append(miner)
	_effects.bind(_car, _camera_driver, _hud, miners)
	_cutscene.bind(self, _rig, _rig_shape, _player_exit, _camera_driver, _hud, _effects)

	_hud.set_gameplay_visible(true)
	_hud.set_skip_prompt_visible(false)
	_apply_settings()

	if settings.autoplay_on_start:
		# Deferred, so every child's _ready has run and the CSG geometry both the
		# camera and the exit check depend on actually exists.
		_play.call_deferred()


## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while playing" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
## The one path that can hand input back behind the cutscene's back.
##
## PauseMenu._on_game_unpaused sets input.enabled = true unconditionally, so a
## pause and unpause mid-shot un-parks the rig while its collision is still off
## and its camera is still taken. There is no pause flow to test in a nineteen
## second prototype, so the menu goes rather than being worked around.
func _free_pause_screen() -> void:
	var pause_screen := get_node_or_null("Player/PlayerBody/UI/PauseScreen")
	if pause_screen != null:
		pause_screen.queue_free()


func _apply_settings() -> void:
	_camera_driver.rumble_amplitude = settings.rumble_amplitude
	_camera_driver.rumble_frequency = settings.rumble_frequency
	_camera_driver.cutscene_fov = settings.cutscene_fov
	# The opening 2D shot has to crop to whatever the 3D close-up will frame, so
	# the fov slider moves both or the match cut stops matching.
	_hud.set_monitor_framing(ElevatorCutsceneKnobs.CLOSEUP_DISTANCE, settings.cutscene_fov)
	_car.apply_settings(settings)
	_cutscene.set_speed_scale(settings.playback_speed)
	_cutscene.data.skippable = settings.skippable

	for failure: String in settings.invariant_failures():
		push_warning("elevator_cutscene_settings: %s" % failure)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("elevator_skip"):
		_cutscene.skip()
		return
	if not event.is_action_pressed("elevator_replay"):
		return
	# Play it from anywhere, ignoring triggers - the ten-second edit-to-see loop
	# the spec asks for. Without it, testing a nineteen-second cinematic means
	# relaunching the scene every time, and it gets watched about four times
	# total before it ships.
	_play()


func _play() -> void:
	if _cutscene.is_playing():
		return
	_rig.global_transform = _player_start.global_transform
	_cutscene.enter(ElevatorCutsceneKnobs.ENTER_BLEND_TIME)


func _process(_delta: float) -> void:
	# Built into a local first. Passing the formatted string straight to the call
	# makes gdformat wrap it into a parenthesised method chain that is unreadable.
	var readout := (
		"camera: %s\nclock: %.2f / %.2f s\neffects fired: %d\nhud: %s  doors: %s  workday: %s\ndrift: %.2f m/s"
		% [
			"CUTSCENE" if _camera_driver.has_control() else "player",
			_cutscene.get_clock(),
			_cutscene.get_length(),
			_cutscene.get_fired_count(),
			_effects.hud_online,
			_effects.doors_unlocked,
			_effects.workday_begun,
			_rig.get_drift_speed(),
		]
	)
	_hud.set_readout(readout)
