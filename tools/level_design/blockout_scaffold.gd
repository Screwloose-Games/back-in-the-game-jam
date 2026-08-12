extends RefCounted

## Builds a blockout scene from a spec, so that a new biome is a data file rather
## than a program.
##
## THE SCENE IS THE SOURCE OF TRUTH ONCE THIS HAS RUN. A scaffold exists so fifty
## tunnels do not have to be placed by hand, not to keep a second copy of the
## design in step with the first. It refuses to overwrite without `--force`, and
## once you start moving things in the viewport you should stop running it.
##
## IT KNOWS EXACTLY ONE SHAPE: a rectangle of drifts crossed by cross-cuts, plus
## free-form spaces and tunnels that can say anything at all. That covers the
## mines. A biome whose structure is a different idea - the ravine's fissure, the
## hive's cells - needs either its own generator or to be drawn in the viewport,
## and for something irregular the viewport is the better answer anyway.
##
## A spec is a Dictionary:
##
##   output_path         where to write. `--out=` overrides it.
##   level_name          the root node's name. `--name=` overrides it.
##   creature_min_width  metres; anything narrower is tagged a refuge.
##   tag_colors          StringName -> Color, for the level's colour coding.
##   grids               Array of grid dictionaries. See _create_grid_spaces.
##   spaces              Array of free-form space entries.
##   tunnels             Array of free-form tunnel entries.
##   entrance            name of the space the level is entered from.
##   sound_origin        name of the space the noise preview starts in.
##
## Everything after `creature_min_width` is optional, so a spec that is nothing
## but free-form spaces and tunnels is a legitimate spec.
##
## NO class_name, DELIBERATELY. tools/ carries a .gdignore, so nothing under it
## is scanned and a class_name here would neither register globally nor even let
## this file name itself. Callers preload the path and instance it:
##
##   const Scaffold := preload("res://tools/level_design/blockout_scaffold.gd")
##   Scaffold.new().run(self, SPEC)

var _spaces_by_name: Dictionary = {}


## The whole command-line job: build, save, report, set the exit code.
func run(tree: SceneTree, spec: Dictionary) -> void:
	var arguments := OS.get_cmdline_user_args()
	var output_path := argument_value(arguments, "--out=", spec["output_path"])
	var level_name := argument_value(arguments, "--name=", spec["level_name"])

	if FileAccess.file_exists(output_path) and not "--force" in arguments:
		printerr(
			(
				(
					"%s already exists. This scaffold overwrites the design; "
					+ "re-run with `-- --force` if that is what you want."
				)
				% output_path
			)
		)
		tree.quit(1)
		return

	var level := build(spec, level_name)
	# Packing reads global transforms and tunnel lengths, neither of which exists
	# outside the tree.
	tree.root.add_child(level)

	var failure := save(level, output_path)
	if not failure.is_empty():
		printerr(failure)
		level.free()
		tree.quit(1)
		return

	report(level, output_path, spec)
	level.free()
	tree.quit(0)


## The value of a `--key=value` argument, or `fallback` when it is absent.
static func argument_value(
	arguments: PackedStringArray, prefix: String, fallback: String
) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return fallback


func build(spec: Dictionary, level_name: String) -> MineLevel:
	_spaces_by_name.clear()

	var level := MineLevel.new()
	level.name = level_name
	level.creature_min_width = spec["creature_min_width"]
	level.color_mode = MineLevel.ColorMode.TAG
	var colors: Dictionary[StringName, Color] = {}
	var declared: Dictionary = spec.get("tag_colors", {})
	for tag: StringName in declared:
		colors[tag] = declared[tag]
	level.tag_colors = colors

	var space_root := _make_group(level, "Spaces")
	var tunnel_root := _make_group(level, "Tunnels")

	# Free-form spaces first, then the grids, because a grid tunnel may name a
	# free-form space and every space has to exist before any tunnel is wired.
	for entry: Dictionary in spec.get("spaces", []):
		var space := _make_space(
			entry["name"],
			entry["position"],
			entry["radius"],
			_kind_from_text(entry.get("kind", "room")),
			_to_tags(entry.get("tags", [])),
			entry.get("notes", "")
		)
		space_root.add_child(space)
		space.owner = level

	var grids: Array = spec.get("grids", [])
	for grid: Dictionary in grids:
		_create_grid_spaces(level, space_root, grid)
	for grid: Dictionary in grids:
		_create_grid_tunnels(level, tunnel_root, grid, spec["creature_min_width"])
	for entry: Dictionary in spec.get("tunnels", []):
		_add_tunnel(level, tunnel_root, entry)

	_point_at(level, &"entrance_space", spec.get("entrance", ""))
	_point_at(level, &"sound_origin", spec.get("sound_origin", ""))
	return level


## Empty on success, otherwise why it failed.
func save(level: MineLevel, output_path: String) -> String:
	var packed := PackedScene.new()
	var pack_result := packed.pack(level)
	if pack_result != OK:
		return "Could not pack the level scene: error %d" % pack_result
	var save_result := ResourceSaver.save(packed, output_path)
	if save_result != OK:
		return "Could not save %s: error %d" % [output_path, save_result]
	return ""


func report(level: MineLevel, output_path: String, spec: Dictionary) -> void:
	var graph := level.build_graph()
	var min_width: float = spec["creature_min_width"]
	print("Wrote %s" % output_path)
	print("  %d spaces, %d tunnels" % [graph.spaces.size(), graph.tunnels.size()])
	print("  %.0f m of centreline" % graph.total_length())
	var passable := graph.passable_tunnel_ids(min_width).size()
	print("  creature fits down %d, blocked from %d" % [passable, graph.tunnels.size() - passable])
	var problems := level.validate()
	if problems.is_empty():
		print("  validate: clean")
		return
	for problem: String in problems:
		print("  validate: %s" % problem)


## One space per crossing of a column and a row.
##
## A grid dictionary is:
##
##   prefix                  name prefix for every node it creates.
##   columns, rows           the survey grid's labels, in order.
##   column_x, row_z         label -> coordinate. Exact, because the workings
##                           were surveyed and do line up in plan.
##   node_y                  "<column>_<row>" -> depth. Per node, because the
##                           workings follow the seam and do NOT line up in
##                           section - which is what stops the biome reading as
##                           one flat floor.
##   drift_rows              which rows are drifts rather than cross-cuts.
##   drift_junction_radius   chamber at a crossing on a drift row.
##   strip_junction_radius   chamber at any other crossing.
##   drift_width, strip_width  metres across.
##   narrow_strips           "<column>_<row><row>" -> a narrower width.
##   omitted_strips, omitted_drifts  keys to leave undug.
func _create_grid_spaces(level: MineLevel, parent: Node3D, grid: Dictionary) -> void:
	var prefix: String = grid["prefix"]
	var drift_rows: Array = grid["drift_rows"]
	for column: String in grid["columns"]:
		for row: String in grid["rows"]:
			var key := "%s_%s" % [column, row]
			var position := Vector3(
				grid["column_x"][column], grid["node_y"][key], grid["row_z"][row]
			)
			var radius: float = (
				grid["drift_junction_radius"]
				if row in drift_rows
				else grid["strip_junction_radius"]
			)
			var space := _make_space(
				"%s_%s" % [prefix, key],
				position,
				radius,
				LevelGraph.SpaceKind.JUNCTION,
				[StringName("mines_%s" % prefix)] as Array[StringName],
				""
			)
			parent.add_child(space)
			space.owner = level


## Drifts run along the columns, cross-cuts run along the rows. Both are straight
## and square, so neither gets a bend.
func _create_grid_tunnels(
	level: MineLevel, parent: Node3D, grid: Dictionary, creature_min_width: float
) -> void:
	var prefix: String = grid["prefix"]
	var columns: Array = grid["columns"]
	var rows: Array = grid["rows"]

	for row: String in rows:
		for index: int in columns.size() - 1:
			var key := "%s_%d" % [row, index + 1]
			if key in grid["omitted_drifts"]:
				continue
			_add_tunnel(
				level,
				parent,
				{
					"name": "drift_%s_%s" % [prefix, key],
					"from": "%s_%s_%s" % [prefix, columns[index], row],
					"to": "%s_%s_%s" % [prefix, columns[index + 1], row],
					"width": grid["drift_width"],
					"tags": ["drift"],
				}
			)

	for column: String in columns:
		for index: int in rows.size() - 1:
			var key := "%s_%s%s" % [column, rows[index], rows[index + 1]]
			if key in grid["omitted_strips"]:
				continue
			var width: float = grid["narrow_strips"].get(key, grid["strip_width"])
			var tags := ["strip"]
			if width < creature_min_width:
				tags.append("refuge")
			_add_tunnel(
				level,
				parent,
				{
					"name": "strip_%s_%s" % [prefix, key],
					"from": "%s_%s_%s" % [prefix, column, rows[index]],
					"to": "%s_%s_%s" % [prefix, column, rows[index + 1]],
					"width": width,
					"tags": tags,
				}
			)


func _add_tunnel(level: MineLevel, parent: Node3D, entry: Dictionary) -> void:
	var from_space: MineSpace = _spaces_by_name.get(entry["from"])
	var to_space: MineSpace = _spaces_by_name.get(entry["to"])
	if from_space == null or to_space == null:
		printerr("Tunnel '%s' names a space that does not exist; skipped." % entry["name"])
		return

	var tunnel := MineTunnel.new()
	tunnel.name = entry["name"]
	tunnel.width = entry["width"]
	tunnel.tags = _to_tags(entry.get("tags", []))
	tunnel.notes = entry.get("notes", "")
	parent.add_child(tunnel)
	tunnel.owner = level
	tunnel.from_space = tunnel.get_path_to(from_space)
	tunnel.to_space = tunnel.get_path_to(to_space)

	var bends: Array = entry.get("bends", [])
	for index: int in bends.size():
		var bend := MineBend.new()
		bend.name = "bend_%d" % (index + 1)
		bend.position = bends[index]
		tunnel.add_child(bend)
		bend.owner = level


func _make_group(level: MineLevel, group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	level.add_child(group)
	group.owner = level
	return group


func _make_space(
	space_name: String,
	position: Vector3,
	radius: float,
	kind: LevelGraph.SpaceKind,
	tags: Array[StringName],
	notes: String
) -> MineSpace:
	var space := MineSpace.new()
	space.name = space_name
	space.position = position
	space.radius = radius
	space.kind = kind
	space.tags = tags
	space.notes = notes
	_spaces_by_name[space_name] = space
	return space


func _point_at(level: MineLevel, property: StringName, space_name: String) -> void:
	if space_name.is_empty():
		return
	var space: MineSpace = _spaces_by_name.get(space_name)
	if space == null:
		printerr("Spec names '%s' for %s, which does not exist." % [space_name, property])
		return
	level.set(property, level.get_path_to(space))


func _kind_from_text(text: String) -> LevelGraph.SpaceKind:
	if text == "junction":
		return LevelGraph.SpaceKind.JUNCTION
	if text == "dead_end":
		return LevelGraph.SpaceKind.DEAD_END
	return LevelGraph.SpaceKind.ROOM


func _to_tags(raw: Array) -> Array[StringName]:
	var tags: Array[StringName] = []
	for entry: Variant in raw:
		tags.append(StringName(entry))
	return tags
