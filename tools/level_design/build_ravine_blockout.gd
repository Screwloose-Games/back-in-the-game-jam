extends SceneTree

## The ravine biome, as data. BlockoutScaffold does the building.
##
## ONE LONG CHASM, TALL AND THIN, WITH WINDING TUNNELS OFF ITS SIDES. The chasm
## is a chain of stations rather than a single space, so where you are along it
## is something the graph can answer and sound has somewhere to decay over.
##
## IT IS NOT QUITE STRAIGHT, ON PURPOSE. The stations drift by up to 14 m either
## side of the axis and the floor falls as it runs. That is enough to break the
## sightline end to end without ever making it feel like a bend - you always
## think you can see the far end, and you never can.
##
## Nothing here joins the mines or the hive. The two `link_*` stubs mark where it
## would, and are deliberately not wired to a central cavern: how the biomes
## connect is still open.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/build_ravine_blockout.gd

## tools/ carries a .gdignore, so nothing under it registers a global class name.
const Scaffold := preload("res://tools/level_design/blockout_scaffold.gd")

## Matches the mines. Anything under this is a refuge.
const CREATURE_MIN_WIDTH := 6.4

#region The chasm
#
# Runs roughly north-south, 430 m of it, falling 60 m as it goes. The x drift is
# the sightline breaker; the z spacing is even because the chasm was not dug, it
# opened.

const CHASM := {
	"prefix": "rv",
	"station_tags": ["ravine", "chasm"],
	# Tall and thin: you can see the roof and the floor is a long way down, and
	# both walls are close enough to touch on a bad line.
	"width": 12.0,
	"height": 48.0,
	"tags": ["ravine", "chasm"],
	"notes": "The chasm itself. Wide open vertically, close on both sides.",
	"stations":
	[
		{
			"name": "north_end",
			"position": Vector3(6, -34, -215),
			"radius": 9.0,
			"kind": "room",
			"notes":
			"Blind north end. The only part of the ravine with a wall you can put your back to.",
		},
		{"name": "s1", "position": Vector3(-8, -41, -160), "radius": 7.0},
		{"name": "s2", "position": Vector3(9, -48, -105), "radius": 7.0},
		{"name": "s3", "position": Vector3(-11, -54, -50), "radius": 7.0},
		{
			"name": "s4",
			"position": Vector3(4, -61, 5),
			"radius": 8.0,
			"notes": "Middle of the run, and the only station both ends are invisible from.",
		},
		{"name": "s5", "position": Vector3(-13, -68, 60), "radius": 7.0},
		{"name": "s6", "position": Vector3(7, -76, 115), "radius": 7.0},
		{"name": "s7", "position": Vector3(-6, -84, 170), "radius": 7.0},
		{
			"name": "south_end",
			"position": Vector3(10, -94, 222),
			"radius": 9.0,
			"kind": "room",
			"notes": "Where the floor of the chasm finally closes. Deepest point in the biome.",
		},
	],
}
#endregion

#region Rooms and junctions off the sides
#
# `pocket` is a dead end worth the trip in. `knot` is where two or three side
# tunnels meet, which is what makes the sides a network rather than a comb.

const EXTRA_SPACES := [
	{
		"name": "link_mines",
		"position": Vector3(-96, -30, -238),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the ravine hands over to the mines.",
	},
	{
		"name": "link_hive",
		"position": Vector3(72, -112, 246),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the ravine hands over to the hive.",
	},
	{
		"name": "knot_north",
		"position": Vector3(-52, -44, -150),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
		"notes": "Three tunnels meet here and none of them looks like the way back.",
	},
	{
		"name": "knot_mid",
		"position": Vector3(48, -58, -18),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
	},
	{
		"name": "knot_deep",
		"position": Vector3(-44, -80, 128),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
	},
	{
		"name": "pocket_north",
		"position": Vector3(-78, -38, -186),
		"radius": 6.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
		"notes": "Big enough to stop in and small enough to be cornered in.",
	},
	{
		"name": "pocket_west",
		"position": Vector3(-70, -50, -96),
		"radius": 5.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "pocket_east",
		"position": Vector3(66, -64, 42),
		"radius": 5.5,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "pocket_deep",
		"position": Vector3(-66, -90, 178),
		"radius": 5.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "pocket_south",
		"position": Vector3(52, -96, 208),
		"radius": 6.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
]
#endregion

#region Side tunnels
#
# `bends` as a NUMBER means the scaffold generates that many corners, straying by
# `wander` metres, from `seed`. Same seed, same tunnel, every run. Typing three
# corners each for twenty tunnels would be a page of coordinates nobody would
# ever tune.
#
# Widths hover around the 6.4 m the creature needs, so which of these is a refuge
# and which is a trap is the question the whole side network is asking.

const SIDE_TUNNELS = [
	# North group: chasm out to the knot, on to pockets, and back to the chasm.
	{
		"name": "side_north_in",
		"from": "rv_s1",
		"to": "knot_north",
		"width": 5.5,
		"bends": 3,
		"wander": 11.0,
		"seed": 101,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_north_pocket",
		"from": "knot_north",
		"to": "pocket_north",
		"width": 4.5,
		"bends": 3,
		"wander": 10.0,
		"seed": 102,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_north_return",
		"from": "knot_north",
		"to": "rv_north_end",
		"width": 7.0,
		"bends": 4,
		"wander": 14.0,
		"seed": 103,
		"tags": ["ravine", "winding"],
		"notes":
		"Rejoins the chasm 55 m north of where it left. Easy to take twice without noticing.",
	},
	{
		"name": "side_west_pocket",
		"from": "knot_north",
		"to": "pocket_west",
		"width": 6.8,
		"bends": 3,
		"wander": 12.0,
		"seed": 104,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_west_return",
		"from": "pocket_west",
		"to": "rv_s2",
		"width": 7.2,
		"bends": 2,
		"wander": 9.0,
		"seed": 105,
		"tags": ["ravine", "winding"],
	},
	# Middle group, on the east side.
	{
		"name": "side_mid_in",
		"from": "rv_s3",
		"to": "knot_mid",
		"width": 7.5,
		"bends": 3,
		"wander": 13.0,
		"seed": 106,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_mid_return",
		"from": "knot_mid",
		"to": "rv_s4",
		"width": 6.0,
		"bends": 3,
		"wander": 11.0,
		"seed": 107,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_mid_pocket",
		"from": "knot_mid",
		"to": "pocket_east",
		"width": 5.0,
		"bends": 4,
		"wander": 12.0,
		"seed": 108,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_east_long",
		"from": "pocket_east",
		"to": "rv_s6",
		"width": 6.6,
		"bends": 5,
		"wander": 16.0,
		"seed": 109,
		"tags": ["ravine", "winding"],
		"notes":
		"The long way round. Skips two stations, so it is the fast route if you know it and a disaster if you do not.",
	},
	# Deep group, west side.
	{
		"name": "side_deep_in",
		"from": "rv_s6",
		"to": "knot_deep",
		"width": 7.0,
		"bends": 3,
		"wander": 12.0,
		"seed": 110,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_deep_pocket",
		"from": "knot_deep",
		"to": "pocket_deep",
		"width": 4.8,
		"bends": 3,
		"wander": 11.0,
		"seed": 111,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_deep_return",
		"from": "knot_deep",
		"to": "rv_s7",
		"width": 6.9,
		"bends": 2,
		"wander": 10.0,
		"seed": 112,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_south_pocket",
		"from": "rv_s7",
		"to": "pocket_south",
		"width": 5.2,
		"bends": 3,
		"wander": 12.0,
		"seed": 113,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_south_return",
		"from": "pocket_south",
		"to": "rv_south_end",
		"width": 6.5,
		"bends": 2,
		"wander": 9.0,
		"seed": 114,
		"tags": ["ravine", "winding"],
	},
	# Out of the biome. Neither passes near the middle of the chasm.
	{
		"name": "link_to_mines",
		"from": "pocket_north",
		"to": "link_mines",
		"width": 6.8,
		"bends": 3,
		"wander": 10.0,
		"seed": 115,
		"tags": ["biome_link", "winding"],
	},
	{
		"name": "link_to_hive",
		"from": "pocket_south",
		"to": "link_hive",
		"width": 7.0,
		"bends": 3,
		"wander": 10.0,
		"seed": 116,
		"tags": ["biome_link", "winding"],
	},
]
#endregion

const TAG_COLORS := {
	&"chasm": Color(0.35, 0.72, 1.0),
	&"winding": Color(0.95, 0.62, 0.25),
	&"warren": Color(0.85, 0.35, 0.9),
	&"pocket": Color(0.45, 0.95, 0.75),
	&"biome_link": Color(1.0, 0.85, 0.2),
	&"refuge": Color(0.3, 0.9, 0.5),
	&"unbuilt": Color(0.5, 0.5, 0.55),
}

## Everything above, assembled for BlockoutScaffold.
const SPEC := {
	"output_path": "res://levels/design/level_ravine_blockout.tscn",
	"level_name": "RavineBlockout",
	"creature_min_width": CREATURE_MIN_WIDTH,
	"tag_colors": TAG_COLORS,
	"chains": [CHASM],
	"spaces": EXTRA_SPACES,
	"tunnels": SIDE_TUNNELS,
	"entrance": "rv_north_end",
	"sound_origin": "rv_s4",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Scaffold.new().run(self, SPEC)
