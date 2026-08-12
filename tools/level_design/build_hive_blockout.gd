extends SceneTree

## The hive biome, as data. BlockoutScaffold does the building.
##
## A STACK OF WIDE FLAT LAYERS. Each layer is a hub with a ring of cells around
## it, joined by bores 26 m across and 5 m floor to roof - so a layer reads as one
## flat cavity you can cross in any direction, not as a ring of tunnels. The
## through dimension is the tight one everywhere.
##
## NO LAYER SITS SQUARELY ON THE ONE BELOW. Every layer is offset, turned, and a
## different size and squash from its neighbours, so the stack never lines up into
## a shaft you can see down and no two layers feel like the same room. The risers
## between them are spread round the rim rather than stacked, so leaving a layer
## is a choice of several doors and none of them is the obvious one.
##
## THAT IS WHY THIS IS THE MOST DISORIENTING BIOME. In the mines you are lost
## about where; here you are lost about which layer, and every layer looks like
## the answer.
##
## Nothing here joins the mines or the ravine. The two `link_*` stubs mark where
## it would, with no central cavern assumed.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/build_hive_blockout.gd

## tools/ carries a .gdignore, so nothing under it registers a global class name.
const Scaffold := preload("res://tools/level_design/blockout_scaffold.gd")

## Matches the mines. Anything under this is a refuge.
const CREATURE_MIN_WIDTH := 6.4

#region The stack
#
# Seven layers over 150 m. `offset` slides a layer off the stack's axis, `twist`
# turns its ring, and `squash` flattens it on z - so no two layers present the
# same silhouette and the cells never sit on top of one another.
#
# gap_height is the number that makes this a hive rather than a warren: 5 m floor
# to roof across a 40 m layer. The creature fits it comfortably, which is the
# point - there is nowhere in a layer that is safe by being tight.

const STACK := {
	"prefix": "hv",
	"center": Vector3(0, 0, 0),
	"layer_tags": ["hive", "layer"],
	"riser_tags": ["hive", "riser"],
	"gap_width": 26.0,
	"gap_height": 5.0,
	# BOTH SMALLER THAN HALF gap_height WOULD BE IDEAL AND BOTH ARE NOT. A chamber
	# is a sphere, so anything bigger than the layer is thick domes the roof and
	# floor where it sits. Kept just proud on purpose - a hub you can rise into is
	# the one landmark a layer has - but nowhere near the radius 5 that would have
	# turned every cell into a bubble and lost the pancake entirely.
	"hub_radius": 4.0,
	"cell_radius": 3.0,
	"riser_width": 6.0,
	"riser_height": 8.0,
	"risers_per_gap": 3,
	"layers":
	[
		{
			"name": "l1",
			"y": -18.0,
			"offset": Vector2(0, 0),
			"radius": 34.0,
			"cells": 5,
			"twist": 0.0,
			"squash": 0.85,
			"notes": "Top layer. Widest ceiling in the biome and the only one with a way up.",
		},
		{
			"name": "l2",
			"y": -42.0,
			"offset": Vector2(14, -9),
			"radius": 42.0,
			"cells": 7,
			"twist": 0.45,
			"squash": 0.7,
		},
		{
			"name": "l3",
			"y": -63.0,
			"offset": Vector2(-11, 16),
			"radius": 37.0,
			"cells": 6,
			"twist": 0.95,
			"squash": 1.0,
		},
		{
			"name": "l4",
			"y": -88.0,
			"offset": Vector2(20, 7),
			"radius": 46.0,
			"cells": 8,
			"twist": 0.2,
			"squash": 0.62,
			"notes": "The big one. Long enough on its wide axis that the far rim is out of sight.",
		},
		{
			"name": "l5",
			"y": -108.0,
			"offset": Vector2(-16, -14),
			"radius": 33.0,
			"cells": 6,
			"twist": 1.3,
			"squash": 0.9,
		},
		{
			"name": "l6",
			"y": -131.0,
			"offset": Vector2(8, 19),
			"radius": 40.0,
			"cells": 7,
			"twist": 0.7,
			"squash": 0.75,
		},
		{
			"name": "l7",
			"y": -152.0,
			"offset": Vector2(-6, -5),
			"radius": 30.0,
			"cells": 5,
			"twist": 1.6,
			"squash": 1.0,
			"notes": "Bottom layer. Nothing below it, which you cannot tell from inside it.",
		},
	],
}
#endregion

#region Spaces outside the stack

const EXTRA_SPACES := [
	{
		"name": "hive_mouth",
		"position": Vector3(-4, 8, -46),
		"radius": 6.0,
		"kind": "room",
		"tags": ["hive", "entrance"],
		"notes": "Where the hive is entered from above. The only part of it that is not a layer.",
	},
	{
		"name": "link_mines",
		"position": Vector3(-88, -142, 64),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the hive hands over to the mines.",
	},
	{
		"name": "link_ravine",
		"position": Vector3(94, -34, 58),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
		"notes": "Stub. Where the hive hands over to the ravine.",
	},
]
#endregion

#region Tunnels outside the stack
#
# The long links are the ones that make the stack untrustworthy: they skip two or
# three layers, so coming up one of them puts you somewhere that looks like where
# you started and is 60 m from it.

const EXTRA_TUNNELS := [
	{
		"name": "entrance_drop",
		"from": "hive_mouth",
		"to": "hv_l1_c0",
		"width": 7.5,
		"bends": 2,
		"wander": 7.0,
		"seed": 201,
		"tags": ["hive", "entrance"],
	},
	{
		"name": "long_l1_l4",
		"from": "hv_l1_c2",
		"to": "hv_l4_c5",
		"width": 5.5,
		"bends": 3,
		"wander": 13.0,
		"seed": 202,
		"tags": ["hive", "long_link", "refuge"],
		"notes":
		"Skips two layers. Narrow enough to be a refuge, which is the only reason to remember it.",
	},
	{
		"name": "long_l2_l5",
		"from": "hv_l2_c4",
		"to": "hv_l5_c1",
		"width": 7.0,
		"bends": 3,
		"wander": 14.0,
		"seed": 203,
		"tags": ["hive", "long_link"],
	},
	{
		"name": "long_l3_l7",
		"from": "hv_l3_c3",
		"to": "hv_l7_c2",
		"width": 6.8,
		"bends": 4,
		"wander": 16.0,
		"seed": 204,
		"tags": ["hive", "long_link"],
		"notes":
		"Four layers in one run. The fastest way out of the bottom and impossible to find by accident.",
	},
	{
		"name": "long_l4_l6",
		"from": "hv_l4_c1",
		"to": "hv_l6_c5",
		"width": 4.6,
		"bends": 3,
		"wander": 12.0,
		"seed": 205,
		"tags": ["hive", "long_link", "refuge"],
	},
	{
		"name": "link_to_ravine",
		"from": "hv_l2_c1",
		"to": "link_ravine",
		"width": 7.0,
		"bends": 3,
		"wander": 11.0,
		"seed": 206,
		"tags": ["biome_link"],
	},
	{
		"name": "link_to_mines",
		"from": "hv_l6_c3",
		"to": "link_mines",
		"width": 6.8,
		"bends": 3,
		"wander": 11.0,
		"seed": 207,
		"tags": ["biome_link"],
	},
]
#endregion

const TAG_COLORS := {
	&"layer": Color(0.35, 0.72, 1.0),
	&"riser": Color(0.95, 0.62, 0.25),
	&"long_link": Color(0.85, 0.35, 0.9),
	&"entrance": Color(0.95, 0.95, 0.5),
	&"biome_link": Color(1.0, 0.85, 0.2),
	&"refuge": Color(0.3, 0.9, 0.5),
	&"unbuilt": Color(0.5, 0.5, 0.55),
}

## Everything above, assembled for BlockoutScaffold.
const SPEC := {
	"output_path": "res://levels/design/level_hive_blockout.tscn",
	"level_name": "HiveBlockout",
	"creature_min_width": CREATURE_MIN_WIDTH,
	"tag_colors": TAG_COLORS,
	"layer_stacks": [STACK],
	"spaces": EXTRA_SPACES,
	"tunnels": EXTRA_TUNNELS,
	"entrance": "hive_mouth",
	"sound_origin": "hv_l4_hub",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Scaffold.new().run(self, SPEC)
