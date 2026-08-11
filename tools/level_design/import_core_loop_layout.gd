extends SceneTree

## Builds levels/design/level_mine_blockout.tscn from the core gameplay loop's
## hand-authored layout, once.
##
## AFTER THIS RUNS, THE SCENE IS THE SOURCE OF TRUTH. This script exists to avoid
## re-typing sixteen routes by hand, not to keep two copies in step. Re-running it
## overwrites whatever has been designed since, so it takes --force to do that.
##
## THE NUMBERS ARE COPIED IN RATHER THAN READ FROM CoreLoopKnobs, because that
## file lives on the unmerged core-gameplay-loop branch and a tool that only
## works on one branch is a tool that stops working. They are a snapshot of it as
## of the import, and the export script is how edits travel back the other way.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/import_core_loop_layout.gd

const OUTPUT_PATH := "res://levels/design/level_mine_blockout.tscn"

const WIDTH_TRUNK := 10.0
const WIDTH_CONNECTOR := 8.0
const WIDTH_REFUGE := 4.0

## The creature's minimum passable width: twice the chase prototype's probe
## comfort of 3.2 m.
const CREATURE_MIN_WIDTH := 6.4

const ENTRANCE := Vector3(0, -4, 0)
const HUB_ANTECHAMBER := Vector3(0, -30, 0)
const HUB_EAST := Vector3(60, -45, -20)
const HUB_WEST := Vector3(-55, -40, 25)
const HUB_DEEP := Vector3(70, -120, -40)
const CORE_CHAMBER := Vector3(30, -170, 20)

## The six named spaces the routes are anchored to. `radius` is the chamber cut
## there; the entrance has none, which is why it is zero rather than omitted.
const NAMED_SPACES := [
	{
		"name": "entrance",
		"position": ENTRANCE,
		"radius": 0.0,
		"kind": "room",
		"tags": ["entrance"],
		"notes":
		"The mine mouth. The elevator arrives here and this is what a run has to get back to.",
	},
	{
		"name": "hub_antechamber",
		"position": HUB_ANTECHAMBER,
		"radius": 7.5,
		"kind": "junction",
		"tags": ["hub"],
		"notes":
		"Foot of the entrance shaft. Five ways out, so the first real decision of a run is made here.",
	},
	{
		"name": "hub_east",
		"position": HUB_EAST,
		"radius": 7.5,
		"kind": "junction",
		"tags": ["hub"],
		"notes":
		"The upper loop rejoins here, so you can arrive from two directions and not be able to tell which.",
	},
	{
		"name": "hub_west",
		"position": HUB_WEST,
		"radius": 7.0,
		"kind": "junction",
		"tags": ["hub"],
		"notes": "The only junction where a trunk meets the squeeze.",
	},
	{
		"name": "hub_deep",
		"position": HUB_DEEP,
		"radius": 7.5,
		"kind": "junction",
		"tags": ["hub"],
		"notes": "120 m down. Reachable by trunk the long way or by the squeeze the short way.",
	},
	{
		"name": "core_chamber",
		"position": CORE_CHAMBER,
		"radius": 9.5,
		"kind": "room",
		"tags": ["core"],
		"notes": "The terminus. Deepest point, biggest chamber, worst place to be caught.",
	},
]

## Dead-end pockets, keyed by the coordinate the route that reaches them ends at.
const POCKETS := [
	{"position": Vector3(18, -20, 32), "radius": 4.5},
	{"position": Vector3(86, -46, 4), "radius": 4.5},
	{"position": Vector3(46, -70, -46), "radius": 4.5},
	{"position": Vector3(-83, -30, 48), "radius": 4.5},
	{"position": Vector3(86, -144, -62), "radius": 4.5},
	{"position": Vector3(44, -108, -70), "radius": 4.5},
	{"position": Vector3(2, -184, 42), "radius": 4.5},
	{"position": Vector3(-2, -36, -34), "radius": 2.8},
	{"position": Vector3(-64, -64, 2), "radius": 2.8},
]

## One entry becomes one MineTunnel. Interior points become MineBend children;
## the first and last must land on a named space or a pocket.
const ROUTES := [
	{
		"name": "entrance_shaft",
		"width": WIDTH_TRUNK,
		"points": [ENTRANCE, Vector3(4, -11, -3), Vector3(-3, -20, 2), HUB_ANTECHAMBER],
	},
	{
		"name": "east_trunk",
		"width": WIDTH_TRUNK,
		"points": [HUB_ANTECHAMBER, Vector3(22, -34, -12), Vector3(43, -36, -22), HUB_EAST],
	},
	{
		"name": "west_trunk",
		"width": WIDTH_TRUNK,
		"points": [HUB_ANTECHAMBER, Vector3(-20, -33, 10), Vector3(-40, -38, 20), HUB_WEST],
	},
	{
		"name": "deep_shaft",
		"width": WIDTH_TRUNK,
		"points": [HUB_EAST, Vector3(68, -70, -28), Vector3(74, -98, -36), HUB_DEEP],
	},
	{
		"name": "core_descent",
		"width": WIDTH_TRUNK,
		"points":
		[
			HUB_DEEP,
			Vector3(66, -133, -30),
			Vector3(58, -145, -18),
			Vector3(50, -153, -8),
			Vector3(42, -160, 2),
			Vector3(36, -166, 12),
			CORE_CHAMBER,
		],
		"notes":
		"Widened from a connector to a trunk so the deep branch stops baking as a navmesh island.",
	},
	{
		"name": "the_squeeze",
		"width": WIDTH_REFUGE,
		"points":
		[
			HUB_WEST,
			Vector3(-30, -62, 30),
			Vector3(0, -85, 18),
			Vector3(35, -100, -10),
			HUB_DEEP,
		],
		"notes":
		"The longest way of saying no. Closes the biggest loop in the level, and the creature cannot follow you down it.",
	},
	{
		"name": "upper_loop",
		"width": WIDTH_CONNECTOR,
		"points":
		[
			HUB_EAST,
			Vector3(40, -22, -5),
			Vector3(5, -18, 22),
			Vector3(-25, -26, 32),
			HUB_WEST,
		],
		"notes":
		"Routed high, so it re-enters hub_west facing the wrong way and the map stops being a tree you can hold in your head.",
	},
	{
		"name": "spur_ante_north",
		"width": WIDTH_REFUGE,
		"points": [HUB_ANTECHAMBER, Vector3(-6, -28, -18), Vector3(-2, -36, -34)],
	},
	{
		"name": "spur_ante_south",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_ANTECHAMBER, Vector3(12, -26, 16), Vector3(18, -20, 32)],
	},
	{
		"name": "spur_east_high",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_EAST, Vector3(76, -50, -8), Vector3(86, -46, 4)],
	},
	{
		"name": "spur_east_low",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_EAST, Vector3(52, -58, -34), Vector3(46, -70, -46)],
	},
	{
		"name": "spur_west_high",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_WEST, Vector3(-72, -34, 36), Vector3(-83, -30, 48)],
	},
	{
		"name": "spur_west_low",
		"width": WIDTH_REFUGE,
		"points": [HUB_WEST, Vector3(-60, -52, 12), Vector3(-64, -64, 2)],
	},
	{
		"name": "spur_deep_east",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_DEEP, Vector3(84, -132, -52), Vector3(86, -144, -62)],
	},
	{
		"name": "spur_deep_west",
		"width": WIDTH_CONNECTOR,
		"points": [HUB_DEEP, Vector3(56, -112, -56), Vector3(44, -108, -70)],
	},
	{
		"name": "spur_core",
		"width": WIDTH_CONNECTOR,
		"points": [CORE_CHAMBER, Vector3(14, -178, 32), Vector3(2, -184, 42)],
	},
]

## Routes the creature is meant to be unable to enter. Carried across as a tag so
## the intent survives even if someone later widens one by accident - the tag and
## the width disagreeing is a question worth being asked.
const REFUGE_ROUTES := ["the_squeeze", "spur_ante_north", "spur_west_low"]

## How close two coordinates must be to mean the same place.
const WELD_DISTANCE := 0.5

const TAG_COLORS := {
	&"hub": Color(0.35, 0.7, 1.0),
	&"entrance": Color(0.9, 0.9, 0.4),
	&"core": Color(1.0, 0.7, 0.1),
	&"pocket": Color(0.6, 0.5, 0.8),
	&"refuge": Color(0.3, 0.9, 0.5),
	&"trunk": Color(0.3, 0.55, 1.0),
	&"connector": Color(0.5, 0.8, 0.9),
}

var _spaces_by_name: Dictionary = {}


## The scene tree's root is not mounted yet when _initialize runs, and tunnel
## endpoints are read from global transforms, so the work waits one frame.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if FileAccess.file_exists(OUTPUT_PATH) and not "--force" in OS.get_cmdline_user_args():
		printerr(
			(
				(
					"%s already exists. This importer overwrites the design; "
					+ "re-run with `-- --force` if that is what you want."
				)
				% OUTPUT_PATH
			)
		)
		quit(1)
		return

	var level := _build_level()
	# Tunnel endpoints are read from the spaces' global transforms, which only
	# exist inside a tree, so the level has to be mounted before it can measure
	# itself. Visuals are unowned and are not packed either way.
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
	level.name = "MineLevel"
	level.creature_min_width = CREATURE_MIN_WIDTH
	level.color_mode = MineLevel.ColorMode.WIDTH
	var tag_colors: Dictionary[StringName, Color] = {}
	for tag: StringName in TAG_COLORS:
		tag_colors[tag] = TAG_COLORS[tag]
	level.tag_colors = tag_colors

	var space_root := Node3D.new()
	space_root.name = "Spaces"
	level.add_child(space_root)
	space_root.owner = level

	var tunnel_root := Node3D.new()
	tunnel_root.name = "Tunnels"
	level.add_child(tunnel_root)
	tunnel_root.owner = level

	_create_named_spaces(level, space_root)
	_create_pocket_spaces(level, space_root)
	_create_tunnels(level, tunnel_root)

	level.entrance_space = level.get_path_to(_spaces_by_name["entrance"])
	level.sound_origin = level.get_path_to(_spaces_by_name["core_chamber"])
	return level


func _create_named_spaces(level: MineLevel, parent: Node3D) -> void:
	for entry: Dictionary in NAMED_SPACES:
		var space := _make_space(
			entry["name"], entry["position"], entry["radius"], _kind_from_text(entry["kind"])
		)
		space.tags = _to_tags(entry["tags"])
		space.notes = entry.get("notes", "")
		parent.add_child(space)
		space.owner = level


## A pocket is named for the route that dead-ends in it, because "spur_west_low_end"
## says where it is and a coordinate does not.
func _create_pocket_spaces(level: MineLevel, parent: Node3D) -> void:
	for entry: Dictionary in POCKETS:
		var position: Vector3 = entry["position"]
		var route_name := _route_ending_at(position)
		if route_name.is_empty():
			printerr("Pocket at %v matches no route end; skipped." % position)
			continue
		var space := _make_space(
			"%s_end" % route_name, position, entry["radius"], LevelGraph.SpaceKind.DEAD_END
		)
		var tags: Array[StringName] = [&"pocket"]
		if route_name in REFUGE_ROUTES:
			tags.append(&"refuge")
		space.tags = tags
		parent.add_child(space)
		space.owner = level


func _create_tunnels(level: MineLevel, parent: Node3D) -> void:
	for route: Dictionary in ROUTES:
		var points: Array = route["points"]
		var from_space := _space_at(points[0])
		var to_space := _space_at(points[points.size() - 1])
		if from_space == null or to_space == null:
			printerr("Route '%s' has an end that matches no space; skipped." % route["name"])
			continue

		var tunnel := MineTunnel.new()
		tunnel.name = route["name"]
		tunnel.width = route["width"]
		tunnel.notes = route.get("notes", "")
		tunnel.tags = _tags_for_route(route)
		parent.add_child(tunnel)
		tunnel.owner = level
		tunnel.from_space = tunnel.get_path_to(from_space)
		tunnel.to_space = tunnel.get_path_to(to_space)

		for index: int in range(1, points.size() - 1):
			var bend := MineBend.new()
			bend.name = "bend_%d" % index
			bend.position = points[index]
			tunnel.add_child(bend)
			bend.owner = level


func _make_space(
	space_name: String, position: Vector3, radius: float, kind: LevelGraph.SpaceKind
) -> MineSpace:
	var space := MineSpace.new()
	space.name = space_name
	space.position = position
	space.radius = radius
	space.kind = kind
	_spaces_by_name[space_name] = space
	return space


func _tags_for_route(route: Dictionary) -> Array[StringName]:
	var tags: Array[StringName] = []
	if route["name"] in REFUGE_ROUTES:
		tags.append(&"refuge")
	elif float(route["width"]) >= WIDTH_TRUNK:
		tags.append(&"trunk")
	else:
		tags.append(&"connector")
	return tags


func _route_ending_at(position: Vector3) -> String:
	for route: Dictionary in ROUTES:
		var points: Array = route["points"]
		if (points[points.size() - 1] as Vector3).distance_to(position) <= WELD_DISTANCE:
			return route["name"]
	return ""


func _space_at(position: Vector3) -> MineSpace:
	for space_name: String in _spaces_by_name:
		var space: MineSpace = _spaces_by_name[space_name]
		if space.position.distance_to(position) <= WELD_DISTANCE:
			return space
	return null


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
	print("  %.1f m of centreline" % graph.total_length())
	print(
		(
			"  %d of %d tunnels passable at %.1f m"
			% [
				graph.passable_tunnel_ids(CREATURE_MIN_WIDTH).size(),
				graph.tunnels.size(),
				CREATURE_MIN_WIDTH,
			]
		)
	)
	var orphans := graph.unreachable_from(&"entrance")
	if orphans.is_empty():
		print("  every space reachable from the entrance")
	else:
		printerr("  UNREACHABLE: %s" % ", ".join(orphans))
