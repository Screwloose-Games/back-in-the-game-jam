class_name MineralLedger
extends RefCounted

## Counts collected units per MineralType and totals a running score. Each
## unit's value is banked at the moment it is added, not recomputed later, so
## retuning a MineralType's value mid-session cannot move a score already paid
## out -- only what is collected after the change reflects it.

var settings: PlayerSettings = preload("res://prefabs/character/player/player_settings.tres")

var _counts: Dictionary = {}
var _banked: int = 0


func add(type: MineralType, amount: int = 1) -> void:
	_counts[type] = count_for(type) + amount
	var banked := amount * type.value * settings.mining_multiplier
	_banked += banked
	# The crew's running total belongs to the Score autoload. This ledger only says
	# what THIS suit put into it, which is also what makes it testable on its own.
	Score.score += banked


func count_for(type: MineralType) -> int:
	return _counts.get(type, 0)


## What this suit banked. The crew total is Score's, and in co-op they differ.
func total_score() -> int:
	return _banked


## Every type this ledger has seen, for a report that wants to break the score down.
func collected_types() -> Array[MineralType]:
	var types: Array[MineralType] = []
	for type: MineralType in _counts:
		types.append(type)
	return types
