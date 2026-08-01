extends CanvasLayer

## Debug overlay for the object carrying prototype: enough readout to tune the
## values in carry_knobs.gd without guessing, plus the control legend.
##
## The crosshair doubles as the grip indicator. In fog this dark the object is
## often only a suggestion of an edge, so its colour is the one reliable answer
## to "am I actually on it".

const CONTROL_LEGEND := """WASD thrust  SPACE/CTRL up-down
Q/E roll  SHIFT stabilizers
F grab-release  T carry mode (drops load)
R respawn  ESC free mouse"""

## Nothing within reach.
const CROSSHAIR_IDLE_COLOR := Color(0.78, 0.88, 1, 0.55)
## Something grabbable under the crosshair.
const CROSSHAIR_READY_COLOR := Color(1, 0.78, 0.42, 0.85)
## Currently holding on.
const CROSSHAIR_HELD_COLOR := Color(0.55, 1, 0.7, 0.9)

@export var player_path: NodePath

@onready var _readout: Label = $Readout
@onready var _crosshair: ColorRect = $Crosshair

var _player: CarrierPlayer
var _rotation_mode_name: String


func _ready() -> void:
	_rotation_mode_name = CarryKnobs.RotationMode.keys()[CarryKnobs.ROTATION_MODE]

	_player = get_node_or_null(player_path) as CarrierPlayer
	if _player == null:
		push_warning("Carry HUD has no player at '%s'; readout disabled." % player_path)
		_readout.text = ""


func _process(_delta: float) -> void:
	if _player == null:
		return

	var readout_lines := PackedStringArray()
	readout_lines.append("%5.2f m/s" % _player.get_drift_speed())
	readout_lines.append("tumble %5.2f rad/s" % _player.angular_velocity.length())
	readout_lines.append("stabilizers %s" % ("ON" if _player.stabilizers_engaged else "off"))
	readout_lines.append("rotation %s" % _rotation_mode_name)
	readout_lines.append(_describe_carry_link())
	readout_lines.append("")
	readout_lines.append(CONTROL_LEGEND)
	_readout.text = "\n".join(readout_lines)

	_crosshair.color = _pick_crosshair_color()


## Strain is shown against the distance the active mode gives out at, so a
## number closing on its limit is a warning that the load is about to be lost.
## A tether also reports its raw length, because whether it has gone taut at
## all is the thing you are watching for.
func _describe_carry_link() -> String:
	var mode_key: String = CarryKnobs.CarryMode.keys()[_player.get_carry_mode()]
	var mode_name := mode_key.to_lower()
	var held_object := _player.get_held_object()
	if held_object == null:
		return "%s %s" % [mode_name, "READY" if _player.get_targeted_object() != null else "empty"]

	if _player.get_carry_mode() == CarryKnobs.CarryMode.TETHER:
		return (
			"%s HELD %.0f kg  %4.2f / %4.2f m  taut %4.2f / %4.2f"
			% [
				mode_name,
				held_object.mass,
				_player.get_link_distance(),
				CarryKnobs.TETHER_LENGTH,
				_player.get_link_strain(),
				_player.get_link_break_distance(),
			]
		)
	return (
		"%s HELD %.0f kg  strain %4.2f / %4.2f m"
		% [
			mode_name,
			held_object.mass,
			_player.get_link_strain(),
			_player.get_link_break_distance(),
		]
	)


func _pick_crosshair_color() -> Color:
	if _player.get_held_object() != null:
		return CROSSHAIR_HELD_COLOR
	if _player.get_targeted_object() != null:
		return CROSSHAIR_READY_COLOR
	return CROSSHAIR_IDLE_COLOR
