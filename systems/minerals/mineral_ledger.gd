class_name MineralLedger
extends RefCounted

## Counts collected units per MineralType and totals a running score. Each
## unit's value is banked at the moment it is added, not recomputed later, so
## retuning a MineralType's value mid-session cannot move a score already paid
## out -- only what is collected after the change reflects it.

var _counts: Dictionary = {}
var _score := 0


func add(type: MineralType, amount: int = 1) -> void:
	_counts[type] = count_for(type) + amount
	_score += amount * type.value


func count_for(type: MineralType) -> int:
	return _counts.get(type, 0)


func total_score() -> int:
	return _score
