extends SceneTree

## Emits the blockout as a ROUTES / CHAMBERS table, in the shape
## prototypes/core_loop/core_loop_knobs.gd already uses.
##
## IT WRITES A SEPARATE FILE AND NEVER TOUCHES core_loop_knobs.gd. That file
## carries a paragraph of design reasoning on half its entries - why the core
## descent is a trunk, what the squeeze is for - and a generator that rewrote it
## would delete all of it on the first run. Diff this against it and take across
## what actually changed.
##
## Junction coordinates come out as named consts referenced by both tables, so
## two routes meeting at a space produce bit-identical endpoints and the
## prototype's welding still recognises them as one junction.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/export_layout_snippet.gd

const DEFAULT_LEVEL_PATH := "res://levels/design/level_mine_blockout.tscn"
const OUTPUT_PATTERN := "res://documentation/design/%s_layout.gd.txt"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var packed := load(_level_path()) as PackedScene
	if packed == null:
		printerr("Could not load %s" % _level_path())
		quit(1)
		return

	var level := packed.instantiate() as MineLevel
	root.add_child(level)
	await process_frame

	var graph := level.build_graph()
	var text := _render_snippet(level, graph)
	DirAccess.make_dir_recursive_absolute(OUTPUT_PATTERN.get_base_dir())
	var output_path := OUTPUT_PATTERN % _level_path().get_file().get_basename()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s" % output_path)
		quit(1)
		return
	file.store_string(text)
	file.close()

	print("Wrote %s" % output_path)
	print(
		(
			"  %d junction consts, %d routes, %d chambers"
			% [
				graph.spaces.size(),
				graph.tunnels.size(),
				_chamber_spaces(graph).size(),
			]
		)
	)
	level.free()
	quit(0)


func _render_snippet(level: MineLevel, graph: LevelGraph) -> String:
	var lines := PackedStringArray()
	lines.append(
		"# Generated from %s by tools/level_design/export_layout_snippet.gd." % _level_path()
	)
	lines.append("# The blockout scene is the source of truth; this is a copy to diff against.")
	lines.append("#")
	(
		lines
		. append(
			(
				"# %d spaces, %d tunnels, %.0f m of centreline. Creature threshold %.1f m."
				% [
					graph.spaces.size(),
					graph.tunnels.size(),
					graph.total_length(),
					level.creature_min_width,
				]
			)
		)
	)
	lines.append("")
	lines.append(_render_junctions(graph))
	lines.append("")
	lines.append(_render_routes(level, graph))
	lines.append("")
	lines.append(_render_chambers(graph))
	lines.append("")
	lines.append(_render_refuges(level, graph))
	return "\n".join(lines) + "\n"


func _render_junctions(graph: LevelGraph) -> String:
	var lines := PackedStringArray(["#region Map - junctions"])
	for space: LevelGraph.Space in graph.spaces:
		if not space.notes.is_empty():
			for note_line: String in space.notes.split("\n"):
				lines.append("## %s" % note_line)
		lines.append("const %s := %s" % [_const_name(space.id), _vector_literal(space.position)])
		lines.append("")
	lines.append("#endregion")
	return "\n".join(lines)


func _render_routes(level: MineLevel, graph: LevelGraph) -> String:
	var lines := PackedStringArray(["#region Map - routes", "", "const ROUTES := ["])
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		lines.append("\t{")
		if not tunnel.notes.is_empty():
			for note_line: String in tunnel.notes.split("\n"):
				lines.append("\t\t# %s" % note_line)
		lines.append('\t\t"name": "%s",' % tunnel.id)
		lines.append('\t\t"width": %s,' % _float_literal(tunnel.width))
		lines.append('\t\t"points": [%s],' % _route_points(level, tunnel))
		lines.append("\t},")
	lines.append("]")
	lines.append("#endregion")
	return "\n".join(lines)


## Endpoints as junction consts, bends as literals. Two routes meeting at a space
## therefore emit the same symbol, which is what keeps the weld exact.
func _route_points(level: MineLevel, tunnel: LevelGraph.Tunnel) -> String:
	var node := level.get_node_or_null(NodePath("Tunnels/%s" % tunnel.id)) as MineTunnel
	var parts := PackedStringArray([_const_name(tunnel.from_id)])
	if node != null:
		for marker: Marker3D in node.bend_markers():
			parts.append(_vector_literal(marker.global_position))
	parts.append(_const_name(tunnel.to_id))
	return ", ".join(parts)


func _render_chambers(graph: LevelGraph) -> String:
	var lines := PackedStringArray(["#region Map - chambers", "", "const CHAMBERS := ["])
	for space: LevelGraph.Space in _chamber_spaces(graph):
		lines.append(
			(
				'\t{"center": %s, "radius": %s},'
				% [_const_name(space.id), _float_literal(space.radius)]
			)
		)
	lines.append("]")
	lines.append("#endregion")
	return "\n".join(lines)


func _render_refuges(level: MineLevel, graph: LevelGraph) -> String:
	var names := PackedStringArray()
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		if tunnel.width < level.creature_min_width:
			names.append('"%s"' % tunnel.id)
	return (
		"## Routes the creature cannot enter, from a %.1f m threshold.\nconst REFUGE_ROUTES := [%s]"
		% [level.creature_min_width, ", ".join(names)]
	)


## Only spaces that actually have a chamber cut at them. A junction of radius 0
## is a corner, and emitting it as a zero-radius sphere would carve nothing.
func _chamber_spaces(graph: LevelGraph) -> Array[LevelGraph.Space]:
	var found: Array[LevelGraph.Space] = []
	for space: LevelGraph.Space in graph.spaces:
		if space.radius > 0.0:
			found.append(space)
	return found


func _const_name(space_id: StringName) -> String:
	return String(space_id).to_upper()


func _vector_literal(point: Vector3) -> String:
	return (
		"Vector3(%s, %s, %s)"
		% [_float_literal(point.x), _float_literal(point.y), _float_literal(point.z)]
	)


## Whole numbers stay whole, so a table of hand-typed integers does not come back
## littered with trailing zeroes and diff as though every line changed.
func _float_literal(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return "%.2f" % value


## Which level to read. Defaults to the mine blockout; `-- --level=res://...`
## points any of these tools at another one.
func _level_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			return argument.trim_prefix("--level=")
	return DEFAULT_LEVEL_PATH
