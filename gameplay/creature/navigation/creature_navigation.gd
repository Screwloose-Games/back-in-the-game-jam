class_name CreatureNavigation
extends Node3D

## The facade the rest of the alien AI talks to (navigation.md sections 17, 33, 37).
##
## Answers exactly one question: HOW COULD I GET THERE, GIVEN WHAT I BELIEVE? It does
## not decide where to go -- section 33 puts that in the behaviour system, which hands
## navigation a goal -- and IT DOES NOT MOVE THE BODY. Sections 20-23 decide what the body
## should do and emit it as `motion_planned`; something else applies it. That boundary is
## what lets the body be a CharacterBody3D, a kinematic node, or a Vector3 in a test.
##
## What this class owns:
##
##     the probe binding             the one call to get_world_3d in the module
##     the frame-budgeted bake       section 32
##     the frame-budgeted patch      section 24.2
##     the replan triggers           section 31
##     the current route             sections 17, 18
##     one tick of local planning    section 20
##
## THE GRAPH IS A FIELD, NOT A SECRET, and sections 26-27's split is a matter of which
## NavGraph it points at. `world_graph` is what the bake and the patcher fill -- section
## 26's authoritative terrain. `graph` is THE PLANNING GRAPH, and is the only one anything
## downstream reads. `use_knowledge` chooses between them.
##
## IT DEFAULTS OFF, AND THAT IS A COMPATIBILITY DECISION RATHER THAN A TIMID ONE. With it
## off, `graph` IS `world_graph` and the alien is omniscient about geometry, which is
## exactly how phases 1-7 behaved; every unit test, every runtime check and the sandbox
## are unaffected by phase 8 existing. With it on, `graph` is `knowledge.project()` and
## Invariant 9 holds. Not one line of `graph/` or `route/` differs between the two.
##
## REPLANNING IS EVENT DRIVEN (section 31). "Do not continuously calculate full paths
## every frame" -- not because A* is expensive at this graph size (section 15 says it
## is not), but because a route recomputed every frame is a route the locomotion layer
## can never finish a manoeuvre against, and the monotonic index in RouteFollower is
## reset by every replan.

## The bake finished. Carries the graph so a consumer does not have to guess when to read
## it.
signal graph_baked(graph: NavGraph)
## A new route replaced the current one. Fires on every replan, including one that
## produces the same anchors.
signal route_changed(route: NavRoute)
## Section 30. See NavInspectionRequest for who is expected to listen and why nothing
## in this module does.
signal inspection_requested(request: NavInspectionRequest)
## Section 20's output, once per tick, for whatever is moving the body.
##
## A SIGNAL RATHER THAN A RETURN VALUE, because `advance()` is also called by
## `_physics_process` and a body that had to poll would be a frame behind on the ticks it
## did not drive. Fires only while there is a route to execute.
signal motion_planned(command: NavMotionCommand)
## Section 24.2 finished a local patch. Carries what changed, so a consumer does not have
## to diff the graph to find out.
signal graph_patched(result: NavPatchResult)
## The locomotion mode changed. Carries both, because "it started wiggling" and "it
## stopped swimming" are different things to an animation system.
signal mode_changed(previous: NavLocomotion.Mode, current: NavLocomotion.Mode)

@export var config: NavigationConfig = null
## Bake this region on _ready. Zero size means "wait for an explicit bake() call",
## which is what the sandbox and both verifiers do. Ignored when `source` is set -- the
## level bakes, not the creature.
@export var bake_region: AABB = AABB()
## THE LEVEL'S BAKE, if there is one. When set, this navigator stops building a graph and
## consumes the source's instead: N creatures cost one bake of one graph rather than N
## bakes of N identical ones, and one patcher handles the mining hole rather than N racing
## over it.
##
## NULL IS EVERY PHASE 1-7 BEHAVIOUR, EXACTLY, and that is what keeps tests/, the sandbox,
## both runtime verifiers and the original demo untouched by this existing. What stays
## per-creature either way: the route, the believed graph, the inspection chain, the
## locomotion planner, and this navigator's OWN probe -- see NavigationSource on why the
## probe is not shared.
@export var source: NavigationSource = null
## Section 27. Plan against belief rather than against the world.
##
## OFF BY DEFAULT so that turning phase 8 on is a decision rather than a side effect --
## see the class docstring. Turning it on mid-run is legal and takes effect on the next
## replan.
@export var use_knowledge: bool = false

## Section 26. What the bake and the patcher fill: the cave as it actually is.
var world_graph: NavGraph = null
## THE PLANNING GRAPH. Either `world_graph` or `knowledge.project()`, per `use_knowledge`.
var graph: NavGraph = null
## Section 27. What the alien believes, which is allowed to be wrong and out of date.
var knowledge: NavKnowledgeGraph = null
## Sections 29-30. Public field so behaviour can read the state it is meant to animate.
var inspector: NavInspector = null
## Section 35. Its `rng.seed` is set from `config.route_seed` in _apply_config.
var chooser: NavRouteChooser = null
var route: NavRoute = null
var probe: NavigationProbe = null
var planner: RoutePlanner = null
var follower: RouteFollower = null
var builder: NavGraphBuilder = null
## Section 24. Public field for the same reason the rest are.
var patcher: NavGraphPatcher = null
## Section 20. Public as a field rather than wrapped in methods, the way `planner` and
## `follower` already are -- it keeps this class under gdlint's public-method cap and
## lets a consumer read `local_planner.mode()` without the facade growing a getter per
## thing worth knowing.
var local_planner: NavLocalPlanner = null
## Section 40's backstop. Public field for the same reason the rest are, and read by the
## prototype HUD -- `progress.trips` climbing is the single most useful number in the scene
## when the alien is behaving oddly.
var progress: NavProgressMonitor = null
## What the body reported last tick, and what was decided from it.
var body_state: NavBodyState = null
var command: NavMotionCommand = null

var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
## The goal the current route was planned against, which is not `_goal` once the target
## has moved. The difference is section 31's movement trigger.
var _planned_goal: Vector3 = Vector3.ZERO
var _replan_countdown: float = 0.0
## Whether the alien has already investigated being unable to reach where it is going, and
## the goal and terrain revision it investigated it for. Section 30's STALE_ROUTE is a
## DISCOVERY, and a thing is discovered once -- see `_report_stale_route`.
var _unreachable_investigated: bool = false
var _unreachable_goal: Vector3 = Vector3.ZERO
var _unreachable_revision: int = -1
var _body_position: Vector3 = Vector3.ZERO
## Navigation's own clock, accumulated from the delta it is handed. NOT a wall clock --
## verify_navigation_static.gd forbids one, and a knowledge layer that aged on
## Time.get_ticks_msec() would keep ageing while the game was paused.
var _clock: float = 0.0


func _init() -> void:
	# Built here rather than in _ready(), so a facade created with .new() and never
	# added to a tree is fully usable. That is what lets the whole planning path be
	# tested in GUT with a fake probe and no scene.
	probe = NavigationProbe.new()
	planner = RoutePlanner.new()
	follower = RouteFollower.new()
	builder = NavGraphBuilder.new()
	patcher = NavGraphPatcher.new()
	local_planner = NavLocalPlanner.new()
	progress = NavProgressMonitor.new()
	knowledge = NavKnowledgeGraph.new()
	inspector = NavInspector.new()
	chooser = NavRouteChooser.new()
	body_state = NavBodyState.make(Vector3.ZERO, Vector3.FORWARD, Vector3.UP)


func _ready() -> void:
	if config == null:
		config = NavigationConfig.new()
		push_warning("CreatureNavigation has no NavigationConfig; running on script defaults.")
	_apply_config()
	# ONE OF THE TWO get_world_3d CALLS IN THE MODULE, the other being NavigationSource's.
	# Everything else reaches the world through NavigationProbe, and
	# verify_navigation_static.gd fails the build if a third appears.
	probe.bind(get_world_3d())
	if source != null:
		_attach_to_source()
		return
	if bake_region.size.length_squared() > 0.0:
		bake(bake_region)


## Subscribes to the level's bake, and catches up on one that already happened.
##
## THE CATCH-UP IS NOT AN EDGE CASE. A creature spawned after the level finished baking --
## which is every creature in a level that bakes on load -- never receives `graph_baked`,
## so without this it plans against a null graph for the rest of the run. It does not error
## and it does not warn: `advance()` simply returns early, forever, and the alien stands
## there looking like a behaviour bug.
func _attach_to_source() -> void:
	source.graph_baked.connect(_on_source_baked)
	source.graph_patched.connect(_on_source_patched)
	if source.world_graph != null:
		_on_source_baked(source.world_graph)


func _on_source_baked(baked: NavGraph) -> void:
	world_graph = baked
	_publish_bake()
	_publish_planning_graph()


func _on_source_patched(result: NavPatchResult) -> void:
	_apply_patch_result(result)


func _physics_process(delta: float) -> void:
	advance(delta)


## The single tick entry point, public so a test or a headless tool can drive it
## exactly. Takes the body position rather than reading `global_position`, because the
## navigator is not necessarily parented to the thing it is navigating.
func advance(delta: float, body_position: Variant = null) -> void:
	if body_position != null:
		_body_position = body_position
	_clock += delta
	_step_bake()
	_step_patch()
	knowledge.age(delta, config if config != null else NavigationConfig.new())
	_step_inspection(delta)
	_publish_planning_graph()
	if not _has_goal or graph == null:
		return

	_replan_countdown -= delta
	var target_drifted: bool = _planned_goal.distance_to(_goal) > config.target_move_threshold
	if route == null or target_drifted or _replan_countdown <= 0.0:
		_replan()
	if route != null:
		follower.advance(_body_position)
	_step_locomotion(delta)


## Binds a world explicitly, for headless tools that build a tree by hand.
func bind_world(world: World3D) -> void:
	probe.bind(world)


## Starts a frame-budgeted bake over `region` (sections 12, 13, 32).
##
## The graph is only swapped in when the bake COMPLETES. Publishing a half-built graph
## would let a route plan through a region whose edges have not been validated yet, and
## the result looks like a pathfinding bug rather than a race.
func bake(region: AABB) -> void:
	if config == null:
		config = NavigationConfig.new()
	_apply_config()
	if source != null:
		# FORWARDED RATHER THAN REFUSED, because the sandbox's rebake key and the demo's
		# reset both go through here and neither knows whether a level owns the graph.
		source.bake(region)
		return
	builder.begin(region, config, probe)
	for line: String in builder.failures:
		push_warning("CreatureNavigation cannot bake: %s" % line)


## Bakes to completion on the calling frame. For headless tools and tests, where the
## section 32 frame budget is meaningless because there are no frames.
func bake_now(region: AABB) -> NavGraph:
	if source != null:
		var built: NavGraph = source.bake_now(region)
		if built == null:
			return null
		_on_source_baked(built)
		return graph
	bake(region)
	if not builder.failures.is_empty():
		return null
	world_graph = builder.build_now()
	_publish_bake()
	_publish_planning_graph()
	return graph


## Whether a bake is in flight ANYWHERE that would make patching unsafe.
##
## The source branch is not cosmetic: `_step_patch` guards on this, and a creature that
## answered for its own idle builder would queue patches against a shared graph the level
## is still building. That race has no symptom other than a cave that is subtly wrong.
func is_baking() -> bool:
	if source != null:
		return source.is_baking()
	return (
		builder.stage != NavGraphBuilder.Stage.IDLE and builder.stage != NavGraphBuilder.Stage.DONE
	)


## Everything the section 39 overlay wants about the bake, from whichever thing is doing it.
func bake_stats() -> Dictionary:
	return source.stats() if source != null else builder.stats()


func bake_progress() -> float:
	return source.progress() if source != null else builder.progress()


## Section 33. The behaviour system says where; navigation works out how.
func set_goal(target: Vector3) -> void:
	_goal = target
	_has_goal = true
	# Force the next advance() to replan rather than waiting out the pursuit timer. A
	# new goal is the one trigger that must not be delayed.
	_replan_countdown = 0.0
	route = null
	# A new goal means the seconds the body spent going nowhere toward the old one say
	# nothing about this one.
	progress.reset()


func clear_goal() -> void:
	_has_goal = false
	route = null
	follower.set_route(null)
	progress.reset()


## Everything locomotion needs to know about the body this tick (section 20).
##
## Separate from `set_body_position` on purpose. Phases 1-2 only ever needed a point, and
## the sandbox and both verifiers still pass one; a crawler needs a facing and a velocity
## as well, and section 22's turn constraint is meaningless without the second.
func set_body_state(at: Vector3, velocity: Vector3, forward: Vector3, up: Vector3) -> void:
	_body_position = at
	body_state.position = at
	body_state.velocity = velocity
	body_state.forward = forward.normalized()
	body_state.up = up.normalized()


func set_body_position(at: Vector3) -> void:
	_body_position = at


## A one-off query that does not disturb the current route. Section 17's request_route.
func plan_route(start: Vector3, target: Vector3) -> NavRoute:
	if graph == null:
		return NavRoute.unreachable(target)
	return planner.plan(start, target, graph)


## Section 30. Public so locomotion can report a failed traversal without reaching into
## this class's internals.
##
## ROUTED THROUGH THE INSPECTOR RATHER THAN EMITTED DIRECTLY, which is what stops the
## request storm: a route that cannot reach its goal raises this on every replan -- twice a
## second, forever, at the same wall -- and before the inspector existed every one of them
## reached whatever was listening. `report` deduplicates by place and time, and refuses
## anything at all while an inspection is already running.
func request_inspection(at: Vector3, reason: NavInspectionRequest.Reason) -> void:
	if config == null:
		config = NavigationConfig.new()
	var request := NavInspectionRequest.make(at, reason, config.chunk_size)
	if inspector.report(request, _clock, config):
		inspection_requested.emit(request)


## Section 30's callback: behaviour has finished looking. Until this is called (or the
## timeout fires) nothing is learned, which is the whole of "delayed acquisition".
func inspection_completed() -> void:
	inspector.complete()


## Everything a debug readout wants that it cannot compute for itself, in one dictionary
## rather than a dozen accessors -- the trade `CrawlerBody.debug_state()` names in its own
## docstring, and what keeps this facade under gdlint's public-method cap.
##
## THERE IS NO `goal_drift` KEY, AND THAT IS THE INTERESTING OMISSION.
## `_planned_goal.distance_to(_goal)` looks like the perfect number for an alien that will
## not settle, and it is dead: `set_goal` zeroes `_replan_countdown` and nulls the route, so
## `advance` replans on the very next tick and `_planned_goal` is `_goal` again. It reads ~0
## during exactly the replan storm it would exist to catch. `route.target_position` is the
## same value by another name and is equally dead. How fast the BEHAVIOUR goal moves is the
## live number, and only Behavior can measure that.
func debug_state() -> Dictionary:
	var usable: bool = follower != null and follower.has_route()
	return {
		"has_goal": _has_goal,
		"goal": _goal,
		"replan_in": _replan_countdown,
		"clock": _clock,
		"baking": is_baking(),
		"bake_progress": bake_progress(),
		"graph_nodes": graph.node_count() if graph != null else 0,
		"route_status": route.status_name() if route != null else "none",
		"anchor_index": follower.index if follower != null else 0,
		"anchor_count": maxi(route.anchors.size() - 1, 0) if route != null else 0,
		"anchor": follower.current_anchor() if usable else Vector3.ZERO,
		"has_anchor": usable,
		# INF rather than 0.0 with no route. RouteFollower returns 0.0, and 0.0 reads as
		# "arrived" -- the trap CreatureBehavior._route_distance() documents at :283.
		"distance_remaining": follower.distance_remaining(_body_position) if usable else INF,
		"shortfall": _route_shortfall(),
		"mode": NavLocomotion.mode_name(local_planner.mode()),
		"stalled": command != null and command.is_stalled(),
		"abort": NavMotionCommand.abort_name(command.abort) if command != null else "none",
		"trips": progress.trips,
		"moved": progress.moved,
	}


# ----- internals -----


## How far short of its target a PARTIAL route stops. Zero for any other status.
##
## THE NUMBER FOR "THE ALIEN DOES NOT FIT". A route that ends 20 m short is not a routing
## bug, it is a body that cannot enter the passage -- and with
## `squeezed_radius_equivalent == normal_radius_equivalent` on a creature, squeezing buys
## nothing and every sweep needs the full bore.
func _route_shortfall() -> float:
	if route == null or route.status != NavRoute.Status.PARTIAL or route.anchors.is_empty():
		return 0.0
	return route.anchors[route.anchors.size() - 1].distance_to(route.target_position)


## One tick of section 20, and the two section 31 triggers locomotion owns.
##
## RUNS AFTER `follower.advance()`, so the anchor the planner steers toward is the one
## smoothing settled on this frame rather than last frame's.
func _step_locomotion(delta: float) -> void:
	if route == null or not follower.has_route():
		return
	body_state.position = _body_position
	body_state.mode = local_planner.mode()
	body_state.squeezed = local_planner.wiggler.is_squeezed()

	var previous: NavLocomotion.Mode = local_planner.mode()
	command = local_planner.plan_next_motion(body_state, follower, delta, probe, config)
	if (
		inspector.should_hold_still()
		and not local_planner.is_airborne()
		and not command.is_stalled()
	):
		# Section 29: the alien stops, orients and looks before it absorbs anything. Without
		# this the whole chain is four states of bookkeeping the player never sees, because
		# the creature investigates a wall at full crawl speed while facing away from it.
		#
		# A leap in progress is exempt -- Invariant 4 says a trajectory cannot be altered
		# once begun, and stopping mid-air is an alteration.
		#
		# A STALLED COMMAND IS EXEMPT TOO, and not merely because it already asks for zero
		# speed. It carries the section 40 reason the locomotion layer stopped, and
		# replacing it with a blank hold erases the one piece of evidence that says WHY --
		# leaving an alien that is visibly stuck and reports only "inspecting".
		command = NavMotionCommand.make(command.mode, Vector3.ZERO, 0.0, _body_position)
	var reading: NavSurfaceReading = local_planner.last_reading()
	if reading != null:
		body_state.attached = reading.has_surface()
		body_state.surface_normal = reading.dominant_normal
		body_state.clearance = reading.nearest_distance()

	if local_planner.mode() != previous:
		mode_changed.emit(previous, local_planner.mode())
	motion_planned.emit(command)
	_react_to(command)
	_watch_progress(delta)


## Section 40's backstop, and the one check that does not care WHY the body stopped.
##
## Every other failure detector in the module is keyed to a cause. This one is keyed to the
## outcome, which is what makes it useful against the causes nobody has found yet: a body
## that has covered less than `progress_threshold` in `progress_window` while holding a
## usable route is wedged, whatever it believes it is doing.
##
## THE RESPONSE IS TO FORGET EVERYTHING LOCAL AND ASK AGAIN. `reset_mode` drops the dwell
## timer and any mode the body was committed to, the countdown forces a replan on the next
## tick, and the inspection request tells the behaviour layer something is wrong here. A
## body held still on purpose is excluded rather than waited out -- section 29's inspection
## and section 43's Scenario B squeeze are both legitimate stillness, and a watchdog tuned
## to outlast them would eventually be tuned to outlast the failures too.
func _watch_progress(delta: float) -> void:
	# A STALL COUNTS AS TRYING, and that is the whole point. Both aliens that wedged
	# permanently were emitting a stall every tick and going nowhere; excluding stalls here
	# would exclude exactly the failure this exists to catch. The two genuine stillnesses
	# are an inspection in progress and a body compressing in place before a squeeze.
	var compressing: bool = command.squeeze and command.desired_speed <= 0.0
	var trying: bool = not inspector.should_hold_still() and not compressing
	if not progress.note(_body_position, delta, trying, config):
		return
	local_planner.reset_mode()
	_replan_countdown = 0.0
	request_inspection(_body_position, NavInspectionRequest.Reason.FAILED_TRAVERSAL)


## Section 40's local failures, turned into the section 30 requests the behaviour layer
## listens for, plus section 31's landing trigger.
func _react_to(motion: NavMotionCommand) -> void:
	if local_planner.has_landed():
		# Section 31, "locomotion transition requires reconsideration". A body 20 m along
		# its own route has a follower index that describes a journey it did not take, and
		# sections 18 and 40.1 forbid fixing that by re-picking the nearest anchor.
		_replan_countdown = 0.0
	if motion == null or not motion.is_stalled():
		return
	match motion.abort:
		NavMotionCommand.Abort.CREVICE_GRIND:
			request_inspection(_body_position, NavInspectionRequest.Reason.FAILED_TRAVERSAL)
		NavMotionCommand.Abort.NO_FIT:
			request_inspection(_body_position, NavInspectionRequest.Reason.FAILED_TRAVERSAL)
		NavMotionCommand.Abort.NO_SURFACE:
			request_inspection(_body_position, NavInspectionRequest.Reason.GEOMETRY_MISMATCH)
		NavMotionCommand.Abort.BLOCKED:
			# A traversal that failed, not a cave that is not what the alien believed. The
			# geometry here is exactly what it looks like; the body simply cannot get out of
			# the pose it is in, which is the same class of problem as a crevice that grinds.
			request_inspection(_body_position, NavInspectionRequest.Reason.FAILED_TRAVERSAL)


## Section 24.2 step 1. Tell navigation that terrain inside `region` has changed.
##
## THE ONLY WAY TERRAIN CHANGE ENTERS THIS MODULE, and it is a notification rather than a
## query: navigation cannot detect mining, and a module that polled for it would be
## re-measuring the whole cave forever on the chance that something moved.
func notify_terrain_changed(region: AABB) -> void:
	if config == null:
		config = NavigationConfig.new()
	if source != null:
		source.notify_terrain_changed(region)
		return
	patcher.mark_dirty(region, config)


## One frame of section 24.2, budgeted separately from the bake.
##
## SKIPPED ENTIRELY WHILE A BAKE IS RUNNING. Both drive a NavGraphBuilder and both spend
## probe queries; letting them overlap means patching a graph that is still being built,
## which is a race with no symptom other than a cave that is subtly wrong.
func _step_patch() -> void:
	# The level owns the patcher when there is a source, exactly as it owns the builder.
	if source != null or is_baking() or graph == null or not patcher.has_work():
		return
	probe.reset_query_count()
	var result: NavPatchResult = patcher.step(graph, config.patch_queries_per_frame, config, probe)
	if result == null:
		return
	_apply_patch_result(result)


## What a completed patch means to THIS creature, whoever ran it.
func _apply_patch_result(result: NavPatchResult) -> void:
	graph_patched.emit(result)
	# Section 31: new topology near the current route is a reason to reconsider it. Not a
	# reason to reconsider knowledge -- Invariant 8 keeps those separate, and phase 8's
	# believed graph is not what was just patched.
	if route != null and not result.is_empty():
		_replan_countdown = 0.0


## Points `graph` at whichever source `use_knowledge` selects.
##
## Runs every tick and costs nothing when nothing changed: `project()` returns its cache
## unless a belief actually moved. The alternative -- swapping on the flag's setter -- has
## to handle a bake completing, a patch landing, an observation arriving and the flag
## itself, which is four places to forget.
## Section 29's chain, and the one place knowledge is allowed to absorb the world.
func _step_inspection(delta: float) -> void:
	if config == null:
		config = NavigationConfig.new()
	inspector.advance(delta, config)
	if not inspector.is_relearn_ready():
		return
	# THE END OF RELEARNING, and nowhere else. Section 43's Scenario J asserts that the
	# believed graph is unchanged at every earlier point in the chain.
	#
	# CONNECTED, not a ball: one continuous section of new geometry is one thing to
	# investigate, and a ball resolves the first `relearn_radius` of it and leaves the alien
	# to stop again a few metres further in.
	knowledge.learn_connected_region(world_graph, inspector.relearn_at(), config, _clock)
	# Section 29's REPLANNING beat: the alien now believes something new, so the route it
	# was following was planned against a cave it no longer thinks it is in.
	_replan_countdown = 0.0


func _publish_planning_graph() -> void:
	if not use_knowledge:
		graph = world_graph
		return
	if config == null:
		config = NavigationConfig.new()
	graph = knowledge.project(config)


## Section 9 of spatial_memory. Wire it to perception with the line its README writes:
##
##     perception.geometry_observed.connect(navigation.observe_geometry_batch)
##
## ONE ARGUMENT, because that is what the signal emits. The clock is this class's own, and
## the observations carry perception's -- see NavKnowledgeGraph on why those stay apart.
func observe_geometry_batch(observations: Array) -> void:
	if config == null:
		config = NavigationConfig.new()
	var update: NavKnowledgeUpdate = knowledge.observe_geometry_batch(observations, config)
	if not update.wants_inspection():
		return
	# Section 29: a contradiction is "was I wrong?", an opening is "what is that?". Both
	# stop the alien and neither is acted on until an inspection completes.
	for at: Vector3 in update.contradictions:
		request_inspection(at, NavInspectionRequest.Reason.GEOMETRY_MISMATCH)
	for at: Vector3 in update.suspected_openings:
		request_inspection(at, NavInspectionRequest.Reason.UNKNOWN_OPENING)


func _apply_config() -> void:
	planner.config = config
	planner.probe = probe
	follower.config = config
	follower.probe = probe
	# Section 19's surface-crawl and leap checks. Shared with the local planner rather
	# than duplicated, so smoothing and steering cannot disagree about what the alien can
	# do -- a shortcut approved by one sampler and executed by another is how an alien
	# ends up gliding across a chamber it was supposed to crawl around.
	# Section 35's determinism. RandomNumberGenerator randomises itself on construction, so
	# without this a route differs between two runs of the same scenario -- which is the
	# one kind of bug in this module nobody could reproduce.
	chooser.rng.seed = config.route_seed
	follower.surface = local_planner.surface
	follower.leaper = local_planner.leaper


func _step_bake() -> void:
	# The level's bake is the level's to step. Two creatures each calling builder.step() on
	# a shared builder would spend twice the section 32 budget and interleave their pacing,
	# which is the whole reason NavigationSource exists.
	if source != null or not is_baking():
		return
	probe.reset_query_count()
	if builder.step(config.bake_queries_per_frame):
		world_graph = builder.graph
		_publish_bake()
		# Republish immediately rather than waiting for the next tick, so a caller that
		# bakes and then reads `graph` on the same frame -- which both verifiers do -- sees
		# the cave rather than null.
		_publish_planning_graph()


func _publish_bake() -> void:
	# A source warns about its own truncation, so warning again here would double every line.
	if source == null and builder.truncated:
		push_warning(
			(
				"Navigation bake hit the %d-sample lattice cap; part of the region was not covered."
				% NavGraphBuilder.MAX_LATTICE_SAMPLES
			)
		)
	# Section 20 of spatial_memory. A creature that has lived here knows the shape of the
	# cave; what it does not know is what has changed since. Seeding belief from the first
	# bake is what makes "the alien is wrong about the NEW passage" the interesting case
	# rather than "the alien knows nothing at all".
	if config != null and config.knowledge_starts_known:
		knowledge.learn_all(world_graph, _clock)
	# A bake replaces the topology outright rather than patching it, so whatever the alien
	# concluded about not being able to get somewhere was concluded about a different cave.
	_unreachable_investigated = false
	graph_baked.emit(world_graph)


## Section 35. One route when alternatives are switched off, otherwise a probabilistic
## choice among the ones worth choosing.
##
## The alternatives come from attaching at different nodes rather than from re-running A*
## with penalties -- see `RoutePlanner.attach_all` for why that produces routes that
## actually differ.
func _choose_route() -> NavRoute:
	var direct: NavRoute = planner.plan(_body_position, _goal, graph)
	if config.route_alternatives <= 1 or not direct.is_usable():
		return direct
	var routes: Array[NavRoute] = [direct]
	for id: int in planner.attach_all(_body_position, graph):
		if routes.size() > config.route_alternatives:
			break
		var via: NavRoute = planner.plan(graph.node_at(id).position, _goal, graph)
		if via.is_usable():
			routes.append(via)
	var chosen: NavRoute = chooser.choose(routes, config)
	return chosen if chosen != null else direct


func _replan() -> void:
	_replan_countdown = config.pursuit_interval
	_planned_goal = _goal
	route = _choose_route()
	follower.set_route(route)
	route_changed.emit(route)

	if route.status != NavRoute.Status.COMPLETE:
		_report_stale_route()
	else:
		_unreachable_investigated = false


## A route that cannot reach the goal is section 30's STALE_ROUTE: what the alien believed
## about the topology and what it can actually traverse have diverged, and section 29 wants
## that investigated rather than silently absorbed.
##
## RAISED ON THE DISCOVERY, NOT ON THE CONDITION, and that distinction is a bug fix. This
## used to fire on every replan while the route stayed non-COMPLETE, with the inspector's
## dedupe as the only brake -- and dedupe rate-limits, it does not conclude. A goal behind a
## slot the alien does not fit through is unreachable forever, so the pursuit timer re-asked
## every `pursuit_interval` and every `inspection_dedupe_time` the answer got through: an
## alien frozen for `mismatch_pause_time + inspection_timeout + relearn_time` out of every
## six seconds, investigating a wall it had already investigated, for the rest of the level.
## Worse, the request position is the PARTIAL route's reachable end, which the section 35
## chooser re-picks every replan -- so once it drifted past `inspection_dedupe_radius` even
## the rate limit stopped applying and the inspections ran back to back.
##
## THE LATCH IS NOT A COOLDOWN. Nothing here delays the retry: `_replan` still runs on every
## section 31 trigger and takes a route the instant one exists. What is suppressed is asking
## the behaviour layer to go and look at the same wall again having learned nothing since.
## Only news re-arms it -- a different goal, terrain that changed under it, or a route that
## completed in between.
func _report_stale_route() -> void:
	var revision: int = world_graph.terrain_revision if world_graph != null else 0
	var same_goal: bool = _goal.distance_to(_unreachable_goal) <= config.target_move_threshold
	if _unreachable_investigated and same_goal and revision == _unreachable_revision:
		return
	_unreachable_investigated = true
	_unreachable_goal = _goal
	_unreachable_revision = revision
	var at: Vector3 = route.anchors[-1] if route.anchors.size() > 0 else _body_position
	request_inspection(at, NavInspectionRequest.Reason.STALE_ROUTE)
