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
##   chains              Array of chain dictionaries. See _create_chain.
##   layer_stacks        Array of stack dictionaries. See _create_layer_stack.
##   spaces              Array of free-form space entries.
##   tunnels             Array of free-form tunnel entries. An entry carrying
##                       `bends` as an int rather than an array gets that many
##                       generated corners. See _wind_between.
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
	var chains: Array = spec.get("chains", [])
	for chain: Dictionary in chains:
		_create_chain_spaces(level, space_root, chain)
	var stacks: Array = spec.get("layer_stacks", [])
	for stack: Dictionary in stacks:
		_create_layer_stack_spaces(level, space_root, stack)

	# Tunnels only after every space exists, so any of them can name any of them.
	for grid: Dictionary in grids:
		_create_grid_tunnels(level, tunnel_root, grid, spec["creature_min_width"])
	for chain: Dictionary in chains:
		_create_chain_tunnels(level, tunnel_root, chain)
	for stack: Dictionary in stacks:
		_create_layer_stack_tunnels(level, tunnel_root, stack)
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
##   omitted_nodes           "<column>_<row>" keys with no working at all, and so
##                           no tunnel either. A RAGGED GRID IS THE POINT: a
##                           biome the player starts in has to be simple where
##                           they come in and complicated only further along, and
##                           a fully populated rectangle is uniformly confusing
##                           from the first junction.
func _create_grid_spaces(level: MineLevel, parent: Node3D, grid: Dictionary) -> void:
	var prefix: String = grid["prefix"]
	var drift_rows: Array = grid["drift_rows"]
	var missing: Array = grid.get("omitted_nodes", [])
	for column: String in grid["columns"]:
		for row: String in grid["rows"]:
			var key := "%s_%s" % [column, row]
			if key in missing:
				continue
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
	var missing: Array = grid.get("omitted_nodes", [])

	for row: String in rows:
		for index: int in columns.size() - 1:
			var key := "%s_%d" % [row, index + 1]
			if key in grid["omitted_drifts"]:
				continue
			# A drift to a working that was never dug is not a drift.
			if "%s_%s" % [columns[index], row] in missing:
				continue
			if "%s_%s" % [columns[index + 1], row] in missing:
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
			if "%s_%s" % [column, rows[index]] in missing:
				continue
			if "%s_%s" % [column, rows[index + 1]] in missing:
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


## A chain of spaces in a line, each joined to the next.
##
## This is what a ravine is: one long chasm is a run of stations rather than a
## single node, so that where you are along it is a thing the graph can answer and
## sound has somewhere to decay over.
##
## A chain dictionary is:
##
##   prefix        name prefix for every node it creates.
##   stations      Array of {name, position, radius, kind, tags, notes}.
##   width, height metres across and floor to roof, for every run in the chain.
##   tags, notes   put on the runs.
##   station_tags  put on the stations, on top of each station's own.
func _create_chain_spaces(level: MineLevel, parent: Node3D, chain: Dictionary) -> void:
	var prefix: String = chain["prefix"]
	var shared: Array = chain.get("station_tags", [])
	for station: Dictionary in chain["stations"]:
		var tags: Array = shared.duplicate()
		tags.append_array(station.get("tags", []))
		var space := _make_space(
			"%s_%s" % [prefix, station["name"]],
			station["position"],
			station["radius"],
			_kind_from_text(station.get("kind", "junction")),
			_to_tags(tags),
			station.get("notes", "")
		)
		parent.add_child(space)
		space.owner = level


func _create_chain_tunnels(level: MineLevel, parent: Node3D, chain: Dictionary) -> void:
	var prefix: String = chain["prefix"]
	var stations: Array = chain["stations"]
	for index: int in stations.size() - 1:
		_add_tunnel(
			level,
			parent,
			{
				"name": "%s_run_%d" % [prefix, index + 1],
				"from": "%s_%s" % [prefix, stations[index]["name"]],
				"to": "%s_%s" % [prefix, stations[index + 1]["name"]],
				"width": chain["width"],
				"height": chain.get("height", 0.0),
				"tags": chain.get("tags", []),
				"notes": chain.get("notes", ""),
			}
		)


## A stack of wide flat layers joined by short risers.
##
## Each layer is a hub with a ring of cells around it, all joined by bores that
## are wide and shallow - which is what makes a layer read as one flat cavity
## rather than as a ring of tunnels. Layers are offset and turned relative to one
## another so the stack never lines up into a shaft you can see down.
##
## A stack dictionary is:
##
##   prefix        name prefix for every node it creates.
##   center        x and z the whole stack is built around.
##   layers        Array of {name, y, offset: Vector2, radius, cells, twist,
##                 squash}. `twist` turns the ring, `squash` flattens it on z so
##                 a layer is not a perfect circle.
##   gap_width     in-plane bore, across. Wide.
##   gap_height    in-plane bore, floor to roof. Thin. This is the whole idea.
##   hub_radius, cell_radius
##   riser_width, riser_height
##   risers_per_gap  how many cells are joined to the layer below.
##   layer_tags, riser_tags
func _create_layer_stack_spaces(level: MineLevel, parent: Node3D, stack: Dictionary) -> void:
	var prefix: String = stack["prefix"]
	var tags := _to_tags(stack.get("layer_tags", []))
	for layer: Dictionary in stack["layers"]:
		var hub := _make_space(
			"%s_%s_hub" % [prefix, layer["name"]],
			_layer_center(stack, layer),
			stack["hub_radius"],
			LevelGraph.SpaceKind.ROOM,
			tags,
			layer.get("notes", "")
		)
		parent.add_child(hub)
		hub.owner = level
		for cell: int in layer["cells"]:
			var space := _make_space(
				"%s_%s_c%d" % [prefix, layer["name"], cell],
				_cell_position(stack, layer, cell),
				stack["cell_radius"],
				LevelGraph.SpaceKind.JUNCTION,
				tags,
				""
			)
			parent.add_child(space)
			space.owner = level


func _create_layer_stack_tunnels(level: MineLevel, parent: Node3D, stack: Dictionary) -> void:
	var prefix: String = stack["prefix"]
	var layers: Array = stack["layers"]
	for layer: Dictionary in layers:
		var cells: int = layer["cells"]
		for cell: int in cells:
			var here := "%s_%s_c%d" % [prefix, layer["name"], cell]
			# Round the rim, then in to the hub: a disc, not a ring.
			_add_layer_tunnel(
				level,
				parent,
				stack,
				layer,
				here,
				"%s_%s_c%d" % [prefix, layer["name"], (cell + 1) % cells],
				"rim%d" % cell
			)
			_add_layer_tunnel(
				level,
				parent,
				stack,
				layer,
				here,
				"%s_%s_hub" % [prefix, layer["name"]],
				"spoke%d" % cell
			)

	for index: int in layers.size() - 1:
		_add_risers(level, parent, stack, layers[index], layers[index + 1], index + 1)


func _add_layer_tunnel(
	level: MineLevel,
	parent: Node3D,
	stack: Dictionary,
	layer: Dictionary,
	from_name: String,
	to_name: String,
	suffix: String
) -> void:
	_add_tunnel(
		level,
		parent,
		{
			"name": "%s_%s_%s" % [stack["prefix"], layer["name"], suffix],
			"from": from_name,
			"to": to_name,
			"width": stack["gap_width"],
			"height": stack["gap_height"],
			"tags": stack.get("layer_tags", []),
		}
	)


## The short tunnels between one layer and the next.
##
## Spread evenly round the ring rather than stacked, so leaving a layer is a
## choice of several doors and none of them is the obvious one.
func _add_risers(
	level: MineLevel,
	parent: Node3D,
	stack: Dictionary,
	lower: Dictionary,
	upper: Dictionary,
	index: int
) -> void:
	var count: int = mini(stack["risers_per_gap"], mini(lower["cells"], upper["cells"]))
	for riser: int in count:
		var from_cell := int(round(float(riser) * float(lower["cells"]) / float(count)))
		var to_cell := int(round(float(riser) * float(upper["cells"]) / float(count)))
		_add_tunnel(
			level,
			parent,
			{
				"name": "%s_riser_%d_%d" % [stack["prefix"], index, riser],
				"from":
				"%s_%s_c%d" % [stack["prefix"], lower["name"], from_cell % int(lower["cells"])],
				"to": "%s_%s_c%d" % [stack["prefix"], upper["name"], to_cell % int(upper["cells"])],
				"width": stack["riser_width"],
				"height": stack.get("riser_height", 0.0),
				"tags": stack.get("riser_tags", []),
			}
		)


func _layer_center(stack: Dictionary, layer: Dictionary) -> Vector3:
	var origin: Vector3 = stack["center"]
	var offset: Vector2 = layer.get("offset", Vector2.ZERO)
	return Vector3(origin.x + offset.x, layer["y"], origin.z + offset.y)


func _cell_position(stack: Dictionary, layer: Dictionary, cell: int) -> Vector3:
	var middle := _layer_center(stack, layer)
	var cells: int = layer["cells"]
	var angle: float = layer.get("twist", 0.0) + TAU * float(cell) / float(cells)
	var radius: float = layer["radius"]
	var squash: float = layer.get("squash", 1.0)
	return middle + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * squash)


func _add_tunnel(level: MineLevel, parent: Node3D, entry: Dictionary) -> void:
	var from_space: MineSpace = _spaces_by_name.get(entry["from"])
	var to_space: MineSpace = _spaces_by_name.get(entry["to"])
	if from_space == null or to_space == null:
		printerr("Tunnel '%s' names a space that does not exist; skipped." % entry["name"])
		return

	var tunnel := MineTunnel.new()
	tunnel.name = entry["name"]
	tunnel.width = entry["width"]
	tunnel.height = entry.get("height", 0.0)
	tunnel.tags = _to_tags(entry.get("tags", []))
	tunnel.notes = entry.get("notes", "")
	parent.add_child(tunnel)
	tunnel.owner = level
	tunnel.from_space = tunnel.get_path_to(from_space)
	tunnel.to_space = tunnel.get_path_to(to_space)

	# An int asks for that many generated corners; an array is the corners.
	var declared: Variant = entry.get("bends", [])
	var bends: Array = (
		(
			_wind_between(from_space.position, to_space.position, entry)
			if declared is int
			else declared
		)
		as Array
	)
	for index: int in bends.size():
		var bend := MineBend.new()
		bend.name = "bend_%d" % (index + 1)
		bend.position = bends[index]
		tunnel.add_child(bend)
		bend.owner = level


## Corners for a tunnel that wanders rather than running straight.
##
## GENERATED, BECAUSE THE RAVINE HAS DOZENS OF THESE and typing three corners for
## each would be a page of coordinates nobody would ever tune. SEEDED, because a
## scaffold that produced a different level every run would not be a scaffold.
##
## `bends` is how many corners, `wander` how far they stray sideways and
## `wander_vertical` how far up and down. Sideways strays more than vertical by
## default: a solution tunnel following a seam snakes more than it undulates.
func _wind_between(from_position: Vector3, to_position: Vector3, entry: Dictionary) -> Array:
	var bend_count: int = entry.get("bends", 0)
	if bend_count <= 0:
		return []
	var wander: float = entry.get("wander", 0.0)
	var wander_vertical: float = entry.get("wander_vertical", wander * 0.4)
	var generator := RandomNumberGenerator.new()
	generator.seed = entry.get("seed", 0)

	var run := to_position - from_position
	var across := run.cross(Vector3.UP)
	if across.is_zero_approx():
		across = run.cross(Vector3.FORWARD)
	across = across.normalized()
	var vertical := across.cross(run).normalized()

	var bends := []
	for index: int in bend_count:
		var along := float(index + 1) / float(bend_count + 1)
		var stray := (
			across * generator.randf_range(-wander, wander)
			+ vertical * generator.randf_range(-wander_vertical, wander_vertical)
		)
		bends.append(from_position + run * along + stray)
	return bends


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
