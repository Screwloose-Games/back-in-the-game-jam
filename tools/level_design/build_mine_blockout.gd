extends SceneTree

## The mines biome, as data. BlockoutScaffold does the building.
##
## THIS IS WHERE THE PLAYER STARTS, SO IT HAS TO TEACH THE MAP BEFORE IT USES IT.
## The whole biome is arranged as a difficulty ramp running east:
##
##   the adit      one straight tunnel, no choices at all
##   c1            still one tunnel. Nothing branches yet.
##   c2            the first branch: ONE cross-cut, perpendicular. A T.
##   c3            the second cross-cut closes a loop, so now there are + junctions
##   level b       the full two-by-three grid, reached only by a winze
##
## Every junction the player meets is therefore the simplest one they have not
## already learnt. An earlier version put four cross-cuts and three drifts in front
## of them at once and it read as noise.
##
## TWO DRIFTS, THREE CROSS-CUTS, TWO LEVELS, AND THAT IS THE MAXIMUM - reached
## only on the lower level. The upper level never has more than five workings.
##
## THE MINES ARE A SURVEYED GRID, WHICH IS WHY x AND z ARE EXACT AND y IS NOT.
## Drifts and cross-cuts were dug straight and square by people with instruments,
## so they line up in plan. They follow the ore seam in section, so they rise and
## fall - which is what stops the biome reading as one flat floor.
##
## NO CENTRAL CAVERN. How the three biomes join is still open, so the mines end at
## two `link_*` stubs and assume nothing.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/build_mine_blockout.gd

## tools/ carries a .gdignore, so nothing under it registers a global class name.
const Scaffold := preload("res://tools/level_design/blockout_scaffold.gd")

## Twice the chase prototype's probe comfort. Anything under this is a refuge.
const CREATURE_MIN_WIDTH := 6.4

#region Mines - upper level
#
# Two drifts running east, three cross-cut positions between them. `m` is the
# drift the player arrives in; `n` is the one they discover.
#
# c1_n IS DELIBERATELY NOT DUG. It is what makes the first stretch a corridor
# rather than a junction: there is nothing at c1 to turn off into, so the player
# flies straight until the map gives them one decision.

const LEVEL_A := {
	"prefix": "a",
	"columns": ["c1", "c2", "c3"],
	"rows": ["m", "n"],
	"column_x": {"c1": -150.0, "c2": -100.0, "c3": -50.0},
	"row_z": {"m": 0.0, "n": -48.0},
	"node_y":
	{
		"c1_m": -52.0,
		"c2_m": -58.0,
		"c2_n": -55.0,
		"c3_m": -66.0,
		"c3_n": -62.0,
	},
	"omitted_nodes": ["c1_n"],
	"drift_rows": ["m"],
	"drift_junction_radius": 5.0,
	"strip_junction_radius": 3.5,
	"drift_width": 9.0,
	"strip_width": 7.0,
	# The first cross-cut is full width on purpose. The player's first branch
	# should not also be their first squeeze.
	"narrow_strips": {"c3_mn": 4.5},
	"omitted_strips": [],
	"omitted_drifts": [],
}
#endregion

#region Mines - lower level
#
# The full grid, and the only place in the biome that gets one. It is reached
# only by a winze, so nobody arrives here without having already learnt a T and a
# plus junction upstairs.

const LEVEL_B := {
	"prefix": "b",
	"columns": ["c1", "c2", "c3"],
	"rows": ["m", "n"],
	"column_x": {"c1": -150.0, "c2": -100.0, "c3": -50.0},
	"row_z": {"m": 0.0, "n": -48.0},
	"node_y":
	{
		"c1_m": -105.0,
		"c1_n": -103.0,
		"c2_m": -110.0,
		"c2_n": -108.0,
		"c3_m": -118.0,
		"c3_n": -114.0,
	},
	"omitted_nodes": [],
	"drift_rows": ["m"],
	"drift_junction_radius": 5.0,
	"strip_junction_radius": 3.5,
	"drift_width": 9.0,
	"strip_width": 7.0,
	"narrow_strips": {"c1_mn": 4.5},
	"omitted_strips": [],
	"omitted_drifts": [],
}
#endregion

#region Spaces outside the grids

const NATURAL_FORK_RADIUS := 5.0

const EXTRA_SPACES := [
	{
		"name": "mine_mouth",
		"position": Vector3(-215, -52, 0),
		"radius": 7.0,
		"kind": "room",
		"tags": ["entrance"],
	},
	{
		"name": "fork_east",
		"position": Vector3(-8, -72, 40),
		"radius": NATURAL_FORK_RADIUS,
		"kind": "junction",
		"tags": ["natural"],
	},
	{
		"name": "fork_deep",
		"position": Vector3(-14, -124, -70),
		"radius": NATURAL_FORK_RADIUS,
		"kind": "junction",
		"tags": ["natural"],
	},
	{
		"name": "link_ravine",
		"position": Vector3(58, -84, 118),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
	},
	{
		"name": "link_hive",
		"position": Vector3(34, -152, -112),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
	},
]
#endregion

#region Tunnels outside the grids
#
# `bends` as an array is exact corners; as a number it is that many generated
# ones. The adit has neither, because it is the one tunnel in the game that must
# not bend.

const EXTRA_TUNNELS := [
	{
		"name": "entrance_adit",
		"from": "mine_mouth",
		"to": "a_c1_m",
		"width": 10.0,
		"bends": [],
		"tags": ["drift", "entrance"],
	},
	# The first branch the player ever sees is a_c2's cross-cut, which the grid
	# generates. Nothing below is reachable before then.
	{
		"name": "winze_deep",
		"from": "a_c3_m",
		"to": "b_c3_m",
		"width": 7.0,
		"bends": [],
		"tags": ["winze"],
	},
	# Too narrow for the creature: the one route between levels that is a way
	# out rather than a risk.
	{
		"name": "winze_north",
		"from": "a_c2_n",
		"to": "b_c2_n",
		"width": 5.0,
		"bends": [],
		"tags": ["winze", "refuge"],
	},
	{
		"name": "nat_a_deep",
		"from": "a_c2_n",
		"to": "a_c3_m",
		"width": 5.5,
		"bends": 3,
		"wander": 9.0,
		"seed": 301,
		"tags": ["natural", "refuge"],
	},
	# Not a winze and not on the survey. Taking it puts you a level down and a
	# column west of where you think you are.
	{
		"name": "nat_drop",
		"from": "a_c3_n",
		"to": "b_c2_m",
		"width": 6.8,
		"bends": 4,
		"wander": 13.0,
		"seed": 302,
		"tags": ["natural"],
	},
	{
		"name": "nat_b_cross",
		"from": "b_c1_m",
		"to": "b_c2_n",
		"width": 7.2,
		"bends": 3,
		"wander": 11.0,
		"seed": 303,
		"tags": ["natural"],
	},
	{
		"name": "fork_from_mines",
		"from": "a_c3_m",
		"to": "fork_east",
		"width": 7.5,
		"bends": 2,
		"wander": 8.0,
		"seed": 304,
		"tags": ["natural"],
	},
	{
		"name": "link_to_ravine",
		"from": "fork_east",
		"to": "link_ravine",
		"width": 6.8,
		"bends": 3,
		"wander": 11.0,
		"seed": 305,
		"tags": ["biome_link"],
	},
	{
		"name": "fork_from_lower",
		"from": "b_c3_n",
		"to": "fork_deep",
		"width": 7.0,
		"bends": 2,
		"wander": 9.0,
		"seed": 306,
		"tags": ["natural"],
	},
	{
		"name": "link_to_hive",
		"from": "fork_deep",
		"to": "link_hive",
		"width": 7.0,
		"bends": 3,
		"wander": 11.0,
		"seed": 307,
		"tags": ["biome_link"],
	},
]
#endregion

const TAG_COLORS := {
	&"drift": Color(0.35, 0.62, 1.0),
	&"strip": Color(0.55, 0.78, 0.95),
	&"natural": Color(0.95, 0.62, 0.25),
	&"winze": Color(0.85, 0.35, 0.9),
	&"biome_link": Color(1.0, 0.85, 0.2),
	&"refuge": Color(0.3, 0.9, 0.5),
	&"entrance": Color(0.95, 0.95, 0.5),
	&"unbuilt": Color(0.5, 0.5, 0.55),
}

## Everything above, assembled for BlockoutScaffold.
const SPEC := {
	"output_path": "res://levels/design/level_mine_blockout.tscn",
	"level_name": "MineBlockout",
	"creature_min_width": CREATURE_MIN_WIDTH,
	"tag_colors": TAG_COLORS,
	"grids": [LEVEL_A, LEVEL_B],
	"spaces": EXTRA_SPACES,
	"tunnels": EXTRA_TUNNELS,
	"entrance": "mine_mouth",
	"sound_origin": "a_c2_m",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Scaffold.new().run(self, SPEC)
