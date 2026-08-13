class_name CreatureNavDemoHud
extends CanvasLayer

## The readout, and the control legend.
##
## The Label3D above the ball says what the creature is doing; this says what NAVIGATION
## is doing, which is a different question and mostly a different failure. A creature that
## sits still because the bake has not finished and one that sits still because every
## route comes back UNREACHABLE look identical from the outside.

const CONTROL_LEGEND := """RMB / T send creature here   LMB mine   Esc release mouse
WASD/Space/Ctrl thrust   Q/E roll   Shift sprint
1 Gallery  2 Warren  3 Vent Loft  4 Gallery ceiling  5 Dock
F1 world graph   F2 locomotion   F3 brush size   F4 believed graph   R rebake"""

var _navigation: CreatureNavigation = null
var _prototype: CreatureNavDemoPrototype = null

@onready var _readout: Label = $Readout


func bind(navigation: CreatureNavigation, prototype: CreatureNavDemoPrototype) -> void:
	_navigation = navigation
	_prototype = prototype


func refresh() -> void:
	if _readout == null:
		return
	_readout.text = "\n".join(_lines()) + "\n\n" + CONTROL_LEGEND


func _lines() -> Array[String]:
	if _navigation == null:
		return ["navigation: unbound"] as Array[String]
	var lines: Array[String] = []
	if _navigation.is_baking():
		lines.append("baking %d%%" % int(_navigation.bake_progress() * 100.0))
	elif _navigation.world_graph == null:
		lines.append("no graph")
	else:
		var believed: String = "believed" if _navigation.use_knowledge else "world"
		lines.append(
			(
				"graph (%s): %d nodes, %d edges   revision %d"
				% [
					believed,
					_navigation.graph.node_count(),
					_navigation.graph.edge_count(),
					_navigation.world_graph.terrain_revision
				]
			)
		)
		var counts: Dictionary = _navigation.knowledge.counts()
		lines.append("knowledge: %s" % counts)

	var route: NavRoute = _navigation.route
	if route == null:
		lines.append("route: none -- right-click a wall")
	else:
		lines.append("route: %s  %.1fs" % [route.status_name(), route.cost])
		_describe_progress(lines, route)
	if _prototype != null:
		lines.append("brush: %s" % ("alien-sized" if _prototype.brush_is_wide() else "player-only"))
	return lines


## How far along the route the body actually is.
##
## THE DISTANCE TO THE CURRENT ANCHOR IS THE MOST DIAGNOSTIC NUMBER IN THIS SCENE. An
## alien that is moving, has a COMPLETE route and never advances its anchor index is
## chasing a point it cannot reach -- and nothing else on screen distinguishes that from
## an alien that is simply taking a while.
func _describe_progress(lines: Array[String], route: NavRoute) -> void:
	var follower: RouteFollower = _navigation.follower
	if not follower.has_route():
		return
	var at: Vector3 = _navigation.body_state.position
	var anchor: Vector3 = follower.current_anchor()
	lines.append(
		(
			"anchor %d/%d at (%.0f, %.0f, %.0f)   %.1f m away   %d skipped"
			% [
				follower.index,
				maxi(route.anchors.size() - 1, 0),
				anchor.x,
				anchor.y,
				anchor.z,
				at.distance_to(anchor),
				follower.skipped_anchors.size()
			]
		)
	)
	var command: NavMotionCommand = _navigation.command
	if command != null:
		# THE INSPECTION'S REASON, NOT JUST ITS STATE. The first thing an inspection does is
		# hold the body still, and holding still replaces the stalled command that caused it
		# -- so `abort` reads "none" one frame later and the readout says the alien is
		# investigating something without saying what. Two different bugs look identical
		# without this: a route that cannot reach its goal, and a body that fell off its wall.
		lines.append(
			(
				"mode %s%s   %.1f m/s   abort %s   inspector %s (%s)"
				% [
					NavLocomotion.mode_name(_navigation.local_planner.mode()),
					"  (recovering)" if command.recovering else "",
					command.desired_speed,
					NavMotionCommand.abort_name(command.abort),
					NavInspector.state_name(_navigation.inspector.state()),
					_navigation.inspector.debug_state()["reason"]
				]
			)
		)
	# THE WATCHDOG'S TRIP COUNT IS THE FIRST THING TO LOOK AT WHEN THE ALIEN IS ODD. Zero
	# means every stop it made was a stop something intended; climbing steadily means
	# locomotion is wedging and recovering over and over, which looks from outside almost
	# exactly like an alien that is simply slow.
	var monitor: NavProgressMonitor = _navigation.progress
	lines.append("progress: %.1f m in window   %d wedge(s)" % [monitor.moved, monitor.trips])
	var refusal: String = _navigation.local_planner.crawler.last_refusal
	if not refusal.is_empty():
		lines.append("crawl refused: %s" % refusal)
	var reading: NavSurfaceReading = _navigation.local_planner.last_reading()
	if reading != null:
		lines.append(
			(
				"body at (%.0f, %.0f, %.0f)   enclosure %.2f   nearest surface %.1f m"
				% [at.x, at.y, at.z, reading.enclosure, reading.nearest_distance()]
			)
		)
