class_name ElevatorIntro
extends Node3D

## The asteroid level's opening: a descent, a match cut, and a door shut in your face.
##
## SELF-CONTAINED, BECAUSE TWO SCENES INSTANCE IT. asteroid_level places it
## against the mine mouth's back wall; the prototype places it in a greybox shaft
## with a tuning panel. Everything the shot is composed against - the car, the
## crew, the markers, the camera, the overlay - is in here, so the two placements
## cannot show different films. The one thing that is NOT in here is a
## WorldEnvironment: PlayerView writes fog into the level's shared one at _ready,
## and a second one riding in with the cutscene would silently repaint the level.

signal finished

## Where the player ends up. Position it so this lands on the level's own spawn
## marker and CLEANUP's teleport is invisible.
@export var player_start: Node3D
@export var player_exit: Node3D

var _rig: CutscenePlayerRig
var _hud_binding: Node

@onready var _car: ElevatorCar = $ElevatorCar
@onready var _camera_driver: CutsceneCameraDriver = $CutsceneCamera
@onready var _cutscene: CutscenePlayer = $Cutscenes/ElevatorIntro
@onready var _effects: ElevatorIntroEffects = $Cutscenes/ElevatorIntro/Effects
@onready var _gesture: PlayerGestureProxy = $Cutscenes/ElevatorIntro/Gesture
@onready var _hud: ElevatorIntroHud = $Hud
@onready var _hud_boot: HudBootCrt = $HudBoot
@onready var _vo: AudioStreamPlayer = $Vo


func _ready() -> void:
	var miners: Array[MinerRig] = []
	for miner: MinerRig in $Miners.get_children():
		miners.append(miner)
	_effects.bind(_car, _camera_driver, _hud, miners)
	_effects.bind_audio(_vo)
	_effects.bind_hud_boot(_hud_boot)
	_cutscene.exit_blend_time = ElevatorIntroKnobs.EXIT_BLEND_TIME
	_cutscene.rig_hull_radius = ElevatorIntroKnobs.RIG_HULL_RADIUS
	_cutscene.finished.connect(finished.emit)
	_hud.set_skip_prompt_visible(false)
	_hud.set_monitor_framing(ElevatorIntroKnobs.CLOSEUP_DISTANCE, ElevatorIntroKnobs.CUTSCENE_FOV)
	apply_tuning(
		ElevatorIntroKnobs.RUMBLE_AMPLITUDE,
		ElevatorIntroKnobs.RUMBLE_FREQUENCY,
		ElevatorIntroKnobs.CUTSCENE_FOV,
		ElevatorIntroKnobs.CEILING_LIGHT_ENERGY,
		ElevatorIntroKnobs.SHAFT_LIGHT_SPEED,
		ElevatorIntroKnobs.SHAFT_LIGHT_SPACING,
		ElevatorIntroKnobs.PLAYBACK_SPEED
	)


## Hands the intro a live player, then parks it in the car ready to start.
##
## THE SPAWN POSE MOVES TOO. PlayerRespawn snapshots the body transform in its own
## _ready, so a level that repositions the player afterwards has to say so or
## death sends them back to wherever the .tscn happened to put the node.
func bind_player(rig: CutscenePlayerRig, hud_binding: Node) -> void:
	_rig = rig
	_hud_binding = hud_binding
	# The cutscene camera is not the player's camera, so it does not inherit the
	# cull mask that keeps a first-person player out of their own frame. Without
	# this it photographs the player's own suit standing in the car.
	_camera_driver.cull_mask = PlayerRenderLayers.local_camera_cull_mask()
	_camera_driver.bind(rig.get_head_camera())
	_gesture.bind(rig)
	_effects.bind_player(rig, _cutscene.get_camera_anchor(), hud_binding)
	if hud_binding != null and hud_binding.has_method("hud"):
		var hud: CanvasLayer = hud_binding.hud()
		_hud.bind_gameplay_hud(hud)
		_hud_boot.adopt(hud)
	park_at_start()
	_cutscene.bind(self, rig, rig.get_hull_shape(), player_exit, _camera_driver, _hud, _effects)


func park_at_start() -> void:
	if _rig == null:
		return
	_rig.global_transform = player_start.global_transform
	_rig.set_spawn_transform(player_start.global_transform)


func play() -> void:
	if _rig == null:
		push_error(
			"ElevatorIntro.play() before bind_player(); there is nobody to take control from."
		)
		return
	if _cutscene.is_playing():
		return
	park_at_start()
	_cutscene.enter(ElevatorIntroKnobs.ENTER_BLEND_TIME)


func skip() -> void:
	_cutscene.skip()


func is_playing() -> bool:
	return _cutscene.is_playing()


func get_cutscene() -> CutscenePlayer:
	return _cutscene


func get_effects() -> ElevatorIntroEffects:
	return _effects


## Pushed from the prototype's tuning panel, or from the knobs at startup.
func apply_tuning(
	rumble_amplitude: float,
	rumble_frequency: float,
	cutscene_fov: float,
	ceiling_energy: float,
	shaft_speed: float,
	shaft_spacing: float,
	playback_speed: float
) -> void:
	_camera_driver.rumble_amplitude = rumble_amplitude
	_camera_driver.rumble_frequency = rumble_frequency
	_camera_driver.cutscene_fov = cutscene_fov
	# The opening 2D shot crops to whatever the 3D close-up frames, so the fov
	# moves both or the match cut stops matching.
	_hud.set_monitor_framing(ElevatorIntroKnobs.CLOSEUP_DISTANCE, cutscene_fov)
	_car.apply_settings(ceiling_energy, shaft_speed, shaft_spacing)
	_cutscene.set_speed_scale(playback_speed)


func _process(_delta: float) -> void:
	if not _cutscene.is_playing():
		return
	var readout := (
		"%5.2f / %5.2f s   effects %d   hud %s   doors %s"
		% [
			_cutscene.get_clock(),
			_cutscene.get_length(),
			_cutscene.get_fired_count(),
			"on" if _effects.hud_online else "off",
			"shut" if _car.are_doors_solid() else "open"
		]
	)
	_hud.set_readout(readout)
