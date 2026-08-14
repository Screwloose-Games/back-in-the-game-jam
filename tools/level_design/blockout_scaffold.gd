extends RefCounted

## Builds a blockout scene from a spec, so that a new biome is a data file rather
## than a program.
##
## THE SCENE IS THE SOURCE OF TRUTH ONCE THIS HAS RUN. A scaffold exists so fifty
## tunnels do not have to be placed by hand, not to keep a second copy of the
## design in step with the first. It refuses to overwrite without `--force`, and
## once you start moving things in the viewport you should stop running it.
##
## IT KNOWS THREE SHAPES, one per biome: a rectangle of drifts crossed by
## cross-cuts for the mines, a line of stations for the ravine's chasm, and a
## stack of scattered strata for the hive. Anything else is a free-form space or
## tunnel, which can say whatever it likes, or is drawn in the viewport - and for
## a one-off irregularity the viewport is the better answer anyway.
##
## A spec is a Dictionary:
##
##   output_path         where to write. `--out=` overrides it.
##   level_name          the root node's name. `--name=` overrides it.
##   creature_min_width  metres; anything narrower is tagged a refuge.
##   tag_colors          StringName -> Color, for the level's colour coding.
##   grids               Array of grid dictionaries. See _create_grid_spaces.
##   chains              Array of chain dictionaries. See _create_chain.
##   strata              Array of strata dictionaries. See strata_layout.gd.
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

## The hive's shape, kept apart because it is geometry rather than scene building
## and is worth being able to re-roll and measure without a level being made.
const StrataLayout := preload("res://tools/level_design/strata_layout.gd")

var _spaces_by_name: Dictionary = {}

## prefix -> the layout StrataLayout returned. Carried between the two passes
## because the tunnels need the exact chambers the scatter produced, and running
## it a second time would draw a different set.
var _strata_layouts: Dictionary = {}

## Chamber names an anchor points at. Excluded from the dead-end sweep, because
## the free-form tunnels that reach them are added after this runs and their
## arrivals cannot be counted here.
var _anchored_names: Dictionary = {}


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
	_strata_layouts.clear()
	_anchored_names.clear()

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
	var all_strata: Array = spec.get("strata", [])
	for strata: Dictionary in all_strata:
		_create_strata_spaces(level, space_root, strata)

	# Tunnels only after every space exists, so any of them can name any of them.
	for grid: Dictionary in grids:
		_create_grid_tunnels(level, tunnel_root, grid, spec["creature_min_width"])
	for chain: Dictionary in chains:
		_create_chain_tunnels(level, tunnel_root, chain)
	for strata: Dictionary in all_strata:
		_create_strata_tunnels(level, tunnel_root, strata, spec["creature_min_width"])
	for entry: Dictionary in spec.get("tunnels", []):
		_add_tunnel(level, tunnel_root, entry)

	_point_at(level, &"entrance_space", spec.get("entrance", ""))
	_point_at(level, &"sound_origin", spec.get("sound_origin", ""))
	return level


## Empty on success, otherwise why it failed.
##
## THE UID OF THE SCENE BEING REPLACED IS CARRIED OVER. A .tscn written from code
## gets no `uid=` in its header, and a level that loses the one it had breaks
## every `uid://` reference to it - level_walkthrough.tscn points at the blockouts
## that way, and it only keeps working because Godot warns and falls back to the
## text path. Re-rolling a biome must not cost it its identity.
func save(level: MineLevel, output_path: String) -> String:
	var carried := _scene_uid(output_path)
	var packed := PackedScene.new()
	var pack_result := packed.pack(level)
	if pack_result != OK:
		return "Could not pack the level scene: error %d" % pack_result
	var save_result := ResourceSaver.save(packed, output_path)
	if save_result != OK:
		return "Could not save %s: error %d" % [output_path, save_result]
	if not carried.is_empty():
		_restore_scene_uid(output_path, carried)
	return ""


## The `uid="uid://..."` out of a scene file's header, or empty when it has none.
func _scene_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var header := file.get_line()
	file.close()
	var opening := header.find('uid="')
	if opening < 0:
		return ""
	var closing := header.find('"', opening + 5)
	return "" if closing < 0 else header.substr(opening, closing - opening + 1)


## Puts a carried-over uid back into a header the saver wrote without one.
func _restore_scene_uid(path: String, uid: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var newline := text.find("\n")
	var header := text.substr(0, newline)
	if newline < 0 or header.contains('uid="') or not header.ends_with("]"):
		return

	var rewritten := FileAccess.open(path, FileAccess.WRITE)
	if rewritten == null:
		printerr("Could not restore the uid on %s; references to it will warn." % path)
		return
	rewritten.store_string(header.insert(header.length() - 1, " %s" % uid) + text.substr(newline))
	rewritten.close()


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


## A stack of strata: mostly horizontal sheets of blobby chambers, staggered and
## breached into one another. StrataLayout works out where they go; this turns
## that into chambers and registers the anchors that let a hand-written tunnel
## name one.
##
## See strata_layout.gd for what a strata dictionary holds and why.
func _create_strata_spaces(level: MineLevel, parent: Node3D, strata: Dictionary) -> void:
	var layout: Dictionary = StrataLayout.new().build(strata)
	var tags := _to_tags(strata.get("stratum_tags", []))
	for stratum: Array in layout["chambers"] as Array:
		for chamber: Dictionary in stratum:
			var space := _make_space(
				chamber["name"],
				chamber["position"],
				chamber["radius"],
				_kind_from_text(chamber["kind"]),
				tags,
				""
			)
			space.vertical_scale = chamber["vertical_scale"]
			parent.add_child(space)
			space.owner = level

	var anchors: Dictionary = layout["anchors"]
	for alias: String in anchors:
		_spaces_by_name[alias] = _spaces_by_name[anchors[alias]]
		_anchored_names[anchors[alias]] = true
	_strata_layouts[strata["prefix"]] = layout


func _create_strata_tunnels(
	level: MineLevel, parent: Node3D, strata: Dictionary, creature_min_width: float
) -> void:
	var layout: Dictionary = _strata_layouts[strata["prefix"]]

	for bore: Dictionary in layout["bores"] as Array:
		var bore_tags: Array = (strata.get("bore_tags", []) as Array).duplicate()
		if bore["width"] < creature_min_width:
			bore_tags.append("refuge")
		_add_tunnel(level, parent, _tagged(bore, bore_tags))

	for breach: Dictionary in layout["breaches"] as Array:
		var breach_tags: Array = (strata.get("breach_tags", []) as Array).duplicate()
		if breach["merged"]:
			breach_tags.append("merged")
		_add_tunnel(level, parent, _tagged(breach, breach_tags))

	for link: Dictionary in layout["long_links"] as Array:
		_add_tunnel(level, parent, _tagged(link, strata.get("long_link_tags", [])))

	# Printed because it is the one thing you re-roll the seed over and the one
	# thing no other report shows: a stack whose strata never reach each other is
	# the flat stack this replaced, and it looks perfectly healthy in every count.
	print(
		(
			"  %d breaches between strata, %d of them where the two merge"
			% [(layout["breaches"] as Array).size(), layout["merges"]]
		)
	)
	_mark_dead_ends(layout["arrivals"])


## A chamber with one way in is a pocket, and saying so is most of what makes the
## colour coding worth reading.
##
## Anchored chambers are skipped: the free-form tunnels that reach them are added
## after this runs, so their real arrival count is not known here.
func _mark_dead_ends(arrivals: Dictionary) -> void:
	for space_name: String in arrivals:
		if arrivals[space_name] != 1 or _anchored_names.has(space_name):
			continue
		var space: MineSpace = _spaces_by_name.get(space_name)
		if space != null:
			space.kind = LevelGraph.SpaceKind.DEAD_END


## A layout record as a tunnel entry. The layout works in numbers and leaves the
## labelling to whoever knows the level's creature width.
func _tagged(record: Dictionary, tags: Array) -> Dictionary:
	var entry := record.duplicate()
	entry["tags"] = tags
	return entry


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
