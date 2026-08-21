class_name PlayerMineralCollector
extends Node

## Listens for the mining tool's mineral_collected event and keeps this
## player's running score, publishing it to the HUD.

var ledger := MineralLedger.new()

@onready var _mining_tool: PlayerMiningTool = %MiningTool
@onready var _hud_state: HudState = %HudState


func _ready() -> void:
	_mining_tool.mineral_collected.connect(_on_mineral_collected)


func _on_mineral_collected(type: MineralType) -> void:
	ledger.add(type)
	_hud_state.mineral_score = ledger.total_score()
