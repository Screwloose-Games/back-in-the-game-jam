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

## A tunnel this space sits part way along, rather than at either end of.
##
## THIS IS HOW A LONG TUNNEL BEHAVES AS A PLACE. A ravine run is one edge that is
## really a corridor of space, and a mouth opening off the middle of it is at a
## point the graph otherwise has no name for: joined by geometry, joined by
## nothing the routing or the sound model can see. Set this and the graph cuts
## the run into pieces at this space, so it becomes a stop along the way instead
## of a wing hanging off the end.
##
## Only the graph is cut. The scene keeps one node per tunnel, and the carved
## geometry is unchanged, because the pieces are slices of the same centreline.
@export_node_path("Node3D") var on_tunnel: NodePath:
	set(value):
		on_tunnel = value
		update_configuration_warnings()
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


## The tunnel this space sits along, or null.
##
## Duck-typed for the same reason _mark_level_dirty is: MineTunnel already refers
## to MineSpace, and naming it back would make the two scripts a resolution cycle.
func resolve_on_tunnel() -> Node3D:
	var node := get_node_or_null(on_tunnel) as Node3D
	if node == null or not node.has_method(&"build_polyline"):
		return null
	return node


## Warns when this space claims to sit on a tunnel it is not actually inside.
##
## Attaching to the wrong run is the easy mistake here, and it fails quietly: the
## graph still connects, just along a route the geometry does not have.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree() or on_tunnel.is_empty():
		return warnings
	var tunnel := resolve_on_tunnel()
	if tunnel == null:
		warnings.append("on_tunnel does not point at a tunnel (%s)." % on_tunnel)
		return warnings

	var polyline: PackedVector3Array = tunnel.call(&"build_polyline")
	if polyline.size() < 2:
		return warnings
	var along := LevelGraph.distance_along_polyline(polyline, global_position)
	var gap := LevelGraph.point_on_polyline(polyline, along).distance_to(global_position)
	var reach: float = maxf(tunnel.get(&"width"), tunnel.call(&"bore_height")) * 0.5
	if gap > reach:
		warnings.append(
			(
				(
					"This space is %.1f m from the centreline of %s, which is only %.1f m "
					+ "across at its widest - so it is outside the tunnel it says it is on."
				)
				% [gap, tunnel.name, reach * 2.0]
			)
		)

	var span := 0.0
	for index: int in maxi(polyline.size() - 1, 0):
		span += polyline[index].distance_to(polyline[index + 1])
	if along <= LevelGraph.MIN_PIECE_LENGTH or along >= span - LevelGraph.MIN_PIECE_LENGTH:
		warnings.append(
			(
				(
					"This space sits %.1f m along %s, effectively at one of its ends. "
					+ "Join that end's space with a tunnel instead."
				)
				% [along, tunnel.name]
			)
		)
	return warnings


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
