extends SceneTree

## Renders the mine blockout as a plan and an elevation, side by side, into one
## SVG for the design document.
##
## SVG RATHER THAN PNG, because the labels are the point. Rasterising text needs
## a font rendered pixel by pixel from a headless process; writing `<text>` needs
## nothing, stays sharp at any zoom, diffs as text, and drops straight into
## markdown. Converting to PNG afterwards is one command if a raster is wanted.
##
## Colours come from the level's own colour mode, so the diagram and the 3D view
## agree without a second palette to keep in step.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/render_level_maps.gd
##   godot --headless --path <root> --script ... -- --mode=creature_passable

const LEVEL_PATH := "res://levels/design/level_mine_blockout.tscn"
## Named for the colour mode, so a width map and a sound map can sit side by side
## in the design document instead of overwriting each other.
const OUTPUT_PATTERN := "res://documentation/design/images/mine_blockout_%s.svg"

const PANEL_WIDTH := 900.0
const PANEL_HEIGHT := 1000.0
const PANEL_GAP := 40.0
const MARGIN := 70.0
const HEADER_HEIGHT := 86.0

const SPACE_LABEL_SIZE := 13.0
const TUNNEL_LABEL_SIZE := 11.0
const MIN_STROKE := 2.0
const MIN_SPACE_RADIUS := 3.0

const BACKGROUND := "#14161a"
const FOREGROUND := "#e8eaf0"
const MUTED := "#8b93a3"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var packed := load(LEVEL_PATH) as PackedScene
	if packed == null:
		printerr("Could not load %s" % LEVEL_PATH)
		quit(1)
		return

	var level := packed.instantiate() as MineLevel
	root.add_child(level)
	_apply_mode_override(level)
	await process_frame

	var graph := level.build_graph()
	if graph.spaces.is_empty():
		printerr("The level has no spaces to draw.")
		quit(1)
		return

	var mode_name: String = MineLevel.ColorMode.keys()[level.color_mode]
	var output_path := OUTPUT_PATTERN % mode_name.to_lower()
	var svg := _render(level, graph)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s" % output_path)
		quit(1)
		return
	file.store_string(svg)
	file.close()

	print("Wrote %s" % output_path)
	print(
		(
			"  %d spaces, %d tunnels, %.0f m, colour mode %s"
			% [
				graph.spaces.size(),
				graph.tunnels.size(),
				graph.total_length(),
				MineLevel.ColorMode.keys()[level.color_mode],
			]
		)
	)
	level.free()
	quit(0)


func _apply_mode_override(level: MineLevel) -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--mode="):
			continue
		var wanted := argument.trim_prefix("--mode=").to_upper()
		var modes: Array = MineLevel.ColorMode.keys()
		if wanted in modes:
			level.color_mode = modes.find(wanted) as MineLevel.ColorMode
		else:
			printerr("Unknown colour mode '%s'. Known: %s" % [wanted, ", ".join(modes)])


func _render(level: MineLevel, graph: LevelGraph) -> String:
	var total_width := PANEL_WIDTH * 2.0 + PANEL_GAP
	var total_height := PANEL_HEIGHT + HEADER_HEIGHT

	# One scale across both panels, so a 40 m tunnel looks the same length in the
	# plan as it does in the elevation and the two can be read against each other.
	var scale := minf(_fit_scale(graph, true), _fit_scale(graph, false))

	var parts := PackedStringArray()
	(
		parts
		. append(
			(
				'<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f">'
				% [total_width, total_height, total_width, total_height]
			)
		)
	)
	parts.append('<rect width="100%%" height="100%%" fill="%s"/>' % BACKGROUND)
	parts.append(_render_header(level, graph, total_width))
	parts.append(_render_panel(level, graph, scale, true, 0.0))
	parts.append(_render_panel(level, graph, scale, false, PANEL_WIDTH + PANEL_GAP))
	parts.append("</svg>")
	return "\n".join(parts)


func _render_header(level: MineLevel, graph: LevelGraph, total_width: float) -> String:
	var passable := graph.passable_tunnel_ids(level.creature_min_width).size()
	var summary := (
		"%d spaces, %d tunnels, %.0f m of centreline. Creature fits down %d of %d at %.1f m."
		% [
			graph.spaces.size(),
			graph.tunnels.size(),
			graph.total_length(),
			passable,
			graph.tunnels.size(),
			level.creature_min_width,
		]
	)
	return (
		(
			'<text x="%.0f" y="34" fill="%s" font-family="sans-serif" font-size="22">%s</text>'
			% [MARGIN, FOREGROUND, _escape(level.name)]
		)
		+ (
			'\n<text x="%.0f" y="58" fill="%s" font-family="sans-serif" font-size="13">%s</text>'
			% [MARGIN, MUTED, _escape(summary)]
		)
		+ (
			(
				'\n<text x="%.0f" y="58" text-anchor="end" fill="%s" font-family="sans-serif"'
				+ ' font-size="13">colour: %s</text>'
			)
			% [total_width - MARGIN, MUTED, MineLevel.ColorMode.keys()[level.color_mode].to_lower()]
		)
	)


## One projection. `is_plan` picks x/z looking down against x/y looking side on.
func _render_panel(
	level: MineLevel, graph: LevelGraph, scale: float, is_plan: bool, offset_x: float
) -> String:
	var origin := _projection_origin(graph, scale, is_plan, offset_x)
	var parts := PackedStringArray()
	parts.append('<g id="%s">' % ("plan" if is_plan else "elevation"))
	(
		parts
		. append(
			(
				'<text x="%.0f" y="%.0f" fill="%s" font-family="sans-serif" font-size="15">%s</text>'
				% [
					offset_x + MARGIN,
					HEADER_HEIGHT + 26.0,
					FOREGROUND,
					"PLAN - looking down (x / z)" if is_plan else "ELEVATION - side on (x / depth)",
				]
			)
		)
	)

	var field := level.current_sound_field()
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		if level.color_mode == MineLevel.ColorMode.SOUND:
			parts.append(_render_tunnel_by_sound(tunnel, field, origin, scale, is_plan))
		else:
			parts.append(_render_tunnel(level, tunnel, origin, scale, is_plan))
	for space: LevelGraph.Space in graph.spaces:
		parts.append(_render_space(level, space, origin, scale, is_plan))
	parts.append("</g>")
	return "\n".join(parts)


func _render_tunnel(
	level: MineLevel, tunnel: LevelGraph.Tunnel, origin: Vector2, scale: float, is_plan: bool
) -> String:
	var node := level.get_node_or_null(NodePath("Tunnels/%s" % tunnel.id)) as MineTunnel
	var color := level.color_for_tunnel(node) if node != null else Color(0.5, 0.6, 0.8)
	var points := PackedStringArray()
	for point: Vector3 in tunnel.polyline:
		var flat := _project(point, origin, scale, is_plan)
		points.append("%.1f,%.1f" % [flat.x, flat.y])

	var stroke := maxf(tunnel.width * scale, MIN_STROKE)
	var midpoint := _project(tunnel.point_at(tunnel.length() * 0.5), origin, scale, is_plan)
	return (
		(
			(
				'<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f"'
				+ ' stroke-opacity="0.55" stroke-linejoin="round" stroke-linecap="round"/>'
			)
			% [" ".join(points), _hex(color), stroke]
		)
		+ (
			(
				'\n<text x="%.1f" y="%.1f" fill="%s" font-family="sans-serif" font-size="%.0f"'
				+ ' text-anchor="middle">%s  %.0fm</text>'
			)
			% [
				midpoint.x,
				midpoint.y - 4.0,
				MUTED,
				TUNNEL_LABEL_SIZE,
				_escape(tunnel.id),
				tunnel.length(),
			]
		)
	)


## A tunnel drawn as a silent base with the audible stretches laid over it, so a
## tunnel the noise only reaches partway down reads as exactly that.
func _render_tunnel_by_sound(
	tunnel: LevelGraph.Tunnel,
	field: LevelGraph.SoundField,
	origin: Vector2,
	scale: float,
	is_plan: bool
) -> String:
	var stroke := maxf(tunnel.width * scale, MIN_STROKE)
	var span := tunnel.length()
	var parts := PackedStringArray(
		[
			_polyline_markup(
				tunnel.polyline, origin, scale, is_plan, MineLevel.COLOR_SILENT, stroke, 0.5
			)
		]
	)

	for interval: Vector2 in field.covered_intervals.get(tunnel.id, [] as Array[Vector2]):
		var remaining := field.loudness - minf(interval.x, span - interval.y)
		var strength := clampf(remaining / maxf(field.loudness, 0.001), 0.0, 1.0)
		var color := MineLevel.COLOR_HEARD_FAINT.lerp(MineLevel.COLOR_HEARD_LOUD, strength)
		parts.append(
			_polyline_markup(
				LevelGraph.slice_polyline(tunnel.polyline, interval.x, interval.y),
				origin,
				scale,
				is_plan,
				color,
				stroke,
				0.95
			)
		)

	var covered := field.covered_length(tunnel.id)
	var midpoint := _project(tunnel.point_at(span * 0.5), origin, scale, is_plan)
	parts.append(
		(
			(
				'<text x="%.1f" y="%.1f" fill="%s" font-family="sans-serif" font-size="%.0f"'
				+ ' text-anchor="middle">%s  %.0f/%.0fm heard</text>'
			)
			% [
				midpoint.x,
				midpoint.y - 4.0,
				MUTED,
				TUNNEL_LABEL_SIZE,
				_escape(tunnel.id),
				covered,
				span
			]
		)
	)
	return "\n".join(parts)


func _polyline_markup(
	points: PackedVector3Array,
	origin: Vector2,
	scale: float,
	is_plan: bool,
	color: Color,
	stroke: float,
	opacity: float
) -> String:
	if points.size() < 2:
		return ""
	var flat := PackedStringArray()
	for point: Vector3 in points:
		var projected := _project(point, origin, scale, is_plan)
		flat.append("%.1f,%.1f" % [projected.x, projected.y])
	return (
		(
			'<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f"'
			+ ' stroke-opacity="%.2f" stroke-linejoin="round" stroke-linecap="round"/>'
		)
		% [" ".join(flat), _hex(color), stroke, opacity]
	)


func _render_space(
	level: MineLevel, space: LevelGraph.Space, origin: Vector2, scale: float, is_plan: bool
) -> String:
	var node := level.get_node_or_null(NodePath("Spaces/%s" % space.id)) as MineSpace
	var color := level.color_for_space(node) if node != null else Color(0.6, 0.8, 1.0)
	var flat := _project(space.position, origin, scale, is_plan)
	var radius := maxf(space.radius * scale, MIN_SPACE_RADIUS)
	# A junction reads as a ring and a room as a disc, so the two are still told
	# apart in a printout with no colour.
	var is_junction := space.kind == LevelGraph.SpaceKind.JUNCTION
	return (
		(
			(
				'<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" fill-opacity="%s" stroke="%s"'
				+ ' stroke-width="1.5"/>'
			)
			% [
				flat.x,
				flat.y,
				radius,
				_hex(color),
				"0.15" if is_junction else "0.45",
				_hex(color),
			]
		)
		+ (
			(
				'\n<text x="%.1f" y="%.1f" fill="%s" font-family="sans-serif" font-size="%.0f"'
				+ ' text-anchor="middle">%s</text>'
			)
			% [flat.x, flat.y + radius + 14.0, FOREGROUND, SPACE_LABEL_SIZE, _escape(space.id)]
		)
	)


## World point to panel pixel. The elevation flips y so deeper is lower down the
## page, which is the only way a mine reads correctly.
func _project(point: Vector3, origin: Vector2, scale: float, is_plan: bool) -> Vector2:
	if is_plan:
		return Vector2(origin.x + point.x * scale, origin.y + point.z * scale)
	return Vector2(origin.x + point.x * scale, origin.y - point.y * scale)


func _projection_origin(graph: LevelGraph, scale: float, is_plan: bool, offset_x: float) -> Vector2:
	var box := graph.bounds()
	var low := _flatten(box.position, is_plan)
	var high := _flatten(box.position + box.size, is_plan)
	var drawable_top := HEADER_HEIGHT + 44.0
	var drawable_height := PANEL_HEIGHT - (drawable_top - HEADER_HEIGHT) - MARGIN
	var centre_x := offset_x + PANEL_WIDTH * 0.5
	var centre_y := drawable_top + drawable_height * 0.5

	var mid := (low + high) * 0.5
	if is_plan:
		return Vector2(centre_x - mid.x * scale, centre_y - mid.y * scale)
	# Elevation's vertical axis is negated by _project, so the offset is too.
	return Vector2(centre_x - mid.x * scale, centre_y + mid.y * scale)


func _fit_scale(graph: LevelGraph, is_plan: bool) -> float:
	var box := graph.bounds()
	var low := _flatten(box.position, is_plan)
	var high := _flatten(box.position + box.size, is_plan)
	var span := high - low
	var usable_width := PANEL_WIDTH - MARGIN * 2.0
	var usable_height := PANEL_HEIGHT - HEADER_HEIGHT - MARGIN * 2.0
	var horizontal := usable_width / maxf(span.x, 1.0)
	var vertical := usable_height / maxf(span.y, 1.0)
	return minf(horizontal, vertical)


func _flatten(point: Vector3, is_plan: bool) -> Vector2:
	return Vector2(point.x, point.z) if is_plan else Vector2(point.x, point.y)


## Color.to_html omits the leading hash, which SVG requires.
func _hex(color: Color) -> String:
	return "#%s" % color.to_html(false)


func _escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
		'"', "&quot;"
	)
