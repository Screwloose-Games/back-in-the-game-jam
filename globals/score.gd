extends Node

signal score_changed(score: int)

@export var quota_target := 2000

var score: int = 0:
	set(value):
		score = value
		score_changed.emit(score)


func _ready() -> void:
	var scene := get_tree().current_scene

	if scene != null and not scene.tree_exiting.is_connected(reset):
		scene.tree_exiting.connect(reset)


func reset():
	score = 0


func is_quota_met() -> bool:
	return credits_outstanding(quota_target, score) <= 0


## Credits still owed, floored at zero. static func credits_outstanding(target: int, collected: int, per_point: float) -> int: return maxi(target - int(round(float(collected) * per_point)), 0)
func credits_outstanding(target: int, collected: int, per_point: float = 1.0) -> int:
	return maxi(target - int(round(float(collected) * per_point)), 0)
