extends Node3D

## The checks that need a real physics server (navigation.md section 43, A/B/C/D/G).
##
##   godot --headless --path <root> \
##     res://gameplay/creature/navigation/tools/verify_navigation_runtime.tscn
##
## RUN IT AS THE .tscn, NOT WITH --script. A node added during
## SceneTree._initialize() never receives _ready(), so the bare-script form runs
## nothing, prints nothing and exits 0 -- which looks exactly like a pass.
##
## Everything here is a claim the GUT suite structurally cannot make. Those tests
## substitute a scripted probe, which means they prove the builder does the right thing
## with the answers it is given; they cannot prove that a swept BoxShape3D cast through
## real Jolt geometry gives those answers. The classification in section 13.2 is
## entirely a statement about real collision shapes, so it has to be checked against
## real ones.
##
## THE SLOT CHECK IS THE IMPORTANT ONE. Every other assertion below fails loudly if the
## module breaks. An edge across the 1 x 1 slot fails NOTHING -- the alien simply gains
## a route it should not have, moves more effectively, and looks better while doing it.

## Points sampled along an edge when testing whether it passes through a volume. The
## shortest volume here is 1 m across and the longest edge is 8 m, so 32 samples put a
## sample inside any traversed opening with room to spare.
const SEGMENT_SAMPLES: int = 32

var _failures: int = 0
var _navigation: CreatureNavigation = null


func _ready() -> void:
	NavigationSandboxGeometry.build(self)
	_navigation = CreatureNavigation.new()
	_navigation.config = NavigationConfig.new()
	add_child(_navigation)

	# Colliders added this frame are not queryable until the physics server has stepped.
	# Baking immediately produces an empty cave and a suite that passes by finding
	# nothing wrong with nothing.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check_bake()
	_check_wide_tunnel()
	_check_tight_tunnel()
	_check_slot()
	_check_chamber_c_isolated()
	_check_routes()
	_check_attachment()
	_check_probe_penetration_guard()
	_check_slip_recovery()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


# ----- checks -----


func _check_bake() -> void:
	var before: int = _failures
	var graph: NavGraph = _navigation.bake_now(NavigationSandboxGeometry.bake_region())
	if graph == null:
		_fail("bake", "bake_now returned null; see the config invariant warnings above")
		return
	if graph.node_count() == 0:
		_fail("bake", "the cave produced no nodes at all")
	if graph.edge_count() == 0:
		_fail("bake", "the cave produced no edges at all")
	_pass_if(
		"bake",
		before,
		(
			"%d nodes, %d edges (%d normal, %d wiggle) from %d samples"
			% [
				graph.node_count(),
				graph.edge_count(),
				_navigation.builder.edges_normal,
				_navigation.builder.edges_wiggle,
				_navigation.builder.samples_taken
			]
		)
	)


## Scenario A. The 6 m tunnel must carry the normal body.
func _check_wide_tunnel() -> void:
	var before: int = _failures
	var through: Array = _edges_through(NavigationSandboxGeometry.WIDE_TUNNEL)
	var normal: int = 0
	for edge: NavEdge in through:
		if edge.type == NavEdge.Type.NORMAL_VOLUME:
			normal += 1
	if normal == 0:
		_fail(
			"wide",
			(
				"no NORMAL_VOLUME edge crosses the 6 m tunnel (%d edges cross it at all)"
				% through.size()
			)
		)
	_pass_if("wide", before, "%d NORMAL_VOLUME edges cross the 6 m tunnel" % normal)


## Scenario B. The 2 m tunnel must carry the squeezed body AND NOT the normal one.
##
## Both halves matter. Only checking for a wiggle edge would pass a build where the
## normal body also fits, which is the whole distinction section 13.2 exists to draw.
func _check_tight_tunnel() -> void:
	var before: int = _failures
	var through: Array = _edges_through(NavigationSandboxGeometry.TIGHT_TUNNEL)
	var wiggle: int = 0
	var normal: int = 0
	for edge: NavEdge in through:
		if edge.type == NavEdge.Type.WIGGLE:
			wiggle += 1
		else:
			normal += 1
	if wiggle == 0:
		_fail("tight", "no WIGGLE edge crosses the 2 m tunnel; the squeezed body cannot fit")
	if normal > 0:
		_fail(
			"tight",
			(
				"%d NORMAL_VOLUME edges cross the 2 m tunnel; the normal body does not fit there"
				% normal
			)
		)

	# SCENARIO B NEEDS THE TUNNEL TO GO SOMEWHERE. Wiggle edges near an opening are not
	# the same claim as a squeeze that gets the alien from one chamber to the other, and
	# a tunnel that dead-ends a third of the way through satisfies every count above.
	# Restricting the walk to the tunnel's own z band keeps the 6 m tunnel out of it.
	var west: bool = false
	var east: bool = false
	var band: AABB = NavigationSandboxGeometry.TIGHT_TUNNEL.grow(3.0)
	for edge: NavEdge in _navigation.graph.all_edges():
		var a: Vector3 = _navigation.graph.node_at(edge.from_id).position
		var b: Vector3 = _navigation.graph.node_at(edge.to_id).position
		if a.z < band.position.z or a.z > band.end.z or b.z < band.position.z or b.z > band.end.z:
			continue
		var mouth_west: float = NavigationSandboxGeometry.TIGHT_TUNNEL.position.x
		var mouth_east: float = NavigationSandboxGeometry.TIGHT_TUNNEL.end.x
		west = west or (minf(a.x, b.x) < mouth_west and maxf(a.x, b.x) > mouth_west)
		east = east or (minf(a.x, b.x) < mouth_east and maxf(a.x, b.x) > mouth_east)
	if not west or not east:
		_fail(
			"tight",
			(
				"the 2 m tunnel does not span the divider on its own (west mouth crossed: %s, east: %s)"
				% [west, east]
			)
		)

	_pass_if(
		"tight",
		before,
		"%d WIGGLE edges, no normal ones, and the tunnel spans both mouths" % wiggle
	)


## Scenarios C and G, and Invariant 5. Nothing may cross a 1 m slot.
func _check_slot() -> void:
	var before: int = _failures
	var through: Array = _edges_through(NavigationSandboxGeometry.SLOT)
	if through.size() > 0:
		var kinds := PackedStringArray()
		for edge: NavEdge in through:
			kinds.append(NavEdge.type_name(edge.type))
		_fail("slot", "%d edges cross the 1 m slot (%s)" % [through.size(), ", ".join(kinds)])
	_pass_if("slot", before, "no edge crosses the 1 m slot")


## Scenario G's other half: the world topology DOES recognise chamber C as open space.
##
## A cave where chamber C simply had no nodes would pass the slot check for the wrong
## reason, and would keep passing it if candidate rejection broke completely.
func _check_chamber_c_isolated() -> void:
	var before: int = _failures
	var graph: NavGraph = _navigation.graph
	var in_c: Array = []
	var in_a: int = -1
	for id: Variant in graph.node_ids():
		var at: Vector3 = graph.node_at(id).position
		if NavigationSandboxGeometry.CHAMBER_C.has_point(at):
			in_c.append(id)
		elif in_a < 0 and at.x < NavigationSandboxGeometry.WIDE_TUNNEL.position.x:
			in_a = id

	if in_c.is_empty():
		_fail("chamber_c", "chamber C has no nodes; the slot check above proves nothing")
	if in_a < 0:
		_fail("chamber_c", "chamber A has no nodes")
		return

	var reachable: Dictionary = graph.reachable_from(in_a)
	var leaked: int = 0
	for id: Variant in in_c:
		if reachable.has(id):
			leaked += 1
	if leaked > 0:
		_fail("chamber_c", "%d chamber C nodes are reachable from chamber A" % leaked)
	_pass_if("chamber_c", before, "chamber C has %d nodes and none are reachable" % in_c.size())


func _check_routes() -> void:
	var before: int = _failures
	var a: Vector3 = NavigationSandboxGeometry.CHAMBER_A_CENTER
	var to_b: NavRoute = _navigation.plan_route(a, NavigationSandboxGeometry.CHAMBER_B_CENTER)
	if to_b.status != NavRoute.Status.COMPLETE:
		_fail("routes", "chamber A -> B came back %s, not complete" % to_b.status_name())
	# Section 14: with a 6 m tunnel available, paying the squeeze penalty for the 2 m one
	# would mean the cost model is not comparing traversal times.
	elif to_b.requires_squeeze():
		_fail("routes", "chamber A -> B chose the tight tunnel despite the wide one being open")

	var to_c: NavRoute = _navigation.plan_route(a, NavigationSandboxGeometry.CHAMBER_C_CENTER)
	if to_c.status != NavRoute.Status.PARTIAL:
		_fail(
			"routes",
			"chamber A -> C came back %s; section 40.4 wants a partial route" % to_c.status_name()
		)
	elif NavigationSandboxGeometry.CHAMBER_C.has_point(to_c.anchors[-1]):
		_fail("routes", "the partial route to chamber C ends INSIDE chamber C")

	var across: NavRoute = _navigation.plan_route(a, NavigationSandboxGeometry.CHAMBER_A_FAR)
	if across.status != NavRoute.Status.COMPLETE:
		_fail("routes", "the ~23 m crawl across chamber A came back %s" % across.status_name())
	_pass_if("routes", before, "A->B complete and normal, A->C partial, A->A_far complete")


## Section 16 against real geometry: attachment lands in the chamber the query is in.
func _check_attachment() -> void:
	var before: int = _failures
	var attached: Dictionary = _navigation.planner.attach(
		NavigationSandboxGeometry.CHAMBER_A_CENTER, _navigation.graph
	)
	if not attached["ok"]:
		_fail("attach", "the centre of chamber A attached to nothing")
	else:
		var at: Vector3 = _navigation.graph.node_at(attached["id"]).position
		if at.x >= NavigationSandboxGeometry.WIDE_TUNNEL.position.x:
			_fail(
				"attach",
				"the centre of chamber A attached to a node at x=%.1f, through the divider" % at.x
			)
	_pass_if("attach", before, "chamber A attaches to a chamber A node")


## The cast_motion penetration guard in NavigationProbe, against a real overlap.
##
## Without it, a sweep starting inside geometry returns [0, 0] -- identical to a
## legitimate immediate block -- and every edge from a node the builder placed slightly
## inside a wall fails validation with nothing in the log.
func _check_probe_penetration_guard() -> void:
	var before: int = _failures
	# Solidly inside divider 1, which is unbroken rock north of the tight tunnel.
	var inside := Vector3(19.0, 4.0, 25.0)
	var profile: ClearanceProfile = _navigation.config.clearance_profile
	var mask: int = _navigation.config.world_mask
	if _navigation.probe.shape_fits(
		profile.squeezed_body(), Transform3D(Basis.IDENTITY, inside), mask
	):
		_fail("probe", "a point inside the divider reports the squeezed body as fitting")
	if _navigation.probe.shape_sweep_clear(
		profile.squeezed_body(), inside, inside + Vector3(0, 0, 6), mask
	):
		_fail("probe", "a sweep starting inside the divider reported clear")
	_pass_if("probe", before, "an overlapping origin is refused rather than reported clear")


## Invariant 3's other half, against real geometry: a body that has slipped off every
## surface gets itself back to one.
##
## THIS CHECK EXISTS BECAUSE THE FAILURE IT GUARDS SHIPPED, TWICE OVER. With nothing inside
## `crawl_surface_reach` the crawler refuses on its first line, the planner stalls
## NO_SURFACE, a stall is zero speed, and zero speed cannot move the body out of the pose
## that caused the stall. The alien is then finished for the rest of the run while holding a
## COMPLETE route and reporting a perfectly plausible mode.
##
## THE SANDBOX'S OWN CHAMBER A CENTRE IS ALREADY SUCH A POSE, which is worth saying plainly:
## the middle of an ordinary 8 m-tall room is 4 m from its floor and 4 m from its ceiling,
## against a 3.5 m reach. Being unsupported here is not an exotic accident, it is what the
## middle of a room IS, and until now the alien could not survive arriving in one.
##
## Asserted in three parts, because each can break without the others. That the pose really
## is unsupported (or the rest proves nothing); that `is_slipped` says so; and that the
## planner answers with motion toward terrain rather than with a stall.
func _check_slip_recovery() -> void:
	var before: int = _failures
	var config: NavigationConfig = _navigation.config
	var at: Vector3 = NavigationSandboxGeometry.CHAMBER_A_CENTER
	var planner: NavLocalPlanner = _navigation.local_planner
	var reading: NavSurfaceReading = planner.surface.sample(
		at, _navigation.probe, config.locomotion_profile, config.world_mask
	)
	if reading.has_surface():
		_fail(
			"slip",
			(
				"the centre of chamber A has terrain %.2f m away, so it is not the unsupported pose this check needs"
				% reading.nearest_distance()
			)
		)
		return
	if not NavLocalPlanner.is_slipped(reading, false):
		_fail("slip", "an unsupported, non-airborne body did not read as slipped")
	if NavLocalPlanner.is_slipped(reading, true):
		_fail(
			"slip", "an AIRBORNE unsupported body read as slipped; Invariant 3 permits exactly that"
		)

	var found: NavSurfaceSample = planner.surface.reacquire(
		at, _navigation.probe, config.locomotion_profile, config.world_mask
	)
	if found == null:
		_fail("slip", "the recovery fan found no surface anywhere in a closed cave")
		return

	var body := NavBodyState.make(at, Vector3.FORWARD, Vector3.UP)
	var follower := RouteFollower.new(config, _navigation.probe)
	follower.set_route(_navigation.plan_route(at, NavigationSandboxGeometry.CHAMBER_B_CENTER))
	var command: NavMotionCommand = planner.plan_next_motion(
		body, follower, 0.05, _navigation.probe, config
	)
	if command.is_stalled():
		_fail(
			"slip",
			(
				"a slipped body stalled with %s instead of recovering"
				% NavMotionCommand.abort_name(command.abort)
			)
		)
	elif not command.recovering:
		_fail("slip", "the slipped body was given an ordinary command rather than a recovery")
	elif command.desired_speed <= 0.0:
		_fail("slip", "the recovery command asks for zero speed, which never leaves the pose")
	elif command.desired_direction.dot(found.direction) <= 0.0:
		_fail("slip", "the recovery heads away from the nearest surface it found")
	_pass_if(
		"slip",
		before,
		"an unsupported body reacquires terrain %.1f m away rather than stalling" % found.distance
	)


# ----- helpers -----


## Every edge whose straight line passes through `volume`.
func _edges_through(volume: AABB) -> Array:
	var found: Array = []
	var graph: NavGraph = _navigation.graph
	if graph == null:
		return found
	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for sample: int in SEGMENT_SAMPLES + 1:
			var at: Vector3 = from.lerp(to, float(sample) / float(SEGMENT_SAMPLES))
			if volume.has_point(at):
				found.append(edge)
				break
	return found


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		print("[%-10s] PASS  %s" % [tag, message])
