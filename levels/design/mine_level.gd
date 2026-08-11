@tool
class_name MineLevel
extends Node3D

## The root of a mine blockout: every MineSpace and MineTunnel under it, drawn as
## a readable diagram and convertible to a plain LevelGraph.
##
## THE SCENE TREE IS THE GRAPH. Spaces and tunnels are ordinary Node3Ds, so
## placement, precise coordinates, naming, multi-select, undo and copy-paste are
## all Godot's rather than a bespoke editor's. This script only supplies what the
## engine does not: how the thing looks, what the numbers add up to, and whether
## it is wired up correctly.
##
## NOTHING DRAWN HERE IS SAVED. Every visual is a child of one container added
## without an owner, so it never reaches the .tscn. The file on disk holds the
## design - positions, radii, widths, tags and notes - and the picture is rebuilt
## from it. Deleting the container loses nothing.
##
## WIDTH THRESHOLDS ARE LEVEL-WIDE, NOT PER TUNNEL. The creature's real size is
## not settled, so `creature_min_width` is one number that recolours the whole
## map. When the creature turns out to be wider than expected, the level does not
## need re-authoring to find out what that broke.

enum ColorMode {
	UNIFORM,  ## One colour. For reading shape alone.
	TAG,  ## By the space or tunnel's first tag.
	WIDTH,  ## Narrow to wide.
	DEPTH,  ## Shallow to deep.
	CREATURE_PASSABLE,  ## Whether the creature fits, against creature_min_width.
	SOUND,  ## What can hear a noise made at sound_origin.
}

## How big a radius-0 junction draws. It has no chamber, but something has to be
## clickable at the coordinate.
const MARKER_RADIUS := 1.0

const SPHERE_SEGMENTS := 12
const SPHERE_RINGS := 6
const TUBE_SIDES := 8

## Width in metres that the WIDTH colour ramp treats as its two ends.
const NARROWEST_DRAWN := 2.0
const WIDEST_DRAWN := 12.0

const COLOR_UNIFORM_SPACE := Color(0.55, 0.75, 1.0)
const COLOR_UNIFORM_TUNNEL := Color(0.45, 0.62, 0.85)
const COLOR_NARROW := Color(1.0, 0.35, 0.25)
const COLOR_WIDE := Color(0.25, 0.6, 1.0)
const COLOR_SHALLOW := Color(0.4, 0.9, 0.7)
const COLOR_DEEP := Color(0.85, 0.2, 0.55)
const COLOR_PASSABLE := Color(0.95, 0.35, 0.3)
const COLOR_REFUGE := Color(0.3, 0.9, 0.5)
const COLOR_SILENT := Color(0.18, 0.2, 0.24)
const COLOR_HEARD_FAINT := Color(0.5, 0.1, 0.1)
const COLOR_HEARD_LOUD := Color(1.0, 0.95, 0.6)

## Hue step between tags with no configured colour. The golden ratio conjugate,
## so a dozen invented tags stay distinguishable instead of cycling.
const TAG_HUE_STEP := 0.618034

@export var color_mode: ColorMode = ColorMode.WIDTH:
	set(value):
		color_mode = value
		mark_visuals_dirty()

## Metres. The narrowest tunnel the creature can get down. Seeded from twice the
## chase prototype's probe comfort; expected to move once the real creature exists.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var creature_min_width := 6.4:
	set(value):
		creature_min_width = maxf(value, 0.0)
		mark_visuals_dirty()

## Colours for named tags. A tag with no entry gets a stable colour from its own
## name, so colour coding works before anyone configures anything.
@export var tag_colors: Dictionary[StringName, Color] = {}:
	set(value):
		tag_colors = value
		mark_visuals_dirty()

@export var show_labels := true:
	set(value):
		show_labels = value
		mark_visuals_dirty()

@export_range(0.002, 0.06, 0.001) var label_pixel_size := 0.014:
	set(value):
		label_pixel_size = value
		mark_visuals_dirty()

@export_range(0.0, 1.0, 0.01) var space_alpha := 0.18:
	set(value):
		space_alpha = value
		mark_visuals_dirty()

@export_range(0.0, 1.0, 0.01) var tunnel_alpha := 0.30:
	set(value):
		tunnel_alpha = value
		mark_visuals_dirty()

## Where the level is entered from. Used as the root for the connectivity check
## and as depth zero. Falls back to the first space when unset.
@export_node_path("Node3D") var entrance_space: NodePath:
	set(value):
		entrance_space = value
		mark_visuals_dirty()

## Which space or tunnel the previewed noise is made in.
@export_node_path("Node3D") var sound_origin: NodePath:
	set(value):
		sound_origin = value
		mark_visuals_dirty()

## Where along the tunnel the noise is made, when sound_origin is a tunnel.
@export_range(0.0, 1.0, 0.01) var sound_origin_fraction := 0.5:
	set(value):
		sound_origin_fraction = value
		mark_visuals_dirty()

## Metres. How far the noise carries - the same unit the noise system uses, where
## a source is defined by the radius at which it can still be heard.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var sound_loudness := 60.0:
	set(value):
		sound_loudness = maxf(value, 0.0)
		mark_visuals_dirty()

## Whether the diagram draws while the project is running, not just in the editor.
##
## Off, because this is a design document that happens to be a scene. Code that
## instantiates a level at runtime almost always wants build_graph(), and would
## not thank it for painting transparent tubes and floating labels over the game.
@export var draw_when_running := false:
	set(value):
		draw_when_running = value
		mark_visuals_dirty()

var _visuals: Node3D = null
var _graph: LevelGraph = null
var _sound_field: LevelGraph.SoundField = null
var _material_cache: Dictionary = {}
var _shallowest := 0.0
var _deepest := 0.0
var _dirty := true


func _ready() -> void:
	mark_visuals_dirty()


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	_recompute()
	if Engine.is_editor_hint() or draw_when_running:
		_draw_everything()


## Queues a redraw. Cheap and idempotent, so every setter and every moved node
## can call it without anyone counting how many times per frame that happens.
func mark_visuals_dirty() -> void:
	_dirty = true


## Every MineSpace under this level, in tree order.
func spaces_in_level() -> Array[MineSpace]:
	var found: Array[MineSpace] = []
	for node: Node in _walk_authored_children(self):
		var space := node as MineSpace
		if space != null:
			found.append(space)
	return found


## Every MineTunnel under this level, in tree order.
func tunnels_in_level() -> Array[MineTunnel]:
	var found: Array[MineTunnel] = []
	for node: Node in _walk_authored_children(self):
		var tunnel := node as MineTunnel
		if tunnel != null:
			found.append(tunnel)
	return found


## The scene converted to the plain graph the AI and noise systems consume.
##
## Tunnels that are not wired up are left out rather than added broken, so a
## half-connected level still answers questions about the part that is finished.
func build_graph() -> LevelGraph:
	var graph := LevelGraph.new()
	for space: MineSpace in spaces_in_level():
		var record := LevelGraph.Space.new()
		record.id = space.name
		record.kind = space.kind
		record.position = space.global_position
		record.radius = space.radius
		record.tags = space.tags
		record.notes = space.notes
		graph.add_space(record)

	for tunnel: MineTunnel in tunnels_in_level():
		if not tunnel.describe_problem().is_empty():
			continue
		var record := LevelGraph.Tunnel.new()
		record.id = tunnel.name
		record.from_id = tunnel.resolve_from().name
		record.to_id = tunnel.resolve_to().name
		record.polyline = tunnel.build_polyline()
		record.width = tunnel.width
		record.tags = tunnel.tags
		record.notes = tunnel.notes
		graph.add_tunnel(record)
	return graph


## The previewed noise. Recomputes first if anything has moved since the last one,
## so a caller never reads a field measured against a stale layout.
func current_sound_field() -> LevelGraph.SoundField:
	if _dirty or _sound_field == null:
		_dirty = false
		_recompute()
	return _sound_field


## Throws away the drawn diagram and builds it again from the authored nodes.
func rebuild_visuals() -> void:
	_dirty = false
	_recompute()
	_draw_everything()


## Re-reads the level as data. No drawing, so this is what runs when the diagram
## is switched off and only the graph is wanted.
func _recompute() -> void:
	_graph = build_graph()
	_sound_field = _compute_sound_field(_graph)
	_measure_depth_range()


func _draw_everything() -> void:
	_material_cache.clear()
	_reset_visual_container()
	for space: MineSpace in spaces_in_level():
		_draw_space(space)
	for tunnel: MineTunnel in tunnels_in_level():
		# A tunnel's shape comes from the spaces at its ends, so dragging a room
		# has to refresh the gizmo of every tunnel arriving at it - which that
		# tunnel has no way of noticing for itself.
		tunnel.update_gizmos()
		if tunnel.describe_problem().is_empty():
			_draw_tunnel(tunnel)


## Totals the dock reports. Every number here is derived, never authored.
func describe_stats() -> Dictionary:
	var graph := build_graph()
	var longest_name := ""
	var longest := 0.0
	var shortest_name := ""
	var shortest := INF
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		if tunnel.length() > longest:
			longest = tunnel.length()
			longest_name = tunnel.id
		if tunnel.length() < shortest:
			shortest = tunnel.length()
			shortest_name = tunnel.id

	var passable := graph.passable_tunnel_ids(creature_min_width).size()
	return {
		"space_count": graph.spaces.size(),
		"room_count": _count_of_kind(graph, LevelGraph.SpaceKind.ROOM),
		"junction_count": _count_of_kind(graph, LevelGraph.SpaceKind.JUNCTION),
		"dead_end_count": _count_of_kind(graph, LevelGraph.SpaceKind.DEAD_END),
		"tunnel_count": graph.tunnels.size(),
		"total_length": graph.total_length(),
		"longest_tunnel": longest_name,
		"longest_length": longest,
		"shortest_tunnel": shortest_name,
		"shortest_length": 0.0 if shortest == INF else shortest,
		"passable_tunnels": passable,
		"refuge_tunnels": graph.tunnels.size() - passable,
		"shallowest": _shallowest,
		"deepest": _deepest,
	}


## Everything wrong with the level, in the order it is worth fixing. Empty is a
## clean bill of health.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen_names := {}
	for space: MineSpace in spaces_in_level():
		if seen_names.has(space.name):
			problems.append("Duplicate space name '%s' - names are graph ids." % space.name)
		seen_names[space.name] = true

	for tunnel: MineTunnel in tunnels_in_level():
		var problem := tunnel.describe_problem()
		if not problem.is_empty():
			problems.append("Tunnel '%s': %s" % [tunnel.name, problem])

	var graph := build_graph()
	var root := _entrance_id(graph)
	if root.is_empty():
		problems.append("No spaces in the level yet.")
		return problems

	for orphan: StringName in graph.unreachable_from(root):
		var reason := "isolated" if graph.degree(orphan) == 0 else "no route from %s" % root
		problems.append("Space '%s' cannot be reached: %s." % [orphan, reason])
	return problems


## The colour a space draws in under the current mode, honouring its override.
func color_for_space(space: MineSpace) -> Color:
	if space.has_color_override():
		return space.display_color
	var chosen := COLOR_UNIFORM_SPACE
	match color_mode:
		ColorMode.TAG:
			chosen = _color_for_tags(space.tags, COLOR_UNIFORM_SPACE)
		ColorMode.DEPTH:
			chosen = COLOR_SHALLOW.lerp(COLOR_DEEP, _depth_fraction(space.global_position.y))
		ColorMode.SOUND:
			chosen = _sound_color(float(_sound_field.remaining_at_space.get(space.name, -1.0)))
		_:
			chosen = COLOR_UNIFORM_SPACE
	return chosen


## The colour a tunnel draws in under the current mode, honouring its override.
##
## SOUND is absent from this match on purpose: a tunnel in that mode is not one
## colour, because a noise can light the first sixty metres of it and leave the
## rest silent. _draw_tunnel splits it instead.
func color_for_tunnel(tunnel: MineTunnel) -> Color:
	if tunnel.has_color_override():
		return tunnel.display_color
	var chosen := COLOR_UNIFORM_TUNNEL
	match color_mode:
		ColorMode.TAG:
			chosen = _color_for_tags(tunnel.tags, COLOR_UNIFORM_TUNNEL)
		ColorMode.WIDTH:
			var span := WIDEST_DRAWN - NARROWEST_DRAWN
			var reach := clampf((tunnel.width - NARROWEST_DRAWN) / span, 0.0, 1.0)
			chosen = COLOR_NARROW.lerp(COLOR_WIDE, reach)
		ColorMode.DEPTH:
			chosen = COLOR_SHALLOW.lerp(COLOR_DEEP, _depth_fraction(_tunnel_mid_height(tunnel)))
		ColorMode.CREATURE_PASSABLE:
			chosen = COLOR_PASSABLE if tunnel.width >= creature_min_width else COLOR_REFUGE
		_:
			chosen = COLOR_UNIFORM_TUNNEL
	return chosen


func _compute_sound_field(graph: LevelGraph) -> LevelGraph.SoundField:
	var origin := get_node_or_null(sound_origin)
	var space_origin := origin as MineSpace
	if space_origin != null:
		return graph.propagate_from_space(space_origin.name, sound_loudness)
	var tunnel_origin := origin as MineTunnel
	if tunnel_origin != null:
		var along := tunnel_origin.length() * sound_origin_fraction
		return graph.propagate_from_tunnel(tunnel_origin.name, along, sound_loudness)
	return LevelGraph.SoundField.new()


func _reset_visual_container() -> void:
	if is_instance_valid(_visuals):
		_visuals.free()
	_visuals = Node3D.new()
	_visuals.name = "DesignVisuals"
	# No owner, so it is never written to the .tscn.
	add_child(_visuals)


func _draw_space(space: MineSpace) -> void:
	var color := color_for_space(space)
	var draw_radius := maxf(space.radius, MARKER_RADIUS)
	var sphere := SphereMesh.new()
	sphere.radius = draw_radius
	sphere.height = draw_radius * 2.0
	sphere.radial_segments = SPHERE_SEGMENTS
	sphere.rings = SPHERE_RINGS

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _material_for(color, space_alpha)
	mesh_instance.transform = _to_level(Transform3D(Basis(), space.global_position))
	_visuals.add_child(mesh_instance)

	if show_labels:
		_draw_label(_describe_space(space), space.global_position + Vector3.UP * draw_radius, color)


func _draw_tunnel(tunnel: MineTunnel) -> void:
	var points := tunnel.build_polyline()
	var radius := tunnel.width * 0.5
	if color_mode == ColorMode.SOUND:
		_draw_tunnel_by_sound(tunnel, points, radius)
	else:
		_draw_tube(points, color_for_tunnel(tunnel), radius)

	if show_labels:
		var midpoint := LevelGraph.point_on_polyline(points, _polyline_length(points) * 0.5)
		_draw_label(_describe_tunnel(tunnel), midpoint, color_for_tunnel(tunnel))


## Splits the tunnel at the edges of what can hear the noise, so a partly-audible
## tunnel reads as partly audible rather than being rounded to one answer.
func _draw_tunnel_by_sound(tunnel: MineTunnel, points: PackedVector3Array, radius: float) -> void:
	var span := _polyline_length(points)
	var intervals: Array = _sound_field.covered_intervals.get(tunnel.name, [])
	var cursor := 0.0
	for interval: Vector2 in intervals:
		if interval.x > cursor:
			_draw_tube(LevelGraph.slice_polyline(points, cursor, interval.x), COLOR_SILENT, radius)
		var remaining := _sound_field.loudness - minf(interval.x, span - interval.y)
		_draw_tube(
			LevelGraph.slice_polyline(points, interval.x, interval.y),
			_sound_color(remaining),
			radius
		)
		cursor = interval.y
	if cursor < span:
		_draw_tube(LevelGraph.slice_polyline(points, cursor, span), COLOR_SILENT, radius)


func _draw_tube(points: PackedVector3Array, color: Color, radius: float) -> void:
	var material := _material_for(color, tunnel_alpha)
	for index: int in maxi(points.size() - 1, 0):
		var start := points[index]
		var finish := points[index + 1]
		var direction := finish - start
		var span := direction.length()
		if span <= 0.0:
			continue
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = span
		cylinder.radial_segments = TUBE_SIDES
		cylinder.rings = 0

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = cylinder
		mesh_instance.material_override = material
		mesh_instance.transform = _to_level(
			Transform3D(basis_aligning_up_with(direction), (start + finish) * 0.5)
		)
		_visuals.add_child(mesh_instance)


func _draw_label(text: String, world_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = label_pixel_size
	label.modulate = Color(color.r, color.g, color.b, 1.0)
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.transform = _to_level(Transform3D(Basis(), world_position))
	_visuals.add_child(label)


func _describe_space(space: MineSpace) -> String:
	var suffix := ""
	if color_mode == ColorMode.SOUND:
		var remaining := float(_sound_field.remaining_at_space.get(space.name, -1.0))
		suffix = "\nsilent" if remaining < 0.0 else "\n%.0f m of noise left" % remaining
	elif space.radius > 0.0:
		suffix = "\nr %.1f m" % space.radius
	return "%s%s" % [space.name, suffix]


func _describe_tunnel(tunnel: MineTunnel) -> String:
	var fit := "" if tunnel.width >= creature_min_width else "  refuge"
	return "%s\n%.0f m long, %.1f m wide%s" % [tunnel.name, tunnel.length(), tunnel.width, fit]


## Dark grey for silence, deep red for a noise that barely arrived, near-white
## for one made right here.
func _sound_color(remaining: float) -> Color:
	if remaining < 0.0 or _sound_field.loudness <= 0.0:
		return COLOR_SILENT
	var strength := clampf(remaining / _sound_field.loudness, 0.0, 1.0)
	return COLOR_HEARD_FAINT.lerp(COLOR_HEARD_LOUD, strength)


func _color_for_tags(tags: Array[StringName], fallback: Color) -> Color:
	if tags.is_empty():
		return fallback
	var first := tags[0]
	if tag_colors.has(first):
		return tag_colors[first]
	var hue := fmod(absf(float(hash(first))) * TAG_HUE_STEP, 1.0)
	return Color.from_hsv(hue, 0.7, 1.0)


func _depth_fraction(height: float) -> float:
	if is_equal_approx(_shallowest, _deepest):
		return 0.0
	return clampf((_shallowest - height) / (_shallowest - _deepest), 0.0, 1.0)


func _measure_depth_range() -> void:
	_shallowest = 0.0
	_deepest = 0.0
	var started := false
	for space: LevelGraph.Space in _graph.spaces:
		var height := space.position.y
		_shallowest = height if not started else maxf(_shallowest, height)
		_deepest = height if not started else minf(_deepest, height)
		started = true


func _tunnel_mid_height(tunnel: MineTunnel) -> float:
	var from_node := tunnel.resolve_from()
	var to_node := tunnel.resolve_to()
	if from_node == null or to_node == null:
		return 0.0
	return (from_node.global_position.y + to_node.global_position.y) * 0.5


func _entrance_id(graph: LevelGraph) -> StringName:
	var chosen := get_node_or_null(entrance_space) as MineSpace
	if chosen != null:
		return chosen.name
	if graph.spaces.is_empty():
		return &""
	return graph.spaces[0].id


func _count_of_kind(graph: LevelGraph, kind: LevelGraph.SpaceKind) -> int:
	var total := 0
	for space: LevelGraph.Space in graph.spaces:
		if space.kind == kind:
			total += 1
	return total


func _material_for(color: Color, alpha: float) -> StandardMaterial3D:
	var key := Color(color.r, color.g, color.b, alpha)
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = key
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Seen from inside as often as outside, and a diagram you can look through is
	# the entire point of drawing it transparent.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = material
	return material


## Converts a world-space transform into this level's local space, so the drawn
## children sit correctly even if the level root has been moved or rotated.
func _to_level(world: Transform3D) -> Transform3D:
	return global_transform.affine_inverse() * world


## A basis whose local +Y - a CylinderMesh's long axis - runs along `direction`.
##
## Quaternion(from, to) picks a degenerate axis when the two are exactly
## opposite, which for a cylinder pointing straight down leaves it pointing
## straight up. The entrance shaft of a mine is the case that hits this.
##
## Static and public because the editor gizmo builds the same tubes to make a
## tunnel clickable, and two copies of this would disagree on the vertical case.
static func basis_aligning_up_with(direction: Vector3) -> Basis:
	if direction.is_zero_approx():
		return Basis()
	var heading := direction.normalized()
	if heading.dot(Vector3.UP) < -0.9999:
		return Basis.from_euler(Vector3(PI, 0.0, 0.0))
	return Basis(Quaternion(Vector3.UP, heading))


func _walk_authored_children(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if child == _visuals:
			continue
		found.append(child)
		found.append_array(_walk_authored_children(child))
	return found


func _polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in maxi(points.size() - 1, 0):
		total += points[index].distance_to(points[index + 1])
	return total
