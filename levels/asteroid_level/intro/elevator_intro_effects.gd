class_name ElevatorIntroEffects
extends CutsceneEffects

## The one place a timed effect name turns into a change to the world.
##
## THIS IS THE HALF OF THE CUTSCENE THAT A SKIP MUST STILL RUN. Everything you
## can see is a keyframe and can be discarded; everything in here is state, and
## discarding it leaves the level broken. The clearest cases are the two door
## effects: the leaves SLIDING is animation, the colliders coming off and going
## back on is state, and dropping either one leaves the player sealed inside a
## box whose doors are visibly open, or floating through a visibly shut one.
##
## Every branch is a plain assignment or an idempotent call, so running the list
## twice cannot double-anything - the spec's "idempotent or guarded" requirement
## satisfied without a single guard.

## Seconds to fade the VO out when a skip cuts it off. A hard stop on a vowel is
## audibly a bug; the spec asks for about a tenth of a second.
const VO_FADE_OUT := 0.1

## True once the gameplay HUD is live rather than a tube still striking.
var hud_online := false

## True once the HUD has been handed back out of the boot overlay.
var hud_settled := false

## True once the door colliders are off and the player can leave.
var doors_unlocked := false

## True once they are back on and the car is shut again.
var doors_locked := false

## True once the refusal has played. The beat the whole intro exists to deliver.
var access_denied := false

## The flag that says gameplay has started, dispatched off the authoritative clock.
var workday_begun := false

var _car: ElevatorCar
var _camera_driver: CutsceneCameraDriver
var _hud: ElevatorIntroHud
var _rig: CutscenePlayerRig
var _camera_anchor: Node3D
var _hud_boot: HudBootCrt
var _hud_host: Node
var _vo: AudioStreamPlayer
var _vo_volume := 0.0
var _miners: Array[MinerRig] = []
var _rig_follows_anchor := false


func bind(
	car: ElevatorCar,
	camera_driver: CutsceneCameraDriver,
	hud: ElevatorIntroHud,
	miners: Array[MinerRig]
) -> void:
	_car = car
	_camera_driver = camera_driver
	_hud = hud
	_miners = miners


## The player-side half, which only exists once a level has spawned one.
func bind_player(rig: CutscenePlayerRig, camera_anchor: Node3D, hud_host: Node) -> void:
	_rig = rig
	_camera_anchor = camera_anchor
	_hud_host = hud_host


func bind_audio(vo: AudioStreamPlayer) -> void:
	_vo = vo
	_vo_volume = vo.volume_db


func bind_hud_boot(hud_boot: HudBootCrt) -> void:
	_hud_boot = hud_boot


func reset() -> void:
	hud_online = false
	hud_settled = false
	doors_unlocked = false
	doors_locked = false
	access_denied = false
	workday_begun = false
	_rig_follows_anchor = false
	_car.set_shaft_running(false)
	_car.set_doors_solid(true)
	_camera_driver.set_rumble_gain(0.0)
	_stop_vo()
	if _rig != null:
		_rig.set_gesture_blend(0.0)
		_rig.set_tool_visible(false)
	for miner: MinerRig in _miners:
		miner.set_visor_lit(false)


## Carries the player's body along with the shot once the camera is in their head.
##
## DERIVED EVERY FRAME, NEVER STORED. The press is rendered from the player's own
## rig, so by PRESS_START the body has to actually be outside the car - and a
## keyframed rig would be a second mixer writing a CharacterBody3D the solver is
## also touching. Reading the anchor instead means the drift, the turn and the
## pan move the body for free, and CLEANUP still snaps to PlayerExit.
func advance(_delta: float) -> void:
	if not _rig_follows_anchor or _rig == null or _camera_anchor == null:
		return
	_rig.global_transform = _camera_anchor.global_transform


func settle_terminal_state() -> void:
	_hud.clear_title()
	_release_hud_boot()
	if _rig != null:
		_rig.set_gesture_blend(0.0)
		_rig.set_tool_visible(true)
	# Not stopped. The refusal runs about four seconds and the clip ends on it by
	# design; cutting it at CLEANUP would clip the line on a normal playthrough.
	# skip() gets the fade instead, through reset() on the next enter().


func apply(effect_name: StringName, detail: float) -> void:
	match effect_name:
		&"car_descending":
			# A MODE, NOT A VALUE ON THE TIMELINE. There is no "end of the
			# descent" keyframe to interpolate toward, and a keyframed shake
			# would be left at whatever the final key said after a skip.
			_car.set_shaft_running(true)
			_camera_driver.set_rumble_gain(1.0)
		&"hud_online":
			# The match cut. Three things become true at once: the HUD is the
			# player's rather than the cutscene's, the body starts riding the
			# shot, and the suit is drawn again so its arms can be in frame.
			hud_online = true
			_rig_follows_anchor = true
			if _rig != null:
				_rig.set_avatar_hidden(false)
				# The cutter would swing through every remaining shot.
				_rig.set_tool_visible(false)
		&"hud_settled":
			hud_settled = true
			_release_hud_boot()
		&"car_stopped":
			_car.set_shaft_running(false)
			_camera_driver.set_rumble_gain(0.0)
		&"doors_unlocked":
			# THE ONE THAT WOULD SOFT-LOCK THE LEVEL. See the class docstring.
			_car.set_doors_solid(false)
			doors_unlocked = true
		&"doors_locked":
			# And its mirror, which would let the player swim back into a car
			# whose doors the shot just shut in their face.
			_car.set_doors_solid(true)
			doors_locked = true
		&"access_denied":
			access_denied = true
			_play_vo()
		&"workday_begun":
			workday_begun = true
		_:
			push_error(
				(
					"elevator_intro_effects: no branch for '%s' (detail %.2f); the effects .tres names an effect this script does not implement."
					% [effect_name, detail]
				)
			)


func is_rig_following_anchor() -> bool:
	return _rig_follows_anchor


## Idempotent so a replay, or a dispatch window that fires it twice, cannot leave
## the HUD orphaned inside a freed SubViewport.
func _release_hud_boot() -> void:
	if _hud_boot == null or not is_instance_valid(_hud_boot):
		_hud_boot = null
		return
	var hud := _hud_boot.release(_hud_host)
	_hud_boot = null
	if hud != null:
		hud.visible = true


func _play_vo() -> void:
	if _vo == null or _vo.stream == null:
		return
	_vo.volume_db = _vo_volume
	_vo.play()


func _stop_vo() -> void:
	if _vo == null or not _vo.playing:
		return
	var fade := create_tween()
	fade.tween_property(_vo, "volume_db", -60.0, VO_FADE_OUT)
	fade.tween_callback(_vo.stop)
