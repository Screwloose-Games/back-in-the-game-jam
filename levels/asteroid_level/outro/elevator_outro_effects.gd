class_name ElevatorOutroEffects
extends CutsceneEffects

## What the departure changes about the world, as opposed to what it shows. The leaves
## sliding shut is presentation and lives in the animation; the leaves becoming solid is
## state and lives here, because a skip discards one and must not discard the other.

## Read by the verifier, which checks each one has actually happened by the end.
var crew_aboard := false
var doors_locked := false
var car_ascending := false

var _car: ElevatorCar
var _music: AudioStreamPlayer
var _rig: CutscenePlayerRig


func bind(car: ElevatorCar) -> void:
	_car = car


func bind_player(rig: CutscenePlayerRig) -> void:
	_rig = rig


func bind_audio(music: AudioStreamPlayer) -> void:
	_music = music


func reset() -> void:
	crew_aboard = false
	doors_locked = false
	car_ascending = false
	if _car != null:
		_car.set_shaft_running(false)
		# Open at t=0. The crew has just come aboard, and the shot starts on the way in.
		_car.set_doors_solid(false)
	if _music != null:
		_music.stop()


func apply(effect_name: StringName, detail: float) -> void:
	match effect_name:
		&"crew_aboard":
			_show_crew()
		&"doors_locked":
			_car.set_doors_solid(true)
			doors_locked = true
		&"car_ascending":
			_car.set_shaft_running(true)
			car_ascending = true
			if _music != null:
				_music.play()
		_:
			super.apply(effect_name, detail)


## The one thing this shot is of.
##
## CutscenePlayer.enter() hides the avatar, because nearly every shot is composed AROUND
## the player rather than of them. This is the exception, so it is undone on the first
## frame -- and undone as an effect rather than in bind_player, so a skip still runs it.
func _show_crew() -> void:
	crew_aboard = true
	if _rig == null:
		return
	_rig.set_avatar_fully_visible()
	# The lamp goes back on for the opposite reason the intro puts it out: there, it was a
	# moving pool of light with no visible source. Here the source is standing in frame.
	_rig.set_lamp_enabled(true)
	_rig.set_tool_visible(false)
