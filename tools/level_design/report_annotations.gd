extends SceneTree

## Writes the level's annotations out as a document to send with the exported model.
##
## A .gltf carries geometry and nothing else: no notes, no tags, no names that mean
## anything once the CSG has been resolved into one lump of rock. So the annotations
## travel beside it, keyed by coordinate - both the document and the model are built
## from the same LevelGraph, at the same scale, about the same origin, so a reader
## can find any annotated place in Blender by typing its position.
##
## `notes` belongs to whoever is designing the level. This reads it and never
## writes it.
##
##     godot --headless --path . --script res://tools/level_design/report_annotations.gd
##     ... report_annotations.gd -- --level=res://levels/design/level_mine_blockout.tscn

const DEFAULT_LEVEL := "res://levels/design/level_full_blockout.tscn"
const OUTPUT_DIRECTORY := "res://documentation/design"

## Where the exported model lands, so the document can say what it belongs to.
const MODEL_PATH := "assets/art/environment/level_blockout/sm_level_full_blockout.gltf"

var _level: MineLevel = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var level_path := _requested_level()
	_level = load(level_path).instantiate() as MineLevel
	if _level == null:
		printerr("report_annotations: %s does not have a MineLevel root" % level_path)
		quit(1)
		return
	root.add_child(_level)

	var page := _compose(level_path)
	var target := "%s/%s_annotations.md" % [OUTPUT_DIRECTORY, level_path.get_file().get_basename()]
	var handle := FileAccess.open(target, FileAccess.WRITE)
	if handle == null:
		printerr("report_annotations: could not write %s" % target)
		quit(1)
		return
	handle.store_string(page)
	handle.close()

	print("wrote %s" % target)
	print(
		(
			"%d annotated spaces, %d annotated tunnels"
			% [_annotated_spaces().size(), _annotated_tunnels().size()]
		)
	)
	quit(0)


func _compose(level_path: String) -> String:
	var stats := _level.describe_stats()
	var lines := PackedStringArray()

	lines.append("# %s: annotations" % _level.name)
	lines.append("")
	lines.append(
		(
			(
				"Generated from `%s` by `tools/level_design/report_annotations.gd`. "
				+ "Every number here is derived from the level; nothing in this file is "
				+ "hand-maintained, so re-run it rather than editing it."
			)
			% level_path
		)
	)
	lines.append("")

	lines.append("## The model this goes with")
	lines.append("")
	lines.append("`%s`, with its `.bin` and `.import` beside it." % MODEL_PATH)
	lines.append("")
	lines.append("- **Units are metres**, one Blender unit to one metre.")
	lines.append(
		(
			"- **The model sits at the level's own origin**, so a position in the "
			+ "tables below is the position in the file. Nothing is re-centred."
		)
	)
	lines.append(
		(
			"- **Corners are sharp.** The rock is a resolved CSG carve, which has no "
			+ "fillets. To dull them: Bevel modifier at about 0.15 m with 2 segments "
			+ "and clamp overlap on, then Shade Auto Smooth at 30 degrees, then "
			+ "Weighted Normal."
		)
	)
	lines.append(
		(
			"- **Facing is Godot's -Z forward**, the convention this repo uses "
			+ "throughout, deliberately not the glTF spec's +Z-front."
		)
	)
	lines.append("")

	lines.append("## What is in it")
	lines.append("")
	var shape := (
		"%d spaces (%d rooms, %d junctions, %d dead ends) joined by %d tunnels, "
		+ "%.0f m of centreline, running from %.0f m to %.0f m."
	)
	var summary := (
		shape
		% [
			stats["space_count"],
			stats["room_count"],
			stats["junction_count"],
			stats["dead_end_count"],
			stats["tunnel_count"],
			stats["total_length"],
			stats["shallowest"],
			stats["deepest"],
		]
	)
	lines.append(summary)
	lines.append("")
	lines.append(
		(
			(
				"%d tunnels are wide enough for the creature at the level's current "
				+ "%.1f m threshold; the other %d are refuges."
			)
			% [stats["passable_tunnels"], _level.creature_min_width, stats["refuge_tunnels"]]
		)
	)
	lines.append("")

	var problems := _level.validate()
	if problems.is_empty():
		lines.append("The graph validates: no duplicate names, no half-wired tunnels, and")
		lines.append("every space has a route from the entrance.")
	else:
		lines.append("**The graph does not validate:**")
		lines.append("")
		for problem: String in problems:
			lines.append("- %s" % problem)
	lines.append("")

	lines.append("## Maps")
	lines.append("")
	lines.append(
		(
			"![plan and elevation](images/%s_%s.svg)"
			% [level_path.get_file().get_basename(), _describe_color_mode().to_lower()]
		)
	)
	lines.append("")
	lines.append(
		(
			"Plan and elevation, drawn from the same graph, by "
			+ "`tools/level_design/render_level_maps.gd`. Both mine levels sit on one "
			+ "survey grid and the hive is eight strata deep, so in plan a lot of this "
			+ "overprints - pass `--tags=` to draw one part at a time."
		)
	)
	lines.append("")

	lines.append_array(_annotation_section())
	lines.append_array(_index_section())
	return "\n".join(lines) + "\n"


func _describe_color_mode() -> String:
	return MineLevel.ColorMode.keys()[_level.color_mode]


## The annotated places, which is the part of this document a person reads.
func _annotation_section() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("## Annotations")
	lines.append("")

	var spaces := _annotated_spaces()
	var tunnels := _annotated_tunnels()
	if spaces.is_empty() and tunnels.is_empty():
		lines.append(
			(
				"Nothing is annotated yet. Notes are the `notes` field on any space or "
				+ "tunnel in the blockout scenes; fill some in and re-run this."
			)
		)
		lines.append("")
		return lines

	for biome: String in _biome_order():
		var biome_spaces := spaces.filter(
			func(space: MineSpace) -> bool: return _biome_of(space) == biome
		)
		var biome_tunnels := tunnels.filter(
			func(tunnel: MineTunnel) -> bool: return _biome_of(tunnel) == biome
		)
		if biome_spaces.is_empty() and biome_tunnels.is_empty():
			continue

		lines.append("### %s" % biome)
		lines.append("")
		for space: MineSpace in biome_spaces:
			lines.append(
				(
					"**%s** - %s, at %s.  \n%s"
					% [
						space.name,
						_describe_kind(space),
						_position_of(space),
						space.notes.strip_edges().replace("\n", "  \n")
					]
				)
			)
			lines.append("")
		for tunnel: MineTunnel in biome_tunnels:
			lines.append(
				(
					"**%s** - %.0f m, %.1f m wide, from %s to %s.  \n%s"
					% [
						tunnel.name,
						tunnel.length(),
						tunnel.width,
						tunnel.resolve_from().name,
						tunnel.resolve_to().name,
						tunnel.notes.strip_edges().replace("\n", "  \n")
					]
				)
			)
			lines.append("")
	return lines


## Every space and tunnel, so anything visible in the model can be looked up.
func _index_section() -> PackedStringArray:
	var lines := PackedStringArray()

	lines.append("## Every space")
	lines.append("")
	lines.append("| Space | Where | Kind | Position x, y, z (m) | Radius | Tags |")
	lines.append("|---|---|---|---|---|---|")
	for space: MineSpace in _level.spaces_in_level():
		var radius := "-" if space.radius <= 0.0 else "%.1f m" % space.radius
		var row := (
			"| `%s` | %s | %s | %s | %s | %s |"
			% [
				space.name,
				_biome_of(space),
				_describe_kind(space),
				_position_of(space),
				radius,
				_describe_tags(space.tags),
			]
		)
		lines.append(row)
	lines.append("")

	lines.append("## Every tunnel")
	lines.append("")
	lines.append("| Tunnel | Where | From | To | Length | Width | Height | Tags |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for tunnel: MineTunnel in _level.tunnels_in_level():
		if not tunnel.describe_problem().is_empty():
			continue
		var bore := "= width" if tunnel.height <= 0.0 else "%.1f m" % tunnel.height
		var row := (
			"| `%s` | %s | `%s` | `%s` | %.0f m | %.1f m | %s | %s |"
			% [
				tunnel.name,
				_biome_of(tunnel),
				tunnel.resolve_from().name,
				tunnel.resolve_to().name,
				tunnel.length(),
				tunnel.width,
				bore,
				_describe_tags(tunnel.tags),
			]
		)
		lines.append(row)
	lines.append("")
	return lines


## Which part of the level a node lives in: the branch of the root it hangs off.
##
## Read from the tree rather than from tags, because a composed level's biomes are
## instanced scenes and that is the one grouping guaranteed to be right.
func _biome_of(node: Node) -> String:
	var branch := node
	while branch != null and branch.get_parent() != _level:
		branch = branch.get_parent()
	return "the level" if branch == null else String(branch.name)


func _biome_order() -> PackedStringArray:
	var seen := PackedStringArray()
	for child: Node in _level.get_children():
		if child.name != "DesignVisuals":
			seen.append(String(child.name))
	return seen


func _annotated_spaces() -> Array[MineSpace]:
	return _level.spaces_in_level().filter(
		func(space: MineSpace) -> bool: return not space.notes.strip_edges().is_empty()
	)


func _annotated_tunnels() -> Array[MineTunnel]:
	return _level.tunnels_in_level().filter(
		func(tunnel: MineTunnel) -> bool:
			return (
				not tunnel.notes.strip_edges().is_empty() and tunnel.describe_problem().is_empty()
			)
	)


func _describe_kind(space: MineSpace) -> String:
	match space.kind:
		LevelGraph.SpaceKind.ROOM:
			return "room"
		LevelGraph.SpaceKind.JUNCTION:
			return "junction"
		LevelGraph.SpaceKind.DEAD_END:
			return "dead end"
	return "space"


func _describe_tags(tags: Array[StringName]) -> String:
	if tags.is_empty():
		return "-"
	var written := PackedStringArray()
	for tag: StringName in tags:
		written.append("`%s`" % tag)
	return " ".join(written)


func _position_of(node: Node3D) -> String:
	var where := node.global_position
	return "%.0f, %.0f, %.0f" % [where.x, where.y, where.z]


func _requested_level() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			return argument.substr("--level=".length())
	return DEFAULT_LEVEL
