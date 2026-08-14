extends SceneTree

## Checks that the carved blockout is actually flyable, without a human at the mouse.
##
## Headless cannot see, so it proves the carve by touching it: a sphere the size
## of the suit is dropped at the middle of every tunnel and the centre of every
## space, and anywhere that comes back solid is somewhere the bore failed to cut.
## That is the failure this exists to catch - a level that looks carved in the
## viewport but has a plug of rock across one drift.
##
##     godot --headless --path . --script res://tools/level_design/verify_walkthrough.gd
##     ... verify_walkthrough.gd -- --level=res://levels/design/level_hive_blockout.tscn
##
## `--level=` swaps the blockout the walkthrough loads, so every biome is checked
## by the same scene rather than needing a walkthrough of its own.

const WALKTHROUGH_PATH := "res://levels/design/level_walkthrough.tscn"

## Radius of the probe, matching the suit's collision hull.
const SUIT_RADIUS := 0.4

## Physics frames to wait before probing. CSG rebuilds on a deferred call and the
## collision shape lands a frame or two after the mesh does.
const SETTLE_FRAMES := 240

## How many of the worst-overrunning runs to name.
const OVERRUN_REPORT_COUNT := 6


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var walkthrough: Node3D = load(WALKTHROUGH_PATH).instantiate()
	# Set before the walkthrough enters the tree, because its _ready is what
	# mounts and carves whatever level_scene is pointing at.
	var chosen := _requested_level()
	if not chosen.is_empty():
		walkthrough.level_scene = load(chosen)
		print("level: %s" % chosen)
	root.add_child(walkthrough)
	for frame: int in SETTLE_FRAMES:
		await physics_frame

	var failures := PackedStringArray()
	failures.append_array(_check_carve(walkthrough))
	failures.append_array(_check_hollow(walkthrough))

	if failures.is_empty():
		print("verify_walkthrough: OK")
		quit(0)
		return
	for failure: String in failures:
		printerr("verify_walkthrough: %s" % failure)
	quit(1)


## The carve produced geometry at all, and the suit is standing in open space.
func _check_carve(walkthrough: Node3D) -> PackedStringArray:
	var failures := PackedStringArray()
	var builder := walkthrough.get_node_or_null("LevelGeometry") as LevelGeometryBuilder
	if builder == null:
		failures.append("no LevelGeometryBuilder in the walkthrough scene")
		return failures

	var brushes := builder.brush_count()
	print("brushes: %d" % brushes)
	if brushes == 0:
		failures.append("nothing was carved")
		return failures

	_report_overruns(builder.overruns_by_tunnel())

	var combiner := builder.get_node_or_null("HullCombiner") as CSGCombiner3D
	var meshes := combiner.get_meshes()
	if meshes.size() < 2 or meshes[1] == null:
		failures.append("the combiner produced no mesh")
		return failures
	print("triangles: %d" % ((meshes[1] as Mesh).get_faces().size() / 3))

	var suit := walkthrough.get_node_or_null("Suit") as Node3D
	if suit == null:
		failures.append("no suit spawned")
		return failures
	if not _is_open(suit.get_world_3d().direct_space_state, suit.global_position):
		failures.append("the suit spawned inside solid rock at %v" % suit.global_position)
	return failures


## Every bore and every chamber got cut.
func _check_hollow(walkthrough: Node3D) -> PackedStringArray:
	var failures := PackedStringArray()
	var level := walkthrough.get_node_or_null("Level") as MineLevel
	if level == null:
		failures.append("no MineLevel in the walkthrough scene")
		return failures

	var space_state := level.get_world_3d().direct_space_state
	var graph := level.build_graph()
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		if not _is_open(space_state, tunnel.point_at(tunnel.length() * 0.5)):
			failures.append("tunnel '%s' is solid at its midpoint" % tunnel.id)
	for space: LevelGraph.Space in graph.spaces:
		if not _is_open(space_state, space.position):
			failures.append("space '%s' is solid at its centre" % space.id)
	print("probed %d tunnels and %d spaces" % [graph.tunnels.size(), graph.spaces.size()])
	return failures


## The runs whose bores reach furthest past their own junctions.
##
## Not a pass or a fail - overrun is what seals a junction and some of it has to be
## there. It is printed because a run near the top of this list with a gentle bend
## is carving a spur out through the wall, and nothing else in a headless check
## would ever mention it.
func _report_overruns(overruns: Dictionary) -> void:
	var ranked := overruns.keys()
	ranked.sort_custom(
		func(left: String, right: String) -> bool: return overruns[left] > overruns[right]
	)
	var worst := PackedStringArray()
	for tunnel_id: String in ranked.slice(0, OVERRUN_REPORT_COUNT):
		worst.append("%s %.1f m" % [tunnel_id, overruns[tunnel_id]])
	print("widest overruns: %s" % ", ".join(worst))


func _requested_level() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			return argument.substr("--level=".length())
	return ""


func _is_open(space_state: PhysicsDirectSpaceState3D, where: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = SUIT_RADIUS
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = sphere
	probe.transform = Transform3D(Basis(), where)
	probe.collision_mask = 1
	return space_state.intersect_shape(probe, 1).is_empty()
