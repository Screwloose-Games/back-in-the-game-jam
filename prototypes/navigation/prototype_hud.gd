extends CanvasLayer

## Debug overlay for the navigation prototype: enough readout to tune the
## values in prototype_knobs.gd without guessing, plus the control legend.

const CONTROL_LEGEND := """WASD thrust  SPACE/CTRL up-down
Q/E roll  SHIFT stabilizers
R respawn  ESC free mouse"""

@export var player_path: NodePath

@onready var _readout: Label = $Readout

var _player: ZeroGPlayer
var _rotation_mode_name: String
var _shows_tumble: bool


func _ready() -> void:
	_rotation_mode_name = PrototypeKnobs.RotationMode.keys()[PrototypeKnobs.ROTATION_MODE]
	# DIRECT mode never accumulates angular velocity, so a tumble gauge there
	# would sit at zero forever and read as broken.
	_shows_tumble = PrototypeKnobs.ROTATION_MODE == PrototypeKnobs.RotationMode.INERTIAL

	_player = get_node_or_null(player_path) as ZeroGPlayer
	if _player == null:
		push_warning("Prototype HUD has no player at '%s'; readout disabled." % player_path)
		_readout.text = ""


func _process(_delta: float) -> void:
	if _player == null:
		return

	var readout_lines := PackedStringArray()
	readout_lines.append("%5.2f m/s" % _player.get_drift_speed())
	if _shows_tumble:
		readout_lines.append("tumble %5.2f rad/s" % _player.angular_velocity.length())
	readout_lines.append("stabilizers %s" % ("ON" if _player.stabilizers_engaged else "off"))
	readout_lines.append("rotation %s" % _rotation_mode_name)
	readout_lines.append("")
	readout_lines.append(CONTROL_LEGEND)
	_readout.text = "\n".join(readout_lines)
