extends CanvasLayer

## Debug overlay for the object carrying prototype: enough readout to tune the
## values in carry_knobs.gd without guessing, plus the control legend.
##
## The crosshair doubles as the grip indicator. In fog this dark the object is
## often only a suggestion of an edge, so its colour is the one reliable answer
## to "am I actually on it".

const CONTROL_LEGEND := """WASD thrust  SPACE/CTRL up-down
Q/E roll  SHIFT stabilizers
F grab-release  T clip-unclip tether
R respawn  ESC free mouse"""

## Nothing within reach.
const CROSSHAIR_IDLE_COLOR := Color(0.78, 0.88, 1, 0.55)
## Something grabbable under the crosshair.
const CROSSHAIR_READY_COLOR := Color(1, 0.78, 0.42, 0.85)
## Currently holding on.
const CROSSHAIR_HELD_COLOR := Color(0.55, 1, 0.7, 0.9)

@export var player_path: NodePath

var _player: CarrierPlayer
var _rotation_mode_name: String

@onready var _readout: Label = $Readout
@onready var _crosshair: ColorRect = $Crosshair


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
	readout_lines.append(_describe_grip())
	readout_lines.append(_describe_tether())
	readout_lines.append("")
	readout_lines.append(CONTROL_LEGEND)
	_readout.text = "\n".join(readout_lines)

	_crosshair.color = _pick_crosshair_color()


## The mass shown is the module's live mass, which is the point: it drops when
## the hands take hold and goes back up when they let go, and that swap is what
## decides whether the module is something you haul or something you are moored
## to. Strain is shown against the distance the grip gives out at, so a number
## closing on its limit is a warning that the module is about to be lost.
func _describe_grip() -> String:
	var held_object := _player.get_held_object()
	if held_object == null:
		return "grip %s" % ("READY" if _player.get_targeted_object() != null else "empty")
	return (
		"grip HELD %.0f kg  strain %4.2f / %4.2f m"
		% [held_object.mass, _player.get_grip_strain(), _player.settings.grip_break_distance]
	)


## Whether the rope has gone taut, and how much of it is going the long way
## round, are the two things you are watching for, so the tether reports the
## length of its whole shape and how much longer that is than the straight line
## between its ends.
func _describe_tether() -> String:
	var tethered_object := _player.get_tethered_object()
	if tethered_object == null:
		return "tether %s" % ("READY" if _player.get_targeted_object() != null else "unclipped")
	return (
		"tether CLIPPED %.0f kg  %4.2f / %4.2f m  taut %4.2f / %4.2f  drape %4.2f"
		% [
			tethered_object.mass,
			_player.get_tether_distance(),
			_player.settings.tether_length,
			_player.get_tether_strain(),
			_player.settings.tether_break_stretch,
			_player.get_tether_drape(),
		]
	)


func _pick_crosshair_color() -> Color:
	if _player.get_held_object() != null:
		return CROSSHAIR_HELD_COLOR
	if _player.get_targeted_object() != null:
		return CROSSHAIR_READY_COLOR
	return CROSSHAIR_IDLE_COLOR
