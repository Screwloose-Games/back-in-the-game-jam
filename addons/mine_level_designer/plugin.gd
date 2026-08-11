@tool
extends EditorPlugin

## Adds the Mine Level dock.
##
## Everything the dock edits is an ordinary node under a MineLevel, so the level
## still opens, loads and plays with this plugin disabled. Turning it off costs
## the buttons, not the data.

const DesignerDock := preload("res://addons/mine_level_designer/designer_dock.gd")
const MineGizmoPlugin := preload("res://addons/mine_level_designer/mine_gizmo_plugin.gd")

var _dock: Control = null
var _gizmos: EditorNode3DGizmoPlugin = null


func _enter_tree() -> void:
	# The gizmos are what make spaces and tunnels selectable in the viewport at
	# all, so they matter more than the dock does.
	_gizmos = MineGizmoPlugin.new()
	_gizmos.bind_undo_redo(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmos)

	_dock = DesignerDock.new()
	_dock.name = "Mine Level"
	_dock.bind_undo_redo(get_undo_redo())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _gizmos != null:
		remove_node_3d_gizmo_plugin(_gizmos)
		_gizmos = null
