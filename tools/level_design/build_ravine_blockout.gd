extends SceneTree

## The ravine biome, as data. BlockoutScaffold does the building.
##
## ONE LONG CHASM, TALL AND THIN, WITH WINDING TUNNELS OFF ITS SIDES. The chasm
## is a chain of stations rather than a single space, so where you are along it
## is something the graph can answer and sound has somewhere to decay over.
##
## IT IS NOT QUITE STRAIGHT, ON PURPOSE. The stations drift up to 10 m either side
## of the axis and the floor falls as it runs. That is enough to break the
## sightline end to end without ever making it feel like a bend - you always think
## you can see the far end, and you never can. Station spacing stays around 44 m,
## so the chasm is no more crooked per metre than it was at twice the length.
##
## EVERY STATION HAS A TUNNEL OFF BOTH WALLS. Side tunnels clustered on one wall
## at a time give the chasm a handedness, and a handedness is a landmark: you
## always know which way you are facing. Both walls everywhere takes that away,
## and that is what makes the biome disorienting rather than merely long.
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
# Six stations over 220 m, running roughly north-south and falling 30 m.

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
			"position": Vector3(6, -34, -110),
			"radius": 9.0,
			"kind": "room",
			"notes":
			"Blind north end. The only part of the ravine with a wall you can put your back to.",
		},
		{"name": "s1", "position": Vector3(-9, -40, -66), "radius": 7.0},
		{"name": "s2", "position": Vector3(8, -46, -22), "radius": 7.0},
		{"name": "s3", "position": Vector3(-10, -52, 22), "radius": 7.0},
		{"name": "s4", "position": Vector3(7, -58, 66), "radius": 7.0},
		{
			"name": "south_end",
			"position": Vector3(-8, -64, 110),
			"radius": 9.0,
			"kind": "room",
			"notes": "Where the floor of the chasm finally closes. Deepest point in the biome.",
		},
	],
}
#endregion

#region Rooms and junctions off the sides
#
# Two knots and two pockets on each wall, so no station is more than one tunnel
# from something on either side. `knot` is where side tunnels meet; `pocket` is a
# room worth the trip in.

const EXTRA_SPACES := [
	{
		"name": "knot_west_a",
		"position": Vector3(-48, -40, -88),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
		"notes": "Three tunnels meet here and none of them looks like the way back.",
	},
	{
		"name": "knot_west_b",
		"position": Vector3(-46, -56, 44),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
	},
	{
		"name": "knot_east_a",
		"position": Vector3(46, -44, -44),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
	},
	{
		"name": "knot_east_b",
		"position": Vector3(44, -60, 64),
		"radius": 4.5,
		"kind": "junction",
		"tags": ["ravine", "warren"],
	},
	{
		"name": "pocket_west_a",
		"position": Vector3(-72, -44, -50),
		"radius": 6.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
		"notes": "Big enough to stop in and small enough to be cornered in.",
	},
	{
		"name": "pocket_west_b",
		"position": Vector3(-70, -62, 86),
		"radius": 5.5,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "pocket_east_a",
		"position": Vector3(70, -48, -84),
		"radius": 5.5,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "pocket_east_b",
		"position": Vector3(68, -66, 100),
		"radius": 6.0,
		"kind": "room",
		"tags": ["ravine", "pocket"],
	},
	{
		"name": "link_mines",
		"position": Vector3(-104, -40, -74),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the ravine hands over to the mines.",
	},
	{
		"name": "link_hive",
		"position": Vector3(96, -74, 128),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the ravine hands over to the hive.",
	},
]
#endregion

#region Side tunnels
#
# TWELVE OF THEM, TWO PER STATION, ONE EACH WAY. At no point in the chasm is
# there a wall with nothing in it, so which wall you are looking at tells you
# nothing about where you are.
#
# `bends` as a NUMBER means the scaffold generates that many corners, straying by
# `wander` metres, from `seed`. Same seed, same tunnel, every run. Typing three
# corners each for eighteen tunnels would be a page of coordinates nobody would
# ever tune.
#
# Widths hover around the 6.4 m the creature needs, so which of these is a refuge
# and which is a trap is the question the whole side network is asking.

const SIDE_TUNNELS := [
	# North end, both walls.
	{
		"name": "side_north_west",
		"from": "rv_north_end",
		"to": "knot_west_a",
		"width": 5.5,
		"bends": 3,
		"wander": 11.0,
		"seed": 101,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_north_east",
		"from": "rv_north_end",
		"to": "pocket_east_a",
		"width": 7.0,
		"bends": 4,
		"wander": 13.0,
		"seed": 102,
		"tags": ["ravine", "winding"],
	},
	# s1, both walls.
	{
		"name": "side_s1_west",
		"from": "rv_s1",
		"to": "knot_west_a",
		"width": 7.2,
		"bends": 3,
		"wander": 10.0,
		"seed": 103,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_s1_east",
		"from": "rv_s1",
		"to": "pocket_east_a",
		"width": 4.8,
		"bends": 3,
		"wander": 10.0,
		"seed": 104,
		"tags": ["ravine", "winding", "refuge"],
	},
	# s2, both walls.
	{
		"name": "side_s2_west",
		"from": "rv_s2",
		"to": "pocket_west_a",
		"width": 6.8,
		"bends": 3,
		"wander": 12.0,
		"seed": 105,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_s2_east",
		"from": "rv_s2",
		"to": "knot_east_a",
		"width": 7.5,
		"bends": 3,
		"wander": 12.0,
		"seed": 106,
		"tags": ["ravine", "winding"],
	},
	# s3, both walls.
	{
		"name": "side_s3_west",
		"from": "rv_s3",
		"to": "knot_west_b",
		"width": 6.0,
		"bends": 3,
		"wander": 11.0,
		"seed": 107,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_s3_east",
		"from": "rv_s3",
		"to": "knot_east_a",
		"width": 5.0,
		"bends": 4,
		"wander": 13.0,
		"seed": 108,
		"tags": ["ravine", "winding", "refuge"],
		"notes":
		"Runs 70 m back north behind the east wall. Comes out well short of where it went in, which is how you lose a hundred metres without ever turning round.",
	},
	# s4, both walls.
	{
		"name": "side_s4_west",
		"from": "rv_s4",
		"to": "knot_west_b",
		"width": 7.0,
		"bends": 3,
		"wander": 12.0,
		"seed": 109,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "side_s4_east",
		"from": "rv_s4",
		"to": "knot_east_b",
		"width": 6.9,
		"bends": 2,
		"wander": 10.0,
		"seed": 110,
		"tags": ["ravine", "winding"],
	},
	# South end, both walls.
	{
		"name": "side_south_west",
		"from": "rv_south_end",
		"to": "pocket_west_b",
		"width": 5.2,
		"bends": 3,
		"wander": 12.0,
		"seed": 111,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "side_south_east",
		"from": "rv_south_end",
		"to": "knot_east_b",
		"width": 6.5,
		"bends": 2,
		"wander": 9.0,
		"seed": 112,
		"tags": ["ravine", "winding"],
	},
	# Knots out to their pockets.
	{
		"name": "west_a_pocket",
		"from": "knot_west_a",
		"to": "pocket_west_a",
		"width": 4.5,
		"bends": 3,
		"wander": 10.0,
		"seed": 113,
		"tags": ["ravine", "winding", "refuge"],
	},
	{
		"name": "west_b_pocket",
		"from": "knot_west_b",
		"to": "pocket_west_b",
		"width": 6.6,
		"bends": 3,
		"wander": 11.0,
		"seed": 114,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "east_a_pocket",
		"from": "knot_east_a",
		"to": "pocket_east_a",
		"width": 6.4,
		"bends": 3,
		"wander": 11.0,
		"seed": 115,
		"tags": ["ravine", "winding"],
	},
	{
		"name": "east_b_pocket",
		"from": "knot_east_b",
		"to": "pocket_east_b",
		"width": 5.4,
		"bends": 3,
		"wander": 10.0,
		"seed": 116,
		"tags": ["ravine", "winding", "refuge"],
	},
	# Out of the biome, one from each wall.
	{
		"name": "link_to_mines",
		"from": "pocket_west_a",
		"to": "link_mines",
		"width": 6.8,
		"bends": 3,
		"wander": 10.0,
		"seed": 117,
		"tags": ["biome_link", "winding"],
	},
	{
		"name": "link_to_hive",
		"from": "pocket_east_b",
		"to": "link_hive",
		"width": 7.0,
		"bends": 3,
		"wander": 10.0,
		"seed": 118,
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
	"sound_origin": "rv_s2",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Scaffold.new().run(self, SPEC)
