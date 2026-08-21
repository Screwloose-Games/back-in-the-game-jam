class_name ElevatorEffects
extends Node

## The one place a timed effect name turns into a change to the world.
##
## THIS IS THE HALF OF THE CUTSCENE THAT A SKIP MUST STILL RUN. Everything you can
## see is a keyframe and can be discarded; everything in here is state, and
## discarding it leaves the level broken. The clearest case is doors_unlocked: the
## doors SLIDING is animation, the colliders coming off is state, and dropping it
## on skip seals the player inside a box whose doors are visibly open.
##
## Every branch is a plain assignment, so every effect is idempotent by
## construction and running the list twice cannot double-anything. That is the
## spec's "idempotent or guarded" requirement satisfied without a single guard,
## and it is worth keeping true as effects are added.
##
## No state of its own beyond the three flags, which exist to be read back - by
## the debug readout, by CLEANUP, and by the verifier comparing a skip against a
## playthrough.

## True once the helmet HUD is the live gameplay overlay rather than a fade in
## progress.
var hud_online := false

## True once the door colliders are off and the player can leave.
var doors_unlocked := false

## The flag the whole cutscene exists to set. Build-order step 3's Flag_Set,
## dispatched off the authoritative clock.
var workday_begun := false

var _car: ElevatorCar
var _camera_driver: CutsceneCameraDriver
var _hud: ElevatorCutsceneHud
var _miners: Array[MinerRig] = []


func bind(
	car: ElevatorCar,
	camera_driver: CutsceneCameraDriver,
	hud: ElevatorCutsceneHud,
	miners: Array[MinerRig]
) -> void:
	_car = car
	_camera_driver = camera_driver
	_hud = hud
	_miners = miners


## Back to the state the world is in before the cutscene runs.
##
## Called from enter(), so replaying is a real replay rather than a second run on
## top of the first one's leftovers.
func reset() -> void:
	hud_online = false
	doors_unlocked = false
	workday_begun = false
	_car.set_shaft_running(false)
	_car.set_doors_solid(true)
	_camera_driver.set_rumble_gain(0.0)
	_hud.set_helmet_online(false)
	for miner: MinerRig in _miners:
		miner.set_visor_lit(false)


func apply(effect_name: StringName, detail: float) -> void:
	match effect_name:
		&"car_descending":
			# A MODE, NOT A VALUE ON THE TIMELINE. There is no "end of the
			# descent" keyframe to interpolate toward, and a keyframed shake
			# would be left at whatever the final key said after a skip cut to
			# the last frame. State belongs here; the shake reads it.
			_car.set_shaft_running(true)
			_camera_driver.set_rumble_gain(1.0)
		&"hud_online":
			# The FADE is the animation. The fact that the overlay is now the
			# live gameplay HUD is state, and CLEANUP reads it to decide what to
			# leave on screen.
			hud_online = true
		&"car_stopped":
			_car.set_shaft_running(false)
			_camera_driver.set_rumble_gain(0.0)
		&"doors_unlocked":
			# THE ONE THAT WOULD SOFT-LOCK THE LEVEL. See the class docstring.
			_car.set_doors_solid(false)
			doors_unlocked = true
		&"workday_begun":
			workday_begun = true
		_:
			push_error(
				(
					"elevator_effects: no branch for '%s' (detail %.2f); the effects .tres names an effect this script does not implement."
					% [effect_name, detail]
				)
			)
