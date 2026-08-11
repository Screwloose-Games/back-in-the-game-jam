@tool
class_name MineBend
extends Marker3D

## A corner partway along a tunnel.
##
## Deliberately NOT a graph node. A bend is somewhere the tunnel changes
## direction; a junction is somewhere a decision gets made. Modelling the first
## as the second would fill the graph with degree-two nodes that no route choice
## ever turns on, and would make every path length calculation walk them.
##
## It exists as a node rather than as an entry in an array on the tunnel so that
## moving a corner is an ordinary gizmo drag. Child order along the tunnel is
## the order they are traversed, so reordering in the Scene dock reroutes it.


func _enter_tree() -> void:
	set_notify_transform(true)
	_mark_level_dirty()


func _exit_tree() -> void:
	_mark_level_dirty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_mark_level_dirty()


## See the note on MineSpace._mark_level_dirty for why this walks up and
## duck-types rather than naming MineLevel.
func _mark_level_dirty() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method(&"mark_visuals_dirty"):
			ancestor.call(&"mark_visuals_dirty")
			return
		ancestor = ancestor.get_parent()
