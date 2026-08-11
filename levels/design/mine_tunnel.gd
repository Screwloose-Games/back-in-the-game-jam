@tool
class_name MineTunnel
extends Node3D

## One edge of the level graph: a tunnel joining two spaces.
##
## ITS ENDPOINTS ARE NOT STORED. They are read from the two MineSpace nodes it
## names, so the topology and the geometry physically cannot disagree - dragging
## a room drags every tunnel that arrives at it, and there is no second copy of
## the coordinate to forget to update.
##
## LENGTH IS DERIVED AND READ-ONLY for the same reason. Tunnel length is what
## decides whether the creature can hear you, so a hand-typed length that had
## drifted from the geometry would silently corrupt every sound answer the level
## gives. It is shown in the Inspector and on the viewport label, and it is
## computed both times.
##
## Corners are MineBend children rather than a coordinate array, so a bend is
## moved with the ordinary gizmo. Their child order is the order the tunnel runs
## through them.

## The space this tunnel leaves. Set with the dock's Connect Selected rather than
## by typing a path.
@export_node_path("Node3D") var from_space: NodePath:
	set(value):
		from_space = value
		_mark_level_dirty()

## The space this tunnel arrives at.
@export_node_path("Node3D") var to_space: NodePath:
	set(value):
		to_space = value
		_mark_level_dirty()

## Metres across. The number that decides whether the creature fits, compared
## against the level's creature_min_width.
@export_range(0.5, 20.0, 0.1, "or_greater", "suffix:m") var width := 8.0:
	set(value):
		width = maxf(value, 0.0)
		_mark_level_dirty()

@export var tags: Array[StringName] = []:
	set(value):
		tags = value
		_mark_level_dirty()

@export_multiline var notes := "":
	set(value):
		notes = value
		_mark_level_dirty()

## Overrides the level's colour mode. Fully transparent means "no override".
@export var display_color := Color(0, 0, 0, 0):
	set(value):
		display_color = value
		_mark_level_dirty()


func _enter_tree() -> void:
	_mark_level_dirty()


func _exit_tree() -> void:
	_mark_level_dirty()


func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": "length_metres",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
			"hint": PROPERTY_HINT_NONE,
		}
	]


func _get(property: StringName) -> Variant:
	if property == &"length_metres":
		return length()
	return null


func resolve_from() -> MineSpace:
	return get_node_or_null(from_space) as MineSpace


func resolve_to() -> MineSpace:
	return get_node_or_null(to_space) as MineSpace


## The corners this tunnel runs through, in the order it runs through them.
func bend_markers() -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for child: Node in get_children():
		var marker := child as Marker3D
		if marker != null:
			found.append(marker)
	return found


## Centre to centre in GLOBAL space, both endpoints included.
##
## Global rather than local because the two endpoints belong to other nodes and
## the corners belong to this one; converting everything to one frame at the
## point of use is the only version with no ambiguity about whose space a
## coordinate is in.
func build_polyline() -> PackedVector3Array:
	var from_node := resolve_from()
	var to_node := resolve_to()
	if from_node == null or to_node == null:
		return PackedVector3Array()
	# Global transforms only exist inside the tree. A detached hierarchy - which
	# is what a scene being built by a script is - has no answer rather than a
	# wrong one.
	if not (from_node.is_inside_tree() and to_node.is_inside_tree()):
		return PackedVector3Array()

	var points := PackedVector3Array([from_node.global_position])
	for marker: Marker3D in bend_markers():
		points.append(marker.global_position)
	points.append(to_node.global_position)
	return points


func length() -> float:
	var points := build_polyline()
	var total := 0.0
	for index: int in maxi(points.size() - 1, 0):
		total += points[index].distance_to(points[index + 1])
	return total


func has_color_override() -> bool:
	return display_color.a > 0.0


## Empty when this tunnel is wired up correctly, otherwise why it is not.
func describe_problem() -> String:
	if from_space.is_empty() or to_space.is_empty():
		return "no space set on one or both ends"
	var from_node := resolve_from()
	var to_node := resolve_to()
	if from_node == null:
		return "from_space points at nothing (%s)" % from_space
	if to_node == null:
		return "to_space points at nothing (%s)" % to_space
	if from_node == to_node:
		return "both ends are the same space (%s)" % from_node.name
	if length() <= 0.0:
		return "zero length - both ends sit at the same coordinate"
	return ""


## See the note on MineSpace._mark_level_dirty for why this duck-types.
func _mark_level_dirty() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method(&"mark_visuals_dirty"):
			ancestor.call(&"mark_visuals_dirty")
			return
		ancestor = ancestor.get_parent()
