extends SceneTree

## Rebuilds the full blockout so the biome scenes are plain instances again.
##
## The composed level was authored with "can edit children" on all three biomes,
## which is how the tunnels between them came to live inside the scenes they join.
## That leaves the biome files unable to say what they are on their own: the hive's
## own graph gains edges to ravine spaces it has never heard of.
##
## Everything those overrides carry can be said from outside instead. A MineTunnel
## names its ends by NodePath, and a NodePath reaches across an instance boundary
## perfectly well, so a tunnel joining two biomes belongs to neither and hangs off
## the composed root. A tunnel split is a MineSpace with `on_tunnel` set, which is
## what that property exists for.
##
## ONE-SHOT. It reads the composed scene, rewrites it, and has nothing to say the
## second time. Kept because the reasoning above is easier to check against code
## than against a diff of sixty override blocks.
##
## ITS OUTPUT WAS FINISHED BY HAND, and re-running it will undo that. PackedScene
## packed from a script differs from what the editor writes in three ways, none of
## which it warns about:
##
##   - every `uid=` is dropped, including the scene's own, so anything referring to
##     this level by uid - level_walkthrough.tscn does - silently repoints;
##   - the biome instances come back carrying `script =` and a copy of every
##     exported property, which PINS them: change tag_colors in the hive after that
##     and the composed level keeps the old ones;
##   - the root is renamed, because the scene being read is still in the tree under
##     the name the new one wants.
##
## Run it with --dry-run to re-read what the overrides contain. Running it for real
## means redoing that cleanup.
##
##     godot --headless --path . --script res://tools/level_design/lift_connectors.gd
##     ... lift_connectors.gd -- --dry-run

const LEVEL_PATH := "res://levels/design/level_full_blockout.tscn"

## Biome instance name in the composed scene, to the scene it instances.
const BIOMES := {
	"HiveBlockout": "res://levels/design/level_hive_blockout.tscn",
	"MineBlockout": "res://levels/design/level_mine_blockout.tscn",
	"RavineBlockout": "res://levels/design/level_ravine_blockout.tscn",
}

## The instance whose scale is being baked into its own scene by shrink_mine, and
## therefore the one whose basis has to come back to identity here.
const UNSCALED_BIOME := "MineBlockout"

## Tunnels joining two biomes get this so the geometry builder rounds their bore
## and every biome's tag_colors already has an entry for it.
const LINK_TAG := &"biome_link"

var _report := PackedStringArray()


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var composed := load(LEVEL_PATH).instantiate() as Node3D
	root.add_child(composed)

	var found := _classify(composed)
	if found.is_empty():
		quit(1)
		return

	var rebuilt := _rebuild(composed, found)
	if rebuilt == null:
		quit(1)
		return

	for line: String in _report:
		print(line)

	if _has_argument("--dry-run"):
		print("dry run: nothing written")
		quit(0)
		return

	var packed := PackedScene.new()
	var packed_error := packed.pack(rebuilt)
	if packed_error != OK:
		printerr("lift_connectors: pack failed (%d)" % packed_error)
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, LEVEL_PATH)
	if save_error != OK:
		printerr("lift_connectors: save failed (%d)" % save_error)
		quit(1)
		return
	print("wrote %s" % LEVEL_PATH)
	quit(0)


## What the overrides actually contain, sorted into the four things they can be.
##
## Anything that does not sort into one of them is a refusal rather than a guess -
## this runs once over work nobody wants to redo, so a silently dropped tunnel is
## the failure worth spending a whole classification pass to avoid.
func _classify(composed: Node3D) -> Dictionary:
	var added_spaces: Array[MineSpace] = []
	var added_tunnels: Array[MineTunnel] = []
	var retargets: Array[Dictionary] = []

	for biome_name: String in BIOMES:
		var instance := composed.get_node_or_null(NodePath(biome_name)) as MineLevel
		if instance == null:
			printerr("lift_connectors: no biome instance named '%s'" % biome_name)
			return {}
		var pristine := load(BIOMES[biome_name]).instantiate() as MineLevel
		root.add_child(pristine)

		for node: Node in _descendants(instance):
			var path := String(instance.get_path_to(node))
			var twin := pristine.get_node_or_null(NodePath(path))
			if twin == null:
				var space := node as MineSpace
				if space != null:
					added_spaces.append(space)
					continue
				var tunnel := node as MineTunnel
				if tunnel != null:
					added_tunnels.append(tunnel)
					continue
				if node is Marker3D:
					# A bend belongs to the tunnel above it and moves with it.
					continue
				printerr(
					"lift_connectors: unrecognised added node %s (%s)" % [path, node.get_class()]
				)
				return {}

			for end_name: String in _retargeted_ends(node as MineTunnel, twin as MineTunnel):
				retargets.append({"tunnel": node, "end": end_name})

		pristine.queue_free()

	_report.append(
		(
			"found %d added spaces, %d added tunnels, %d retargeted ends"
			% [added_spaces.size(), added_tunnels.size(), retargets.size()]
		)
	)
	return {
		"added_spaces": added_spaces,
		"added_tunnels": added_tunnels,
		"retargets": retargets,
	}


## Which ends of an instanced tunnel the composed scene repointed.
func _retargeted_ends(tunnel: MineTunnel, twin: MineTunnel) -> PackedStringArray:
	var changed := PackedStringArray()
	if tunnel == null or twin == null:
		return changed
	if String(tunnel.to_space) != String(twin.to_space):
		changed.append("to")
	if String(tunnel.from_space) != String(twin.from_space):
		changed.append("from")
	return changed


## The composed scene rebuilt: three clean instances and a root-owned Connectors.
func _rebuild(composed: Node3D, found: Dictionary) -> Node3D:
	var level := MineLevel.new()
	level.name = "LevelFullBlockout"
	level.color_mode = MineLevel.ColorMode.TAG
	level.creature_min_width = 6.4
	level.entrance_space = ^"MineBlockout/Spaces/mine_mouth"
	root.add_child(level)

	var merged_colors: Dictionary[StringName, Color] = {}
	for biome_name: String in BIOMES:
		var source := composed.get_node(NodePath(biome_name)) as MineLevel
		var instance := load(BIOMES[biome_name]).instantiate() as MineLevel
		instance.name = biome_name
		if biome_name == UNSCALED_BIOME:
			# Its scale is being baked into its own scene, so the instance carries
			# only where the biome sits, never how big it is.
			instance.transform = Transform3D(Basis(), source.transform.origin)
		else:
			instance.transform = source.transform
		level.add_child(instance)
		instance.owner = level
		for tag: StringName in source.tag_colors:
			merged_colors[tag] = source.tag_colors[tag]
	level.tag_colors = merged_colors

	var connectors := _make_branch(level, "Connectors", level)
	var connector_spaces := _make_branch(connectors, "Spaces", level)
	var connector_tunnels := _make_branch(connectors, "Tunnels", level)

	# Where a space that used to live inside a biome now lives, so a tunnel naming
	# it resolves to the lifted copy rather than to nothing.
	var moved: Dictionary = {}
	for space: MineSpace in found["added_spaces"]:
		var lifted := _lift_space(space, connector_spaces, level)
		moved[composed.get_path_to(space)] = lifted

	var splits := _plan_splits(composed, found, moved)
	if splits.is_empty():
		return null

	for tunnel: MineTunnel in found["added_tunnels"]:
		if splits["redundant"].has(tunnel):
			_report.append(
				(
					"  dropped %s - the on_tunnel stop on %s regenerates it"
					% [tunnel.name, splits["redundant"][tunnel]]
				)
			)
			continue
		_lift_tunnel(tunnel, connector_tunnels, level, composed, moved, false)

	for retarget: Dictionary in found["retargets"]:
		var tunnel := retarget["tunnel"] as MineTunnel
		if splits["stops"].has(tunnel):
			continue
		_lift_tunnel(tunnel, connector_tunnels, level, composed, moved, true)

	for stop_path: NodePath in splits["stops_by_space"]:
		var lifted_stop := moved[stop_path] as MineSpace
		var carrier: MineTunnel = splits["stops_by_space"][stop_path]
		lifted_stop.on_tunnel = lifted_stop.get_path_to(
			level.get_node(NodePath(String(composed.get_path_to(carrier))))
		)
		_report.append("  %s rides on %s via on_tunnel" % [lifted_stop.name, carrier.name])

	return level


## Which retargets are tunnel splits, and which added tunnel each one makes redundant.
##
## A split shows up as an instanced tunnel repointed at a NEW space, plus a second
## added tunnel carrying the rest of the original run. MineSpace.on_tunnel says both
## in one node, and _stops_by_tunnel slices the original centreline to match - so the
## added half is not moved, it is deleted.
func _plan_splits(composed: Node3D, found: Dictionary, moved: Dictionary) -> Dictionary:
	var stops: Dictionary = {}
	var stops_by_space: Dictionary = {}
	var redundant: Dictionary = {}

	for retarget: Dictionary in found["retargets"]:
		var tunnel := retarget["tunnel"] as MineTunnel
		var new_target := tunnel.resolve_to() if retarget["end"] == "to" else tunnel.resolve_from()
		var stop_path := composed.get_path_to(new_target)
		if not moved.has(stop_path):
			# Repointed at something that already existed: a reroute, not a split.
			# _rebuild republishes it as a connector and leaves the biome alone.
			continue

		var far_end := _original_far_end(tunnel, new_target, found["added_tunnels"])
		if far_end == null:
			printerr(
				(
					"lift_connectors: %s was split at %s but no tunnel carries the rest of it"
					% [tunnel.name, new_target.name]
				)
			)
			return {}
		if not is_equal_approx(far_end.width, tunnel.width):
			printerr(
				(
					(
						"lift_connectors: %s is %.2f m wide but its far half %s is %.2f m - "
						+ "on_tunnel gives both halves one width, so this is not a plain split"
					)
					% [tunnel.name, tunnel.width, far_end.name, far_end.width]
				)
			)
			return {}
		stops[tunnel] = new_target
		stops_by_space[stop_path] = tunnel
		redundant[far_end] = tunnel.name

	return {"stops": stops, "stops_by_space": stops_by_space, "redundant": redundant}


## The added tunnel that continues a split run past its new middle space.
func _original_far_end(
	tunnel: MineTunnel, stop: MineSpace, candidates: Array[MineTunnel]
) -> MineTunnel:
	for candidate: MineTunnel in candidates:
		var ends := [candidate.resolve_from(), candidate.resolve_to()]
		if not ends.has(stop):
			continue
		# The far half shares the split tunnel's tags, which is what tells it apart
		# from a biome link that happens to start at the same new junction.
		if candidate.tags == tunnel.tags:
			return candidate
	return null


func _lift_space(space: MineSpace, into: Node3D, owner_node: Node) -> MineSpace:
	var lifted := MineSpace.new()
	lifted.name = space.name
	lifted.kind = space.kind
	lifted.radius = space.radius
	lifted.vertical_scale = space.vertical_scale
	lifted.tags = space.tags.duplicate()
	lifted.notes = space.notes
	lifted.display_color = space.display_color
	into.add_child(lifted)
	lifted.owner = owner_node
	lifted.position = space.global_position
	_report.append("  lifted space %s" % lifted.name)
	return lifted


## One connector tunnel, rebuilt at the composed root.
##
## `rerouted` rebuilds an instanced tunnel that was repointed across a biome
## boundary. The biome keeps its own copy untouched, so walking that biome alone
## still has the route it was designed with, and the composed level gains the link
## as an extra edge rather than as a replacement.
func _lift_tunnel(
	tunnel: MineTunnel,
	into: Node3D,
	owner_node: Node,
	composed: Node3D,
	moved: Dictionary,
	rerouted: bool
) -> void:
	var from_node := tunnel.resolve_from()
	var to_node := tunnel.resolve_to()
	if from_node == null or to_node == null:
		printerr("lift_connectors: %s has an unresolved end; refusing to drop it" % tunnel.name)
		return

	var lifted := MineTunnel.new()
	lifted.name = "%s_to_%s" % [from_node.name, to_node.name] if rerouted else tunnel.name
	lifted.width = tunnel.width
	lifted.height = tunnel.height
	lifted.notes = tunnel.notes
	lifted.display_color = tunnel.display_color

	var tags := tunnel.tags.duplicate()
	if not tags.has(LINK_TAG):
		tags.append(LINK_TAG)
	lifted.tags = tags

	into.add_child(lifted)
	lifted.owner = owner_node

	for marker: Marker3D in tunnel.bend_markers():
		var bend := MineBend.new()
		bend.name = marker.name
		lifted.add_child(bend)
		bend.owner = owner_node
		bend.position = marker.global_position

	lifted.from_space = lifted.get_path_to(_counterpart(from_node, composed, owner_node, moved))
	lifted.to_space = lifted.get_path_to(_counterpart(to_node, composed, owner_node, moved))
	_report.append(
		(
			"  lifted tunnel %s (%s -> %s)%s"
			% [lifted.name, from_node.name, to_node.name, "  rerouted" if rerouted else ""]
		)
	)


## The node in the rebuilt tree standing for one in the composed tree.
func _counterpart(node: Node, composed: Node3D, level: Node, moved: Dictionary) -> Node:
	var path := composed.get_path_to(node)
	if moved.has(path):
		return moved[path]
	return level.get_node(NodePath(String(path)))


func _make_branch(parent: Node, branch_name: String, owner_node: Node) -> Node3D:
	var branch := Node3D.new()
	branch.name = branch_name
	parent.add_child(branch)
	branch.owner = owner_node
	return branch


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


func _has_argument(wanted: String) -> bool:
	return OS.get_cmdline_user_args().has(wanted)
