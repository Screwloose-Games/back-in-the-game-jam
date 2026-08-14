extends SceneTree

## The hive biome, as data. BlockoutScaffold does the building.
##
## AN ANTHILL IN SECTION. Eight strata over about 110 m, each one a wandering
## field of blobby chambers rather than a disc of cells on a ring. A stratum is
## horizontal and nothing about it is flat: its chambers sit on a warped surface
## that rises and falls several metres across the width of the biome, and each
## chamber is a different size and a different thickness from its neighbours, so
## the space you cross opens into a room and pinches to a squeeze and opens again.
##
## A STRATUM IS ONE CONTINUOUS VOID WITH PILLARS IN IT, not a set of rooms joined
## by corridors. Most bores are wide enough to merge with the chambers at both
## ends, so what stands between you and the far side of a stratum is whatever rock
## the scatter happened to leave, and it stops a sightline somewhere between 7 and
## 30 m of the 63 to 89 m across. You can never see out of a stratum, and how far
## you can see inside one varies enough that it is not a cue to which one it is.
##
## THE STRATA ARE NOT SEPARATE FLOORS. They stagger sideways from one another,
## they come close in places, and where they come close they are joined straight
## through the floor. Where they come closer still they simply intersect, and one
## cavity spans two strata with nothing to tell you it did. That is the anthill's
## defining property and it is why the depth you are at is never a thing you know.
##
## THAT IS WHY THIS IS THE MOST DISORIENTING BIOME. In the mines you are lost
## about where; here you are lost about which stratum, and every stratum looks
## like the answer. There is deliberately no guarantee that you cannot see from
## one stratum into another - a glimpse of movement below through a hole in the
## floor is worse than never seeing anything at all.
##
## Nothing here joins the mines or the ravine. The two `link_*` stubs mark where
## it would, with no central cavern assumed.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/build_hive_blockout.gd
##
## It refuses to overwrite the scene it made last time; add `-- --force` when a
## re-roll is what you want.

## tools/ carries a .gdignore, so nothing under it registers a global class name.
const Scaffold := preload("res://tools/level_design/blockout_scaffold.gd")

## Matches the mines. Anything under this is a refuge.
const CREATURE_MIN_WIDTH := 6.4

#region The strata
#
# EVERY NUMBER HERE IS A RANGE, and `seed` is the knob you re-roll when a layout
# comes out wrong. There are no coordinates to tune because there is nothing
# regular left to tune: an anthill's irregularity is the design, and a table of
# hand-typed cell positions could only ever be one sample of it.
#
# Three of these decide whether it reads as an anthill or as something else:
#
# `blob_vertical_scale` is drawn independently of `blob_radius`, so a chamber's
# thickness has nothing to do with its width. That is what gives a stratum uneven
# thickness instead of the single flat gap the old stack had.
#
# `blob_spacing` against the bore widths decides whether a stratum is continuous.
# Chambers 11 to 20 m apart with most bores wider than half that merge into one
# void; push them further apart and the same spec builds a warren of rooms and
# corridors instead, which is a mine and not a hive.
#
# `gap` against `undulation` decides how often two strata meet, and it is the
# pair to reach for when the stack comes out too separated or too mixed. A base
# separation of 9 to 21 m with each surface waving 8 m either way - and waving
# independently of its neighbours, which is the part that matters - means two
# strata clear each other over most of the biome and run into one another
# somewhere. THE BUILD PRINTS HOW MANY JOINS IT MANAGED. A stack reporting no
# merges is the flat stack this replaced, and it will not look wrong in any
# other number.

const STRATA := {
	"prefix": "hv",
	"seed": 7,
	"center": Vector3(0, 0, 0),
	"count": 8,
	"top_y": -14.0,
	"gap": Vector2(9.0, 21.0),
	"drift": 14.0,
	"spread": 46.0,
	"undulation": 8.0,
	"undulation_scale": 72.0,
	"blobs": Vector2i(12, 20),
	"blob_spacing": Vector2(11.0, 20.0),
	"blob_radius": Vector2(5.0, 11.0),
	"blob_vertical_scale": Vector2(0.30, 0.55),
	"blob_jitter": 1.6,
	"bore_width": Vector2(3.4, 24.0),
	"bore_height": Vector2(2.6, 7.5),
	"extra_edges": 0.35,
	"breach_gap": 10.0,
	"breach_width": Vector2(3.6, 9.0),
	"breaches_per_gap": 5,
	"long_links": 5,
	"long_link_width": Vector2(4.5, 8.0),
	# The only names anything outside the generator can rely on. Each resolves to
	# whichever chamber in that stratum lands nearest the point, so re-rolling the
	# seed moves them without breaking them.
	"anchors":
	{
		"hv_entry": {"stratum": 0, "near": Vector3(-4, 0, -46)},
		"hv_middle": {"stratum": 2, "near": Vector3(0, 0, 0)},
		"hv_ravine_side": {"stratum": 1, "near": Vector3(94, 0, 58)},
		"hv_deep": {"stratum": 7, "near": Vector3(-86, 0, 58)},
	},
	"stratum_tags": ["hive", "chamber"],
	"bore_tags": ["hive", "bore"],
	"breach_tags": ["hive", "breach"],
	"long_link_tags": ["hive", "long_link"],
}
#endregion

#region Spaces outside the strata

const EXTRA_SPACES := [
	{
		"name": "hive_mouth",
		"position": Vector3(-4, 8, -46),
		"radius": 6.0,
		"kind": "room",
		"tags": ["hive", "entrance"],
	},
	{
		"name": "link_mines",
		"position": Vector3(-86, -135, 58),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
	},
	{
		"name": "link_ravine",
		"position": Vector3(94, -34, 58),
		"radius": 4.0,
		"kind": "dead_end",
		"tags": ["biome_link", "unbuilt"],
	},
]
#endregion

#region Tunnels outside the strata
#
# Every tunnel that skips strata is generated, so these are only the ones that
# reach something the generator does not know about. They aim at anchors rather
# than at chamber names for the reason the anchors exist.

const EXTRA_TUNNELS := [
	{
		"name": "entrance_drop",
		"from": "hive_mouth",
		"to": "hv_entry",
		"width": 7.5,
		"bends": 2,
		"wander": 7.0,
		"seed": 201,
		"tags": ["hive", "entrance"],
	},
	{
		"name": "link_to_ravine",
		"from": "hv_ravine_side",
		"to": "link_ravine",
		"width": 7.0,
		"bends": 3,
		"wander": 11.0,
		"seed": 206,
		"tags": ["hive", "biome_link"],
	},
	{
		"name": "link_to_mines",
		"from": "hv_deep",
		"to": "link_mines",
		"width": 6.8,
		"bends": 3,
		"wander": 11.0,
		"seed": 207,
		"tags": ["hive", "biome_link"],
	},
]
#endregion

const TAG_COLORS := {
	&"chamber": Color(0.35, 0.72, 1.0),
	&"bore": Color(0.45, 0.85, 0.95),
	&"breach": Color(0.95, 0.62, 0.25),
	# The breaches where the two strata already run into one another, which are
	# the ones worth being able to pick out of the stack at a glance.
	&"merged": Color(1.0, 0.4, 0.35),
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
	"strata": [STRATA],
	"spaces": EXTRA_SPACES,
	"tunnels": EXTRA_TUNNELS,
	"entrance": "hive_mouth",
	"sound_origin": "hv_middle",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Scaffold.new().run(self, SPEC)
