extends SceneTree

## Asks the carved rock what you can actually see from where.
##
## Sightline is a design property in every biome here and it is the one thing a
## coordinate table cannot tell you: the ravine is meant to be too crooked to see
## end to end, a hive layer is meant to be open right across, and the mines are
## meant to be legible until they are not. All three are claims about geometry,
## and this measures them instead of taking their word for it.
##
##     godot --headless --path . --script res://tools/level_design/check_sightlines.gd -- \
##         --level=res://levels/design/level_ravine_blockout.tscn \
##         --pairs=rv_north_end,rv_south_end;rv_s1,rv_s3
##
## Pairs are space names separated by a comma, pairs separated by a semicolon.

const WALKTHROUGH_PATH := "res://levels/design/level_walkthrough.tscn"

## Physics frames to wait before probing. CSG rebuilds on a deferred call and the
## collision shape lands a frame or two after the mesh does.
const SETTLE_FRAMES := 240


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var level_path := _argument("--level=")
	var walkthrough: Node3D = load(WALKTHROUGH_PATH).instantiate()
	if not level_path.is_empty():
		# Before entering the tree: the walkthrough's _ready is what carves.
		walkthrough.level_scene = load(level_path)
	root.add_child(walkthrough)
	for frame: int in SETTLE_FRAMES:
		await physics_frame

	var level := walkthrough.get_node_or_null("Level") as MineLevel
	if level == null:
		printerr("check_sightlines: nothing was mounted")
		quit(1)
		return

	var positions: Dictionary = {}
	for space: MineSpace in level.spaces_in_level():
		positions[String(space.name)] = space.global_position

	var pairs := _argument("--pairs=")
	if pairs.is_empty():
		printerr("check_sightlines: --pairs= is required")
		quit(1)
		return
	for pair: String in pairs.split(";", false):
		_report_pair(level.get_world_3d().direct_space_state, positions, pair)
	quit(0)


func _report_pair(
	space_state: PhysicsDirectSpaceState3D, positions: Dictionary, pair: String
) -> void:
	var ends := pair.split(",")
	if ends.size() != 2 or not positions.has(ends[0]) or not positions.has(ends[1]):
		print("%s: no such pair of spaces" % pair)
		return
	var from_point: Vector3 = positions[ends[0]]
	var to_point: Vector3 = positions[ends[1]]
	var query := PhysicsRayQueryParameters3D.create(from_point, to_point)
	query.collision_mask = 1
	var hit := space_state.intersect_ray(query)
	var gap := from_point.distance_to(to_point)
	if hit.is_empty():
		print("%s: CLEAR over %.0f m" % [pair, gap])
		return
	print(
		(
			"%s: blocked at %.0f m of %.0f"
			% [pair, from_point.distance_to(hit["position"] as Vector3), gap]
		)
	)


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""
