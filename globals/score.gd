extends Node

## The run's ledger, and the single source of truth for everything that displays it.
##
## The quota terminal, the exit door and the extraction report all read from here rather
## than keeping a copy. A screen with its own quota is a screen that can disagree with the
## door beside it, and that disagreement stays invisible until a playtest ends with
## somebody stuck in the airlock.

## What the crew has banked so far.
signal score_changed(score: int)

## What they have to bank. The elevator car pushes its own figure in when it configures
## itself, so anything already showing a number has to be told.
signal quota_changed(quota_target: int)

## Either half of the sum moved. What a readout wants, because it repaints for both.
signal ledger_changed

@export var quota_target: int = 2000:
	set(value):
		if value == quota_target:
			return
		quota_target = value
		quota_changed.emit(quota_target)
		ledger_changed.emit()

var score: int = 0:
	set(value):
		if value == score:
			return
		score = value
		score_changed.emit(score)
		ledger_changed.emit()


func _ready() -> void:
	var scene := get_tree().current_scene
	if scene != null and not scene.tree_exiting.is_connected(reset):
		scene.tree_exiting.connect(reset)


func reset() -> void:
	score = 0


## Credits still owed, floored at zero. This is the number on the glass.
func credits_outstanding() -> int:
	return maxi(quota_target - score, 0)


func is_quota_met() -> bool:
	return credits_outstanding() <= 0
