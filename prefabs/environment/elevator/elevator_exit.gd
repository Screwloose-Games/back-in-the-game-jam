class_name ElevatorExit
extends Node

## The way out. The doorway and the call panel ask the same question -- has the quota been
## met -- because a player standing at the door should not have to work out which of the
## two is the one that listens.

## The quota is met and the crew is leaving. The level owns what happens next.
signal departure_approved

## The quota is not met. Carries what is still owed, for anything that wants to say so.
signal departure_refused(credits_short: int)

@onready var refusal_vo: AudioStreamPlayer3D = $RefusalVo

@onready var _car: ElevatorCar = get_parent() as ElevatorCar


func _ready() -> void:
	if _car == null:
		push_error("ElevatorExit must be a child of an ElevatorCar; it reads the quota off it.")
		return
	# Found rather than wired. Every Interactable on this car is a way of asking to leave,
	# so the prefab keeps working dropped into a level with nothing connected to it --
	# which is the contract every prefab in this project keeps.
	for interactable: Interactable in _car.find_children("*", "Interactable", true, false):
		interactable.interacted.connect(_on_asked_to_leave.unbind(1))


func _on_asked_to_leave() -> void:
	var screen := _car.get_quota_screen()
	if Score.is_quota_met():
		departure_approved.emit()
		GlobalSignalBus.level_exit_requested.emit()
		return
	_refuse(screen)


## The screen has been reading DENIED in red since the run started; what pressing the
## button adds is a voice saying so, which is the difference between a locked door and a
## door that answered you.
func _refuse(screen: ElevatorScreen) -> void:
	if refusal_vo != null and not refusal_vo.playing:
		refusal_vo.play()
	departure_refused.emit(screen.credits_short() if screen != null else 0)
