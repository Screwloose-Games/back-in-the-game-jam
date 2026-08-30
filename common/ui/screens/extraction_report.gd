class_name ExtractionReport
extends Control

## What the run was worth, shown once the car has gone. Reached only from the ending, and
## it hands off to the credits.

## Handed over before the scene change, because a scene swap is the one moment where there
## is no tree to pass anything through. Static rather than an autoload: exactly one screen
## reads these, and an autoload would only be a second place to look for them.
static var recovered_credits := 0
static var quota_credits := 0
static var breakdown: Array[Dictionary] = []

@onready var _rows: VBoxContainer = %Rows
@onready var _recovered: Label = %Recovered
@onready var _quota: Label = %Quota
@onready var _balance: Label = %Balance
@onready var _continue: Button = %Continue


## Fills in what the report will show. Called by the level before it changes scene.
static func prepare(ledger: MineralLedger, quota: int) -> void:
	recovered_credits = ledger.total_score()
	quota_credits = quota
	breakdown = []
	for type: MineralType in ledger.collected_types():
		var label := type.display_name if not type.display_name.is_empty() else String(type.id)
		breakdown.append({"name": label, "count": ledger.count_for(type)})


func _ready() -> void:
	_recovered.text = "RECOVERED  %d CR" % recovered_credits
	_quota.text = "QUOTA      %d CR" % quota_credits
	var surplus := recovered_credits - quota_credits
	_balance.text = ("SURPLUS    %d CR" % surplus) if surplus >= 0 else ("SHORT %d CR" % -surplus)
	_build_breakdown()
	_continue.pressed.connect(_on_continue_pressed)
	_continue.grab_focus()


## Built rather than authored, because how many kinds of ore a run turned up is not
## something the scene can know.
func _build_breakdown() -> void:
	for entry: Dictionary in breakdown:
		var row := Label.new()
		row.text = "  %s x%d" % [entry["name"], entry["count"]]
		_rows.add_child(row)
		_rows.move_child(row, _rows.get_child_count() - 2)


func _on_continue_pressed() -> void:
	SceneTransitionManager.change_scene_with_transition(
		SceneManager.credits, SceneManager.fade_transition
	)
