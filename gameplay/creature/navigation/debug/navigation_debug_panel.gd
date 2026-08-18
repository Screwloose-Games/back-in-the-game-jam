class_name NavigationDebugPanel
extends Label

## The numbers the section 39 overlay cannot draw.
##
## Node and edge COUNTS are what tell a bake that found nothing apart from a bake that
## found everything and drew it off screen -- two situations that look identical when
## the overlay is empty, and that have completely different causes. The wiggle count
## specifically is the fastest read on whether the clearance profile is sane: a cave
## with zero wiggle edges usually means the squeezed body is too fat to fit anything,
## and a cave where every edge is wiggle means the normal body is.
##
## Deliberately reads only public state. A panel that reaches into privates is a panel
## that stops compiling every time the module is refactored, and it gets deleted
## instead of fixed.

@export var navigation: CreatureNavigation = null


func _process(_delta: float) -> void:
	text = describe()


## Public so the sandbox and the runtime verifier can print the same summary they show.
func describe() -> String:
	if navigation == null:
		return "navigation: unbound"

	var lines: Array[String] = []
	if navigation.is_baking():
		var stats: Dictionary = navigation.bake_stats()
		lines.append(
			(
				"baking %d%%  samples %d  candidates %d"
				% [
					int(navigation.bake_progress() * 100.0),
					stats["samples_taken"],
					stats["candidates_kept"]
				]
			)
		)
	elif navigation.graph == null:
		lines.append("graph: none baked")
	else:
		var stats: Dictionary = navigation.bake_stats()
		lines.append(
			(
				"graph: %d nodes, %d edges (%d normal, %d wiggle), %d pairs rejected"
				% [
					navigation.graph.node_count(),
					navigation.graph.edge_count(),
					stats["edges_normal"],
					stats["edges_wiggle"],
					stats["pairs_rejected"]
				]
			)
		)

	var route: NavRoute = navigation.route
	if route == null:
		lines.append("route: none")
	else:
		var squeeze: String = " (squeeze)" if route.requires_squeeze() else ""
		lines.append(
			(
				"route: %s, %d anchors, %.1fs%s"
				% [route.status_name(), route.anchors.size(), route.cost, squeeze]
			)
		)
		var follower: RouteFollower = navigation.follower
		if follower != null:
			lines.append(
				(
					"anchor %d/%d, %d skipped"
					% [
						follower.index,
						maxi(route.anchors.size() - 1, 0),
						follower.skipped_anchors.size()
					]
				)
			)
	_describe_locomotion(lines)
	return "\n".join(lines)


## Phases 3-6. THE LEAP REJECTIONS ARE THE REASON THIS SECTION EXISTS: section 39 asks for
## the rejection reason on screen, and a reason is a word. The overlay can colour a
## rejected trajectory but it cannot spell "no grab", so the two halves are read together.
func _describe_locomotion(lines: Array[String]) -> void:
	var planner: NavLocalPlanner = navigation.local_planner
	if planner == null:
		return
	var state: NavBodyState = navigation.body_state
	var motion: NavMotionCommand = navigation.command
	var attached: String = "attached" if state != null and state.attached else "UNSUPPORTED"
	lines.append(
		(
			"mode: %s  %s  clearance %.2f m"
			% [
				NavLocomotion.mode_name(planner.mode()),
				attached,
				state.clearance if state != null else 0.0
			]
		)
	)
	if motion != null:
		var flags: Array[String] = []
		if motion.squeeze:
			flags.append("squeeze %.0f%%" % (planner.wiggler.squeeze_fraction() * 100.0))
		if motion.preparing_leap:
			flags.append("winding up")
		if planner.is_airborne():
			flags.append("airborne")
		if motion.is_stalled():
			flags.append("ABORT %s" % NavMotionCommand.abort_name(motion.abort))
		var detail: String = " ".join(flags) if not flags.is_empty() else "-"
		lines.append("motion: %.2f m/s  %s" % [motion.desired_speed, detail])

	var candidates: Array[NavLeapCandidate] = planner.leaper.last_candidates
	if candidates.is_empty():
		return
	var summary: Array[String] = []
	for candidate: NavLeapCandidate in candidates:
		if candidate.accepted:
			summary.append("%.0fm LEAP %.2fs" % [candidate.distance, candidate.leap_cost])
		else:
			summary.append(
				(
					"%.0fm %s"
					% [candidate.distance, NavLeapCandidate.rejection_name(candidate.rejection)]
				)
			)
	lines.append("leaps: " + ", ".join(summary))
