extends SceneTree

## Scaffolds levels/design/level_asteroid_blockout.tscn: the central cavern and
## the mines biome, from the spec below.
##
## THE SCENE IS THE SOURCE OF TRUTH ONCE THIS HAS RUN. This exists so fifty-odd
## tunnels do not have to be placed by hand, not to keep a second copy in step.
## It refuses to overwrite an existing scene without `-- --force`.
##
## THE MINES ARE A SURVEYED GRID, WHICH IS WHY x AND z ARE EXACT AND y IS NOT.
## Drifts and cross-cuts were dug straight and square by people with instruments,
## so they line up in plan. They follow the ore seam in section, so they rise and
## fall - which is what stops the biome reading as one flat floor and is the main
## reason it is disorienting despite being the legible biome.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/build_asteroid_blockout.gd

const OUTPUT_PATH := "res://levels/design/level_asteroid_blockout.tscn"

## Twice the chase prototype's probe comfort. Anything under this is a refuge.
const CREATURE_MIN_WIDTH := 6.4

#region Mines - upper level
#
# Four columns of cross-cuts crossing three drifts. The drifts run east toward
# the cavern; the cross-cuts run north-south between them. Every crossing is a
# junction, and the whole thing sags eastward and southward as the seam dips.

const LEVEL_A := {
	"prefix": "a",
	"columns": ["c1", "c2", "c3", "c4"],
	"rows": ["n", "m", "s"],
	"column_x": {"c1": -150.0, "c2": -115.0, "c3": -80.0, "c4": -45.0},
	"row_z": {"n": -45.0, "m": 0.0, "s": 45.0},
	"node_y":
	{
		"c1_n": -47.0,
		"c1_m": -52.0,
		"c1_s": -58.0,
		"c2_n": -51.0,
		"c2_m": -54.0,
		"c2_s": -62.0,
		"c3_n": -49.0,
		"c3_m": -58.0,
		"c3_s": -67.0,
		"c4_n": -57.0,
		"c4_m": -62.0,
		"c4_s": -68.0,
	},
	"drift_width": 9.0,
	"strip_width": 7.0,
	# Cross-cuts too tight for the creature. Three of them, so ducking sideways
	# is something you have to have remembered rather than something always to hand.
	"narrow_strips": {"c2_ms": 4.5, "c4_nm": 4.5},
	"omitted_strips": [],
	"omitted_drifts": [],
}
#endregion

#region Mines - lower level
#
# Wider spacing and a missing cross-cut, so the lower workings do not read as a
# copy of the upper ones. Its rows sit directly under the upper level's, which is
# what lets the winzes be genuinely vertical.

const LEVEL_B := {
	"prefix": "b",
	"columns": ["c1", "c2", "c3"],
	"rows": ["n", "m", "s"],
	"column_x": {"c1": -150.0, "c2": -115.0, "c3": -45.0},
	"row_z": {"n": -45.0, "m": 0.0, "s": 45.0},
	"node_y":
	{
		"c1_n": -104.0,
		"c1_m": -108.0,
		"c1_s": -115.0,
		"c2_n": -110.0,
		"c2_m": -113.0,
		"c2_s": -119.0,
		"c3_n": -118.0,
		"c3_m": -122.0,
		"c3_s": -126.0,
	},
	"drift_width": 9.0,
	"strip_width": 7.0,
	"narrow_strips": {"c1_nm": 4.5},
	# The north end of the cavern-side column is only reachable the long way
	# round, or by dropping through the deep fork.
	"omitted_strips": ["c3_nm"],
	"omitted_drifts": [],
}
#endregion

#region Chamber sizes

const DRIFT_JUNCTION_RADIUS := 5.0
const STRIP_JUNCTION_RADIUS := 3.5
const NATURAL_FORK_RADIUS := 5.0
#endregion

#region Spaces outside the grids

const EXTRA_SPACES := [
	{
		"name": "mine_mouth",
		"position": Vector3(-185, -12, 0),
		"radius": 7.0,
		"kind": "room",
		"tags": ["entrance"],
		"notes": "Where the elevator lands. The run starts and has to end here.",
	},
	{
		"name": "cavern_ceiling",
		"position": Vector3(0, -28, 0),
		"radius": 14.0,
		"kind": "room",
		"tags": ["cavern"],
		"notes":
		"Roof of the central cavern. Nothing joins it yet - held for whatever comes in from above.",
	},
	{
		"name": "cavern_upper",
		"position": Vector3(0, -62, 0),
		"radius": 20.0,
		"kind": "junction",
		"tags": ["cavern"],
		"notes":
		"Where the upper mines meet the cavern. Level with the c4 drift, so you walk out of a square tunnel into open space with no transition.",
	},
	{
		"name": "cavern_lower",
		"position": Vector3(0, -122, 0),
		"radius": 22.0,
		"kind": "junction",
		"tags": ["cavern"],
		"notes": "Where the lower mines meet the cavern.",
	},
	{
		"name": "cavern_floor",
		"position": Vector3(0, -180, 0),
		"radius": 25.0,
		"kind": "room",
		"tags": ["cavern"],
		"notes": "Bottom of the cavern. Held for the route on to the hive.",
	},
	{
		"name": "fork_south",
		"position": Vector3(-25, -78, 62),
		"radius": NATURAL_FORK_RADIUS,
		"kind": "junction",
		"tags": ["natural"],
		"notes":
		"A natural cavity where a solution tunnel splits: one way into the cavern, one way around it toward the ravine. Getting this wrong is how you leave the biome without meaning to.",
	},
	{
		"name": "fork_deep",
		"position": Vector3(-30, -138, -55),
		"radius": NATURAL_FORK_RADIUS,
		"kind": "junction",
		"tags": ["natural"],
		"notes":
		"The lower equivalent of fork_south, splitting toward the cavern and toward the hive.",
	},
	{
		"name": "link_ravine",
		"position": Vector3(55, -92, 125),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes":
		"Stub. Where the mines hand over to the ravine, routed wide of the cavern so this is a way between biomes that never passes through the middle.",
	},
	{
		"name": "link_hive",
		"position": Vector3(20, -195, -110),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the mines hand over to the hive, again clear of the cavern.",
	},
]
#endregion

#region Tunnels outside the grids
#
# `bends` are the corners the tunnel runs through. A square-cut mine tunnel has
# none; the natural ones are nothing but.

const EXTRA_TUNNELS := [
	{
		"name": "entrance_shaft",
		"from": "mine_mouth",
		"to": "a_c1_m",
		"width": 10.0,
		"bends": [Vector3(-178, -26, -4), Vector3(-166, -40, 4)],
		"tags": ["drift", "entrance"],
		"notes":
		"The incline down from the elevator. Widest thing in the biome, and the only route you can be sure of on the way out.",
	},
	{
		"name": "mines_a_portal",
		"from": "a_c4_m",
		"to": "cavern_upper",
		"width": 9.0,
		"bends": [],
		"tags": ["drift", "cavern_link"],
		"notes": "The upper mines' front door onto the cavern.",
	},
	{
		"name": "mines_b_portal",
		"from": "b_c3_m",
		"to": "cavern_lower",
		"width": 9.0,
		"bends": [],
		"tags": ["drift", "cavern_link"],
		"notes": "The lower mines' front door onto the cavern.",
	},
	{
		"name": "cavern_shaft_upper",
		"from": "cavern_ceiling",
		"to": "cavern_upper",
		"width": 30.0,
		"bends": [],
		"tags": ["cavern"],
	},
	{
		"name": "cavern_shaft_mid",
		"from": "cavern_upper",
		"to": "cavern_lower",
		"width": 30.0,
		"bends": [],
		"tags": ["cavern"],
		"notes":
		"Sixty metres of open vertical space joining the two mine levels. Fast, completely exposed, and it carries sound between levels that the rock otherwise separates.",
	},
	{
		"name": "cavern_shaft_lower",
		"from": "cavern_lower",
		"to": "cavern_floor",
		"width": 30.0,
		"bends": [],
		"tags": ["cavern"],
	},
	{
		"name": "winze_deep",
		"from": "a_c1_m",
		"to": "b_c1_m",
		"width": 7.0,
		"bends": [],
		"tags": ["winze"],
		"notes":
		"The far winze, right where the entrance incline arrives. Drops you a level before you have got your bearings on this one.",
	},
	{
		"name": "winze_north",
		"from": "a_c2_n",
		"to": "b_c2_n",
		"width": 7.0,
		"bends": [],
		"tags": ["winze"],
	},
	{
		"name": "winze_south",
		"from": "a_c4_s",
		"to": "b_c3_s",
		"width": 5.0,
		"bends": [],
		"tags": ["winze", "refuge"],
		"notes": "Too tight for the creature. The only way to change level while being chased.",
	},
	{
		"name": "nat_a_far",
		"from": "a_c1_s",
		"to": "a_c2_m",
		"width": 5.0,
		"bends": [Vector3(-140, -63, 30), Vector3(-128, -59, 14)],
		"tags": ["natural", "refuge"],
		"notes":
		"The one natural tunnel out at the far end. Rare enough this far from the cavern that finding it should feel like a discovery.",
	},
	{
		"name": "nat_a_mid_north",
		"from": "a_c2_n",
		"to": "a_c3_m",
		"width": 6.0,
		"bends": [Vector3(-105, -48, -30), Vector3(-92, -52, -12)],
		"tags": ["natural", "refuge"],
	},
	{
		"name": "nat_a_mid_south",
		"from": "a_c2_s",
		"to": "a_c3_n",
		"width": 6.8,
		"bends": [Vector3(-108, -58, 30), Vector3(-95, -52, -8), Vector3(-86, -50, -28)],
		"tags": ["natural"],
		"notes":
		"Cuts clean across two drifts and a cross-cut without touching either. Ends up a row north of where it started.",
	},
	{
		"name": "nat_a_near_north",
		"from": "a_c3_n",
		"to": "a_c4_m",
		"width": 7.0,
		"bends": [Vector3(-70, -52, -30), Vector3(-56, -57, -14)],
		"tags": ["natural"],
	},
	{
		"name": "nat_a_near_cross",
		"from": "a_c3_m",
		"to": "a_c4_n",
		"width": 6.6,
		"bends": [Vector3(-70, -56, -12), Vector3(-57, -55, -32)],
		"tags": ["natural"],
	},
	{
		"name": "nat_a_near_south",
		"from": "a_c3_s",
		"to": "a_c4_m",
		"width": 5.8,
		"bends": [Vector3(-68, -66, 32), Vector3(-55, -64, 14)],
		"tags": ["natural", "refuge"],
	},
	{
		"name": "nat_b_west",
		"from": "b_c1_n",
		"to": "b_c2_m",
		"width": 6.2,
		"bends": [Vector3(-140, -106, -30), Vector3(-127, -110, -14)],
		"tags": ["natural", "refuge"],
	},
	{
		"name": "nat_b_cross",
		"from": "b_c1_s",
		"to": "b_c2_n",
		"width": 7.0,
		"bends": [Vector3(-142, -114, 30), Vector3(-128, -110, -10), Vector3(-120, -110, -32)],
		"tags": ["natural"],
	},
	{
		"name": "nat_b_east",
		"from": "b_c2_s",
		"to": "b_c3_m",
		"width": 6.8,
		"bends": [Vector3(-100, -121, 32), Vector3(-75, -124, 18), Vector3(-58, -123, 6)],
		"tags": ["natural"],
	},
	{
		"name": "nat_drop_south",
		"from": "a_c3_s",
		"to": "b_c2_s",
		"width": 5.5,
		"bends": [Vector3(-88, -80, 50), Vector3(-100, -98, 52), Vector3(-110, -110, 48)],
		"tags": ["natural", "refuge", "level_link"],
		"notes":
		"A natural drop between levels that is not a winze and is not on the survey. Going down it puts you a level lower and two columns west of where you think you are.",
	},
	{
		"name": "nat_drop_mid",
		"from": "a_c3_m",
		"to": "b_c2_n",
		"width": 6.5,
		"bends": [Vector3(-88, -72, -10), Vector3(-98, -90, -28), Vector3(-108, -102, -40)],
		"tags": ["natural", "level_link"],
	},
	{
		"name": "nat_fork_south_in",
		"from": "a_c4_s",
		"to": "fork_south",
		"width": 6.2,
		"bends": [Vector3(-38, -72, 54)],
		"tags": ["natural", "refuge"],
	},
	{
		"name": "nat_fork_south_cavern",
		"from": "fork_south",
		"to": "cavern_upper",
		"width": 6.0,
		"bends": [Vector3(-16, -72, 42), Vector3(-8, -66, 20)],
		"tags": ["natural", "refuge", "cavern_link"],
		"notes": "A back way into the cavern the creature cannot use.",
	},
	{
		"name": "link_to_ravine",
		"from": "fork_south",
		"to": "link_ravine",
		"width": 6.8,
		"bends": [Vector3(0, -84, 95), Vector3(30, -90, 112)],
		"tags": ["natural", "biome_link"],
		"notes":
		"Swings wide of the cavern on the south side. Take this instead of the fork's other branch and you are in the ravine without having crossed the middle of the map.",
	},
	{
		"name": "nat_fork_deep_in",
		"from": "b_c3_n",
		"to": "fork_deep",
		"width": 6.4,
		"bends": [Vector3(-40, -128, -50)],
		"tags": ["natural"],
	},
	{
		"name": "nat_fork_deep_cavern",
		"from": "fork_deep",
		"to": "cavern_lower",
		"width": 5.6,
		"bends": [Vector3(-20, -132, -38), Vector3(-9, -126, -18)],
		"tags": ["natural", "refuge", "cavern_link"],
	},
	{
		"name": "link_to_hive",
		"from": "fork_deep",
		"to": "link_hive",
		"width": 7.0,
		"bends": [Vector3(-16, -158, -84), Vector3(0, -178, -98)],
		"tags": ["natural", "biome_link"],
		"notes": "Runs down the north side, clear of the cavern floor.",
	},
]
#endregion

const TAG_COLORS := {
	&"drift": Color(0.35, 0.62, 1.0),
	&"strip": Color(0.55, 0.78, 0.95),
	&"natural": Color(0.95, 0.62, 0.25),
	&"winze": Color(0.85, 0.35, 0.9),
	&"cavern": Color(0.45, 0.95, 0.75),
	&"biome_link": Color(1.0, 0.85, 0.2),
	&"refuge": Color(0.3, 0.9, 0.5),
	&"entrance": Color(0.95, 0.95, 0.5),
	&"unbuilt": Color(0.5, 0.5, 0.55),
}

var _spaces_by_name: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if FileAccess.file_exists(OUTPUT_PATH) and not "--force" in OS.get_cmdline_user_args():
		printerr(
			(
				(
					"%s already exists. This scaffold overwrites the design; "
					+ "re-run with `-- --force` if that is what you want."
				)
				% OUTPUT_PATH
			)
		)
		quit(1)
		return

	var level := _build_level()
	root.add_child(level)

	var packed := PackedScene.new()
	var pack_result := packed.pack(level)
	if pack_result != OK:
		printerr("Could not pack the level scene: error %d" % pack_result)
		quit(1)
		return
	var save_result := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_result != OK:
		printerr("Could not save %s: error %d" % [OUTPUT_PATH, save_result])
		quit(1)
		return

	_report(level)
	level.free()
	quit(0)


func _build_level() -> MineLevel:
	var level := MineLevel.new()
	level.name = "AsteroidBlockout"
	level.creature_min_width = CREATURE_MIN_WIDTH
	level.color_mode = MineLevel.ColorMode.TAG
	var colors: Dictionary[StringName, Color] = {}
	for tag: StringName in TAG_COLORS:
		colors[tag] = TAG_COLORS[tag]
	level.tag_colors = colors

	var space_root := Node3D.new()
	space_root.name = "Spaces"
	level.add_child(space_root)
	space_root.owner = level

	var tunnel_root := Node3D.new()
	tunnel_root.name = "Tunnels"
	level.add_child(tunnel_root)
	tunnel_root.owner = level

	for entry: Dictionary in EXTRA_SPACES:
		var space := _make_space(
			entry["name"],
			entry["position"],
			entry["radius"],
			_kind_from_text(entry["kind"]),
			_to_tags(entry["tags"]),
			entry.get("notes", "")
		)
		space_root.add_child(space)
		space.owner = level

	for grid: Dictionary in [LEVEL_A, LEVEL_B]:
		_create_grid_spaces(level, space_root, grid)
	for grid: Dictionary in [LEVEL_A, LEVEL_B]:
		_create_grid_tunnels(level, tunnel_root, grid)
	_create_extra_tunnels(level, tunnel_root)

	level.entrance_space = level.get_path_to(_spaces_by_name["mine_mouth"])
	level.sound_origin = level.get_path_to(_spaces_by_name["a_c3_m"])
	return level


## One space per crossing. A crossing of two drifts is a wider junction than a
## crossing that only a cross-cut passes through, which is what the two radii say.
func _create_grid_spaces(level: MineLevel, parent: Node3D, grid: Dictionary) -> void:
	var prefix: String = grid["prefix"]
	for column: String in grid["columns"]:
		for row: String in grid["rows"]:
			var key := "%s_%s" % [column, row]
			var position := Vector3(
				grid["column_x"][column], grid["node_y"][key], grid["row_z"][row]
			)
			var radius := DRIFT_JUNCTION_RADIUS if row == "m" else STRIP_JUNCTION_RADIUS
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
func _create_grid_tunnels(level: MineLevel, parent: Node3D, grid: Dictionary) -> void:
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
			if width < CREATURE_MIN_WIDTH:
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


func _create_extra_tunnels(level: MineLevel, parent: Node3D) -> void:
	for entry: Dictionary in EXTRA_TUNNELS:
		_add_tunnel(level, parent, entry)


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


func _report(level: MineLevel) -> void:
	var graph := level.build_graph()
	print("Wrote %s" % OUTPUT_PATH)
	print("  %d spaces, %d tunnels" % [graph.spaces.size(), graph.tunnels.size()])
	print("  %.0f m of centreline" % graph.total_length())
	var passable := graph.passable_tunnel_ids(CREATURE_MIN_WIDTH).size()
	print("  creature fits down %d, blocked from %d" % [passable, graph.tunnels.size() - passable])
	var problems := level.validate()
	if problems.is_empty():
		print("  validate: clean")
	else:
		for problem: String in problems:
			printerr("  %s" % problem)
