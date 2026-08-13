class_name CreatureNavSourceDemoHud
extends CanvasLayer

## What the LEVEL's bake is doing, which is a different question from what the creature is.
##
## `creature_nav_demo_hud.gd` reports the creature: its route, its mode, its wedge count.
## This scene's failures are almost all on the other side of the split -- a flood that
## resolved no seeds, a patch queue that never drains, a graph full of rock -- and every one
## of them shows up as a creature that does not move, which the creature-side readout
## describes perfectly and explains not at all.

const CONTROL_LEGEND := """RMB / T send creature here   LMB mine   Esc release mouse
WASD/Space/Ctrl thrust   Q/E roll   Shift sprint
1 chamber A   2 chamber B   3 chamber C (unreachable by design)
F1 graph overlay   F2 locomotion   F3 brush size   R rebake"""

var _source: NavigationSource = null
var _navigation: CreatureNavigation = null
var _prototype: Node3D = null

@onready var _readout: Label = $Readout


func bind(source: NavigationSource, navigation: CreatureNavigation, prototype: Node3D) -> void:
	_source = source
	_navigation = navigation
	_prototype = prototype


func refresh() -> void:
	if _readout == null:
		return
	_readout.text = "\n".join(_lines()) + "\n\n" + CONTROL_LEGEND


func _lines() -> Array[String]:
	if _source == null:
		return ["source: unbound"] as Array[String]
	var lines: Array[String] = []
	_describe_source(lines)
	_describe_creature(lines)
	if _prototype != null:
		lines.append(
			(
				"brush: %s   digs %d/%d"
				% [
					"alien-sized" if _prototype.brush_is_wide() else "player-only",
					_prototype.digs_spent(),
					CreatureNavSourceDemoMap.MAX_DIGS
				]
			)
		)
	return lines


## THE SEED COUNT IS THE FIRST NUMBER TO LOOK AT. A flood with zero resolved seeds bakes
## nothing, and "nothing" is indistinguishable on screen from a cave the creature simply has
## not been sent anywhere in.
func _describe_source(lines: Array[String]) -> void:
	var stats: Dictionary = _source.stats()
	var mode: String = "flood" if stats["flooding"] else "lattice sweep"
	if _source.is_baking():
		lines.append(
			(
				"baking (%s) %d%%   seeds %d ok / %d rejected   samples %d"
				% [
					mode,
					int(_source.progress() * 100.0),
					stats["seeds_resolved"],
					stats["seeds_rejected"],
					stats["samples_taken"]
				]
			)
		)
		return
	if _source.world_graph == null:
		lines.append("no graph -- the %s found nothing" % mode)
		return
	lines.append(
		(
			"graph (%s): %d nodes, %d edges (%d normal, %d wiggle)   revision %d"
			% [
				mode,
				_source.world_graph.node_count(),
				_source.world_graph.edge_count(),
				stats["edges_normal"],
				stats["edges_wiggle"],
				_source.world_graph.terrain_revision
			]
		)
	)
	var patch: Dictionary = stats["patch"]
	lines.append(
		(
			"patch queue: %d region(s)   last added %d node(s)"
			% [patch["queued"], patch["nodes_added"]]
		)
	)


func _describe_creature(lines: Array[String]) -> void:
	if _navigation == null:
		return
	var route: NavRoute = _navigation.route
	if route == null:
		lines.append("route: none -- right-click a wall")
		return
	lines.append("route: %s  %.1fs" % [route.status_name(), route.cost])
	var command: NavMotionCommand = _navigation.command
	if command == null:
		return
	lines.append(
		(
			"mode %s%s   %.1f m/s   abort %s   %d wedge(s)"
			% [
				NavLocomotion.mode_name(_navigation.local_planner.mode()),
				"  (recovering)" if command.recovering else "",
				command.desired_speed,
				NavMotionCommand.abort_name(command.abort),
				_navigation.progress.trips
			]
		)
	)
