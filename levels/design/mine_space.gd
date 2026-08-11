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

## Metres. Zero draws a marker dot and means there is no chamber here at all.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m") var radius := 5.0:
	set(value):
		radius = maxf(value, 0.0)
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
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method(&"mark_visuals_dirty"):
			ancestor.call(&"mark_visuals_dirty")
			return
		ancestor = ancestor.get_parent()
