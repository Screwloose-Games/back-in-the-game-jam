@tool
class_name MineSpace
extends Node3D

## One node of the level graph: a room, a tunnel junction, or a dead-end pocket.
##
## Rooms and junctions are the same thing structurally, so they are one script
## told apart by `kind` rather than two scripts. Which one a given space IS gets
## argued about repeatedly while a level is being designed, and changing a
## dropdown is cheaper than swapping a node's script and losing its annotations
## on the way through.
##
## A JUNCTION WITH radius 0 IS A BARE CORNER: tunnels meeting with no chamber cut
## at the meeting point. That is the case the graph has to carry and geometry
## alone cannot - somewhere that is a decision point without being a place.
##
## Position is the node's own transform, so a space is placed with the ordinary
## 3D gizmo and typed exactly in the Inspector when the coordinate matters.

## What this space is. Only affects how it reads and how it is drawn; the graph
## treats all three the same when routing.
@export var kind: LevelGraph.SpaceKind = LevelGraph.SpaceKind.ROOM:
	set(value):
		kind = value
		_mark_level_dirty()

## Horizontal radius, metres. Zero draws a marker dot and means there is no
## chamber here at all.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m") var radius := 5.0:
	set(value):
		radius = maxf(value, 0.0)
		_mark_level_dirty()

## Vertical radius as a fraction of `radius`, making the chamber an oblate
## spheroid. 1.0 is a sphere - a chamber cut by something that did not care which
## way was up.
##
## BELOW 1.0 IS WHAT LETS A CHAMBER BE WIDE AND FLAT AT THE SAME TIME. A sphere
## big enough to read as a room in a hive stratum domes through the roof and floor
## either side of it, which is why the hive's cells used to be capped at a radius
## far below the size the space wanted to be. Radius still decides how far across
## a chamber is and is still what the gizmo handle drags; this is shape only.
@export_range(0.1, 2.0, 0.05, "or_greater") var vertical_scale := 1.0:
	set(value):
		vertical_scale = maxf(value, 0.01)
		_mark_level_dirty()

## Free-form labels used for colour coding and for filtering. Nothing validates
## these - the whole point is that a designer can invent one mid-thought.
@export var tags: Array[StringName] = []:
	set(value):
		tags = value
		_mark_level_dirty()

@export_multiline var notes := "":
	set(value):
		notes = value
		_mark_level_dirty()

## Overrides whatever the level's colour mode would have picked. FULLY
## TRANSPARENT MEANS "no override" - the level chooses.
@export var display_color := Color(0, 0, 0, 0):
	set(value):
		display_color = value
		_mark_level_dirty()


func _enter_tree() -> void:
	set_notify_transform(true)
	_mark_level_dirty()


func _exit_tree() -> void:
	_mark_level_dirty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_mark_level_dirty()


## Whether a caller has set an explicit colour on this space.
func has_color_override() -> bool:
	return display_color.a > 0.0


## Asks the enclosing level to redraw.
##
## Found by walking up and duck-typing rather than by naming MineLevel, because
## MineLevel already refers to this class and a mutual reference between two
## class_name scripts is a resolution cycle Godot will not always untangle.
func _mark_level_dirty() -> void:
	if is_inside_tree():
		# Redraws the editor gizmo, which is both how this is seen and how it is
		# clickable at all.
		update_gizmos()
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method(&"mark_visuals_dirty"):
			ancestor.call(&"mark_visuals_dirty")
			return
		ancestor = ancestor.get_parent()
