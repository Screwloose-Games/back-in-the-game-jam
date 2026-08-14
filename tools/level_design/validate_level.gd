extends SceneTree

## Runs MineLevel.validate() from the command line.
##
## The designer dock has a Validate button, which is no use to CI and no use after
## a scene has been rewritten by a tool. Same checks, same wording: duplicate names,
## half-wired tunnels, and any space with no route from the entrance.
##
## Reachability is the one a composed level gets wrong. Geometry probing proves
## every bore was cut; it says nothing about whether a biome is joined to the rest
## of the asteroid, and a biome that is not is a biome the player never sees.
##
## `--creature-width=` overrides the level's own threshold for the run. The
## creature's real size is not settled, and each blockout was authored against
## whatever number was current when it was built, so comparing two biomes means
## putting them on the same threshold first.
##
##     godot --headless --path . --script res://tools/level_design/validate_level.gd
##     ... validate_level.gd -- --level=res://levels/design/level_mine_blockout.tscn
##     ... validate_level.gd -- --creature-width=3.9

const DEFAULT_LEVEL := "res://levels/design/level_full_blockout.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var level_path := _requested_level()
	var level := load(level_path).instantiate() as MineLevel
	if level == null:
		printerr("validate_level: %s does not have a MineLevel root" % level_path)
		quit(1)
		return
	root.add_child(level)

	var threshold := _requested_creature_width()
	if threshold > 0.0:
		level.creature_min_width = threshold

	var stats := level.describe_stats()
	print("level: %s" % level_path)
	print(
		(
			"%d spaces (%d rooms, %d junctions, %d dead ends), %d tunnels, %.0f m"
			% [
				stats["space_count"],
				stats["room_count"],
				stats["junction_count"],
				stats["dead_end_count"],
				stats["tunnel_count"],
				stats["total_length"],
			]
		)
	)
	var fit := (
		"creature: %d unhandicapped (>= %.1f m), %d squeeze (>= %.1f m), %d blocked"
		% [
			stats["passable_tunnels"],
			level.creature_min_width,
			stats["squeeze_tunnels"],
			level.creature_squeeze_width,
			stats["blocked_tunnels"],
		]
	)
	print(fit)
	print("%.0f m to %.0f m deep" % [stats["shallowest"], stats["deepest"]])

	var problems := level.validate()
	if problems.is_empty():
		print("validate_level: OK")
		quit(0)
		return
	for problem: String in problems:
		printerr("validate_level: %s" % problem)
	quit(1)


## Zero when nothing was asked for, so the level keeps its own threshold.
func _requested_creature_width() -> float:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--creature-width="):
			return argument.substr("--creature-width=".length()).to_float()
	return 0.0


func _requested_level() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			return argument.substr("--level=".length())
	return DEFAULT_LEVEL
