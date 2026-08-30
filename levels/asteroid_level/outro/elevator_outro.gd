class_name ElevatorOutro
extends Node3D

## The asteroid level's ending: the doors shut, the car runs, and the crew goes home.
##
## SELF-CONTAINED, for the same reason the intro is. AnimationPlayer resolves its track
## paths against this root, so the car the shot animates has to live in here rather than
## out in the level. The level hides its own copy and drops this one on top of it at the
## same transform, which works because it is the same prefab either way.
##
## LOADED AT RUNTIME, unlike the intro, which the level scene instances directly. Nothing
## needs it until the quota is met and most runs never reach it, so AsteroidLevel warms it
## through AsyncLoader while the intro is still playing and nothing else wants the disk.

signal finished

## Where the crew stands while the doors shut. Inside the car, and the shot is composed
## around it.
@export var player_start: Node3D

## Where control would be handed back, if there were anything to hand it back to. The run
## ends here, so it is the same spot.
@export var player_exit: Node3D

var _rig: CutscenePlayerRig

@onready var _car: ElevatorCar = $ElevatorCar
@onready var _camera_driver: CutsceneCameraDriver = $CutsceneCamera
@onready var _cutscene: CutscenePlayer = $Cutscenes/ElevatorOutro
@onready var _effects: ElevatorOutroEffects = $Cutscenes/ElevatorOutro/Effects
@onready var _hud: ElevatorOutroHud = $Hud
@onready var _music: AudioStreamPlayer = $Music


func _ready() -> void:
	_effects.bind(_car)
	_effects.bind_audio(_music)
	_cutscene.exit_blend_time = ElevatorOutroKnobs.EXIT_BLEND_TIME
	_cutscene.rig_hull_radius = ElevatorOutroKnobs.RIG_HULL_RADIUS
	_cutscene.finished.connect(finished.emit)
	_camera_driver.cutscene_fov = ElevatorOutroKnobs.CUTSCENE_FOV


## Hands the ending a live player, then parks it in the car ready to start.
func bind_player(rig: CutscenePlayerRig, hud_binding: Node) -> void:
	_rig = rig
	# The ordinary local cull mask, the same one the intro uses -- but here it draws the
	# crew rather than hiding them, because ElevatorOutroEffects puts their meshes on the
	# world layer first. The mask never had to change; what they are drawn on did.
	_camera_driver.cull_mask = PlayerRenderLayers.local_camera_cull_mask()
	_camera_driver.bind(rig.get_head_camera())
	_effects.bind_player(rig)
	if hud_binding != null and hud_binding.has_method("hud"):
		_hud.bind_gameplay_hud(hud_binding.hud())
	_refresh_quota_screen()
	park_at_start()
	_cutscene.bind(self, rig, rig.get_hull_shape(), player_exit, _camera_driver, _hud, _effects)


func park_at_start() -> void:
	if _rig == null:
		return
	_rig.global_transform = player_start.global_transform
	_rig.set_spawn_transform(player_start.global_transform)


func play() -> void:
	if _rig == null:
		push_error("ElevatorOutro.play() before bind_player(); there is nobody to take from.")
		return
	if _cutscene.is_playing():
		return
	park_at_start()
	_cutscene.enter(ElevatorOutroKnobs.ENTER_BLEND_TIME)


func is_playing() -> bool:
	return _cutscene.is_playing()


func get_cutscene() -> CutscenePlayer:
	return _cutscene


func get_effects() -> ElevatorOutroEffects:
	return _effects


func get_car() -> ElevatorCar:
	return _car


## This car is instanced at the end of the run, long after the ledger last moved, so
## its screen has never heard a ledger_changed -- and would come up showing the whole
## quota outstanding, DENIED on the one run where it is certainly APPROVED.
func _refresh_quota_screen() -> void:
	var screen := _car.get_quota_screen()
	if screen != null:
		screen.refresh()
