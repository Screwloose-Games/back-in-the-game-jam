class_name DrillHud
extends CanvasLayer

## Debug overlay: enough readout to tune drill_knobs.gd without guessing, plus
## the control legend.
##
## Holds the suit, the beam and the debris pool directly rather than a reference
## back to the prototype root, so nothing here has to name the root's class - the
## two would otherwise be types pointing at each other.

const CONTROL_LEGEND := """LMB drill  WASD thrust  SPACE/CTRL up-down
Q/E roll  SHIFT sprint  R stabilizers
TAB rebuild the field  ESC free mouse
(the drill is dead while the mouse is free)"""

var _suit: DrillSuit
var _beam: DrillBeam
var _debris: OreDebrisPool
var _node_total := 0
var _collected := 0
var _notice := ""
var _notice_remaining := 0.0

@onready var _readout: Label = $Readout


func _process(delta: float) -> void:
	if _notice_remaining > 0.0:
		_notice_remaining -= delta
		if _notice_remaining <= 0.0:
			_notice = ""
	_readout.text = "\n".join(_build_lines())


## Wires the readout to what it reports on. Called by the prototype root once
## everything it names has been spawned.
func bind(suit: DrillSuit, beam: DrillBeam, debris: OreDebrisPool, node_total: int) -> void:
	_suit = suit
	_beam = beam
	_debris = debris
	_node_total = node_total


## How many crystals are in the bag.
func set_collected(count: int) -> void:
	_collected = count


## A line that says so for a moment, then goes away. Used for the two events the
## readout would otherwise let you miss while looking at the rock.
func show_notice(text: String) -> void:
	_notice = text
	_notice_remaining = DrillKnobs.COLLECT_NOTICE_TIME


func _build_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("crystals  %d / %d" % [_collected, _node_total])
	lines.append(_target_line())
	if _debris != null:
		lines.append("loose rock  %d" % _debris.get_active_count())
	if _suit != null:
		lines.append("%5.2f m/s" % _suit.get_drift_speed())
	if not _notice.is_empty():
		lines.append("")
		lines.append(_notice)
	lines.append("")
	lines.append(CONTROL_LEGEND)
	return lines


## What the crosshair is on. This is the line that has to make the release rule
## legible: "opening" is the widest clear tube out of the crystal so far, in
## metres, so it climbs toward the clearance the crystal needs and the crystal
## comes loose when it gets there.
func _target_line() -> String:
	if _beam == null:
		return "target  -"
	if _beam.is_on_crystal():
		return "target  CRYSTAL - the beam will not cut it"
	var ore_node := _beam.get_target_node()
	if ore_node == null:
		return "target  -" if _beam.is_firing() else "target  (not drilling)"
	return (
		"target  rock %3.0f%%   opening %.2f m"
		% [ore_node.get_rock_fraction() * 100.0, ore_node.get_widest_opening()]
	)
