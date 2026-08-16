class_name EncounterSandbox
extends Node3D

## behavior.md section 35's whole encounter, running with nothing scripting it.
##
##     unalerted -> investigating (hotspot)   a noise becomes a lead
##             the alien routes to it and sweeps, re-aiming between sweeps
##     investigating -> hunting (candidate)   it sees you
##             it chases the estimate across the chase floor
##             you go into the refuge and direct evidence stops
##             chase gives way to lurk: the route comes back PARTIAL, it stops at the mouth
##             of the slot and waits a length of time it draws rather than one it is told
##     hunting -> retreating (director)       the ENCOUNTER ends, rather than the trail
##             SATED if the lurk filled the meter, STALLED if it never did
##     retreating -> unalerted (separated)
##
## THAT SECOND-TO-LAST LINE USED TO READ `(lost)`, AND THE CHANGE IS THE POINT. Without a
## Director every hunt here ended in suspicion starvation -- the alien gave up because its
## belief ran out, which is a fact about its memory rather than a decision about the scene.
## With one attached the same chase ends because the encounter has delivered what it had to
## deliver, and `disengage_reason` says which of the two exits it earned. `(lost)` still
## happens; it is now the exception rather than the only ending there is.
##
## NO STATE MACHINE IN THIS FILE DRIVES ANY OF THAT. The only inputs are moving and making
## noise; every transition above comes out of Perception, Suspicion, the Director and the HFSM
## disagreeing and agreeing with each other. If a beat needs a keypress, something upstream has
## stopped feeding the next one, and that is the bug this scene exists to show.
##
## FOR THE DIRECTOR ITSELF, USE `gameplay/director/sandbox/director_sandbox.tscn`. This scene
## has one attached so its arc terminates honestly, but it runs on the shipped cadence with no
## way to hurry it -- a lull takes 200 s to fill here. That one adds a clock multiplier, a
## panel showing menace and lull as bars, and a player whose mining you can hold down.
##
## IT BUILDS ITS OWN CAVE, unlike `behavior_sandbox.tscn`, which instantiates suspicion's
## sandbox whole and perception's under that. Their room is 24 x 6 x 24 with a 3 m doorway
## every edge crosses as NORMAL_VOLUME; this scenario needs an opening UNDER 1.5 m and a route
## long enough that a chase reads as one. Getting those from the chain would mean editing an
## inner sandbox to accommodate an outer one -- which is exactly the coupling
## `suspicion_sandbox.gd` says must make the file stop building. So this one does not chain,
## and pays for it by wiring all four facades itself.
##
##     WASD / QE   move the player
##     1 / 2       emit a quiet / loud noise where the player is standing
##     G           toggle the navigation graph overlay
##     F           toggle the scored crawl fan
##     Tab         toggle every overlay at once
##     R           put the creature, the player and the nests back
##
## THE TWO OVERLAY KEYS EARN THEIR PLACE. `G` is how you check the claim the whole scenario
## rests on -- NO EDGE CROSSES THE SLOT. Green is NORMAL_VOLUME, amber is WIGGLE, and the
## refuge should be full of nodes with nothing joining any of them to this side. `F` draws the
## scored crawl fan, which is the ONLY overlay in the project that shows `NavAvoidance.risk`
## changing which way the creature goes: length carries the score, so the winner is simply the
## longest ray, and you can watch it bend around the pillar.
##
## THE MOTOR HERE IS REAL, and that is the difference from `behavior_sandbox.gd`. That scene
## walks route anchors on purpose and says why: consuming `navigation.command` faithfully
## wedged the alien in a doorway after about 45 seconds. The cause is known now and it was
## never a navigation bug -- `WiggleController` answers `stalled(WIGGLE, NO_FIT)` when neither
## body fits AND the body is already compressed, which `NavLocalPlanner` documents as a stall
## carrying a reason the layer above can act on, and the stand-in motor ignored
## `command.abort`. Avoidance only runs inside the locomotion controllers, so a scene meant to
## demonstrate it has no choice but to consume the command properly. See `_drive`.

const CAMERA_HEIGHT: float = 52.0
const PLAYER_SPEED: float = 7.0
const QUIET_LOUDNESS: float = 0.25
const LOUD_LOUDNESS: float = 1.0
const COLOR_NEST := Color(0.30, 0.85, 0.80, 1.0)
const COLOR_GOAL := Color(1.0, 0.55, 0.15, 1.0)
const COLOR_CAVE := Color(0.62, 0.64, 0.78, 1.0)
const COLOR_PLAYER := Color(0.95, 0.75, 0.25, 1.0)
const COLOR_CREATURE := Color(0.55, 0.25, 0.60, 1.0)

var behavior: CreatureBehavior = null
var director: EncounterDirector = null

var _creature: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _navigation: CreatureNavigation = null
var _player: Node3D = null
var _nests: Array[CreatureNest] = []
var _goal_marker: MeshInstance3D = null
var _graph_overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _perception_panel: PerceptionDebugPanel = null
var _suspicion_panel: SuspicionDebugPanel = null
var _behavior_panel: BehaviorDebugPanel = null
var _navigation_panel: NavigationDebugPanel = null
var _director_panel: DirectorDebugPanel = null
var _perception_overlay: PerceptionDebugDraw = null
var _suspicion_overlay: SuspicionDebugDraw = null
## The applied heading, which is what gets reported back to navigation. NEVER
## `command.preferred_forward` -- see `_drive`.
var _forward: Vector3 = Vector3.RIGHT
var _command: NavMotionCommand = null
var _last_abort: NavMotionCommand.Abort = NavMotionCommand.Abort.NONE
var _escaped: bool = false
var _debug_visible: bool = true


func _ready() -> void:
	# The creature BEFORE the cave. CreaturePerception._ready() walks its parent's descendants
	# to build the RID list it excludes from its own line-of-sight rays; build the room first
	# and every wall in it lands on that list, so the alien sees through solid rock and the
	# whole scenario stops meaning anything.
	_build_creature()
	EncounterSandboxGeometry.build(self)
	_draw_cave()
	_build_player()
	_plant_nests()
	_build_belief()
	_build_camera()

	# Colliders added this frame are not queryable until the physics server has stepped, and a
	# bake that runs before it produces a graph filling the cave, walls included.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_build_navigation()
	_build_director()
	_build_behavior()
	_build_debug()
	_prove_the_refuge_is_out_of_reach()


func _process(delta: float) -> void:
	_drive_player(delta)
	if behavior == null or _goal_marker == null:
		return
	var showing: bool = _debug_visible and behavior.goal.has_goal()
	_goal_marker.visible = showing
	if showing:
		_goal_marker.global_position = behavior.goal.committed() + Vector3.UP * 1.5


func _physics_process(delta: float) -> void:
	_drive(delta)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_emit_noise(QUIET_LOUDNESS, &"footstep")
		KEY_2:
			_emit_noise(LOUD_LOUDNESS, &"drill")
		KEY_G:
			_graph_overlay.draw_graph = not _graph_overlay.draw_graph
			_graph_overlay.refresh_graph()
		KEY_F:
			_locomotion_overlay.draw_crawl_fan = not _locomotion_overlay.draw_crawl_fan
		KEY_TAB:
			_toggle_debug()
		KEY_R:
			_reset()


# ----- the motor, which is step 9 of the tick contract -----


## Consumes `navigation.command` for real, which is what makes avoidance visible at all.
##
## `NavAvoidance` is static, reads no rays of its own, and is used INSIDE
## SurfaceCrawlController and TunnelSwimController -- so it runs automatically, and only while
## the locomotion layer is actually driving the body. A motor that walks route anchors instead
## never reaches it. Four responsibilities, and the stand-in motor in `behavior_sandbox.gd`
## skipped all four:
##
##   1. SEED THE INPUT HALF. `NavBodyState.forward` starts on Vector3.FORWARD and the crawl
##      controller slews FROM it, so a body state that is never seeded recomputes one tick of
##      turn from the same stale heading for ever. Done once in `_build_navigation`.
##
##   2. REPORT THE APPLIED BASIS BACK, never `preferred_forward`. Every `NavMotionCommand.make`
##      path -- including hold-still -- leaves that field on the class default, which is a
##      real-looking heading pointing at -Z. Feeding it back closes the loop on a lie.
##
##   3. CLAMP THE TURN HERE. Only the surface crawler slews; wiggle, leap and tunnel assign
##      their heading raw. The motor has to bound it itself or the body snaps, and the body IS
##      the eye transform -- a creature that pivots instantly sees round a corner a frame
##      before it could have looked round it.
##
##   4. ACT ON `command.abort`, WHICH MEANS STOP PUSHING. A stall carries a reason precisely so
##      the layer above can do something about it, and ignoring it is what wedged the alien in
##      a doorway for the rest of the session with a COMPLETE route in hand. What acting on it
##      does NOT mean is nudging the body loose -- see the note in `_drive`.
##
## THIS MOTOR HAS NO COLLISION OF ITS OWN, and does not need any: the creature here is a
## Node3D, and `desired_direction` is a step the crawl controller already swept against the
## probe. Travelling along it is what keeps the body inside the cave. Travelling along
## anything else does not -- see the note in the body of `_drive`.
##
## ONE CHARACTERISTIC WORTH RECOGNISING RATHER THAN CHASING. Waiting out the slot, the alien
## creeps to within about a metre of the wall and then reports BLOCKED for a second or two at
## a time: closer to the rock than to the floor, the wall becomes the crawler's
## `dominant_normal`, the tangent plane rotates onto it and nothing in the fan validates.
## Navigation's own stuck watchdog trips, replans, and it moves again. It is the same
## dominant-normal behaviour `test_local_avoidance.gd` documents, it belongs to Movement, and
## it costs the scenario nothing -- the lurk is a timer, not a position, and the retreat that
## follows it gets out on the first replan.
func _drive(delta: float) -> void:
	if _navigation == null or _creature == null or _command == null:
		return
	# NO ROUTE, NO PLAN TO EXECUTE. Step 9 carries out a plan; it does not invent one. The
	# behaviour tree legitimately spends whole stretches commanding nothing -- `search_area`
	# asks Perception to sweep and holds no goal at all -- and a motor that kept consuming the
	# last command through those stretches drives the body in a straight line for as long as
	# they last. Observed: the alien slid out of the cave entirely and kept going, with
	# `abort` reading `none` and a perfectly calm log the whole way.
	if not _navigation.follower.has_route():
		_step(Vector3.ZERO, delta)
		return
	_note_abort(_command.abort)

	if _command.is_stalled() or _command.desired_speed <= 0.0:
		# STOP PUSHING. That is what acting on an abort means here, and the obvious
		# alternative -- reversing a little to shake the body loose -- was tried and is worse
		# twice over. It is unvalidated motion, so it walks the body INTO the rock it is
		# already against; and it looks like progress to `NavProgressMonitor`, which is the
		# one thing in the project that can actually recover this. Held still, the monitor
		# trips after `progress_window`, resets the local mode and asks for a FAILED_TRAVERSAL
		# inspection, and the creature replans out of the pose. Still report the pose, so the
		# loop keeps being fed a true heading while nothing moves.
		_step(Vector3.ZERO, delta)
		return

	var wanted: Vector3 = _command.desired_direction.normalized()
	var profile: LocomotionProfile = _navigation.config.locomotion_profile
	# The FACING is what gets clamped, and only the facing. `desired_direction` is a step the
	# crawler already validated against the probe, so travelling along anything else -- a
	# slewed heading, for instance -- walks the body into rock the layer below had already
	# refused. That is not a subtle failure: the creature climbs the inside of a wall, crosses
	# the shell and ends up hundreds of metres outside the cave with a perfectly calm log.
	# Facing and travel are allowed to disagree during a turn. Animals do that.
	_forward = _turn_toward(_forward, wanted, profile.orientation_slew_rate * delta)
	# `desired_speed` already carries `cornering_speed`, so the cornering floor is not applied
	# a second time here.
	_step(wanted * _command.desired_speed * delta, delta)


## Moves the body and hands the APPLIED pose back to navigation.
func _step(travel: Vector3, delta: float) -> void:
	_creature.global_position += travel
	_watch_for_an_escape()
	# Yaw only. This motor keeps the creature upright, so the applied up IS up -- a real
	# Movement layer would align it to the surface and report that instead.
	var flat := Vector3(_forward.x, 0.0, _forward.z)
	if not flat.is_zero_approx():
		_creature.global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	var velocity: Vector3 = travel / maxf(delta, 0.0001)
	_navigation.set_body_state(_creature.global_position, velocity, _forward, Vector3.UP)


## Says so, once, if the motor has put the creature somewhere the cave is not.
##
## THIS IS THE MOTOR'S OWN FAILURE MODE AND IT IS SILENT WITHOUT THIS. The body has no collider
## -- staying inside is entirely a consequence of travelling along steps the crawl controller
## swept against the probe -- so any motor bug that stops honouring those steps ends with an
## alien in the void, still reporting a mode, a speed and no abort at all. On screen it just
## looks like the creature wandered off.
func _watch_for_an_escape() -> void:
	if _escaped or EncounterSandboxGeometry.INTERIOR.grow(1.0).has_point(_creature.global_position):
		return
	_escaped = true
	push_error(
		(
			(
				"EncounterSandbox: the motor put the creature at %v, outside the cave. It has no "
				+ "collider; only the validated step keeps it in."
			)
			% _creature.global_position
		)
	)


## `from` turned toward `to` by at most `max_radians`, in three dimensions because the crawler
## works in the tangent plane rather than in yaw.
static func _turn_toward(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_radians or angle < 0.0001:
		return to
	# slerp has no defined arc between opposed vectors, so a body asked to turn exactly around
	# is nudged off the antipode first and finishes the turn on the following frames.
	if angle > PI - 0.001:
		return from.rotated(Vector3.UP, max_radians)
	return from.slerp(to, max_radians / angle).normalized()


## Prints an abort the first time it appears, and again when it clears. A stall carries a
## reason precisely so the layer above can say what it was; silently absorbing them is how a
## wedged creature looks like a pathfinding mystery.
func _note_abort(abort: NavMotionCommand.Abort) -> void:
	if abort == _last_abort:
		return
	_last_abort = abort
	if abort == NavMotionCommand.Abort.NONE:
		print("[encounter] moving again")
	else:
		print("[encounter] stalled: %s" % NavMotionCommand.abort_name(abort))


func _on_motion_planned(command: NavMotionCommand) -> void:
	_command = command


# ----- the claim the scenario rests on -----


## The three-part proof from `verify_navigation_runtime.gd`, run every time the scene opens.
##
## THE MIDDLE PART IS THE ONE PEOPLE SKIP, and it is why this is three checks rather than one.
## A cave whose refuge simply had no nodes in it would pass "nothing crosses the slot" for
## entirely the wrong reason, and would go on passing it if candidate rejection broke outright.
func _prove_the_refuge_is_out_of_reach() -> void:
	var graph: NavGraph = _navigation.graph
	if graph == null:
		push_error("EncounterSandbox baked no graph; the cave proves nothing")
		return

	var crossing: int = 0
	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for sample: int in 33:
			if EncounterSandboxGeometry.SLOT.has_point(from.lerp(to, float(sample) / 32.0)):
				crossing += 1
				break

	var inside: Array = []
	var outside: int = -1
	for id: Variant in graph.node_ids():
		var at: Vector3 = graph.node_at(id).position
		if EncounterSandboxGeometry.REFUGE.has_point(at):
			inside.append(id)
		elif outside < 0 and EncounterSandboxGeometry.CHAMBER_A.has_point(at):
			outside = id

	var leaked: int = 0
	if outside >= 0:
		var reachable: Dictionary = graph.reachable_from(outside)
		for id: Variant in inside:
			if reachable.has(id):
				leaked += 1

	var route: NavRoute = _navigation.plan_route(
		EncounterSandboxGeometry.CREATURE_START, EncounterSandboxGeometry.REFUGE.get_center()
	)
	var stops_short: bool = (
		route.status == NavRoute.Status.PARTIAL
		and route.anchors.size() > 0
		and not EncounterSandboxGeometry.REFUGE.has_point(route.anchors[-1])
	)

	print(
		(
			"[encounter] %d nodes, %d edges | slot crossed by %d | refuge has %d nodes, %d reachable | route to it: %s%s"
			% [
				graph.node_count(),
				graph.edge_count(),
				crossing,
				inside.size(),
				leaked,
				route.status_name(),
				"" if stops_short else "  <-- DOES NOT STOP SHORT"
			]
		)
	)
	if crossing > 0 or inside.is_empty() or leaked > 0 or not stops_short:
		push_error("EncounterSandbox: the refuge is not out of reach; see the line above")


# ----- interaction -----


func _drive_player(delta: float) -> void:
	if _player == null:
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += Vector3.FORWARD
	if Input.is_physical_key_pressed(KEY_S):
		move += Vector3.BACK
	if Input.is_physical_key_pressed(KEY_A):
		move += Vector3.LEFT
	if Input.is_physical_key_pressed(KEY_D):
		move += Vector3.RIGHT
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move += Vector3.DOWN
	if move != Vector3.ZERO:
		_player.global_position += move.normalized() * PLAYER_SPEED * delta


## Straight into the creature, because nothing in this project emits NoiseEvents yet.
func _emit_noise(loudness: float, category: StringName) -> void:
	_creature.receive_noise(
		NoiseEvent.make(_player.global_position, loudness, category, _player, _player)
	)
	print("[encounter] %s at %v" % [category, _player.global_position])


func _reset() -> void:
	_creature.global_position = EncounterSandboxGeometry.CREATURE_START
	_player.global_position = EncounterSandboxGeometry.PLAYER_START
	_forward = Vector3.RIGHT
	_command = null
	_navigation.clear_goal()
	_navigation.set_body_state(_creature.global_position, Vector3.ZERO, _forward, Vector3.UP)
	_suspicion.reset()
	# Session history too, so the first encounter after a reset teaches rather than kills.
	director.reset()
	behavior.hfsm.reset_to(CreatureState.State.UNALERTED, behavior.context)
	print("[encounter] reset")


func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	for node: CanvasItem in [
		_perception_panel, _suspicion_panel, _behavior_panel, _navigation_panel, _director_panel
	]:
		node.visible = _debug_visible
	for node: Node3D in [
		_graph_overlay, _locomotion_overlay, _perception_overlay, _suspicion_overlay
	]:
		node.visible = _debug_visible
	for nest: CreatureNest in _nests:
		nest.visible = _debug_visible


# ----- construction -----


func _build_creature() -> void:
	_creature = CreaturePerception.new()
	_creature.name = "CreaturePerception"
	_creature.position = EncounterSandboxGeometry.CREATURE_START
	# Looking along +X, down the length of the cave.
	_creature.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	# Shipped defaults, for the reason navigation's own sandbox gives: a sandbox with a tuned
	# config proves only that SOME config works.
	_creature.config = PerceptionConfig.new()
	add_child(_creature)
	_creature.add_child(_blob(SphereMesh.new(), COLOR_CREATURE))


func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "StandIn"
	_player.position = EncounterSandboxGeometry.PLAYER_START
	# The group CreaturePerception falls back to when `targets` is not wired, so this scene
	# exercises the fallback rather than only the explicit path.
	_player.add_to_group(&"perceivable")
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	add_child(_player)
	_player.add_child(_blob(capsule, COLOR_PLAYER))


func _build_belief() -> void:
	_suspicion = CreatureSuspicion.new()
	_suspicion.name = "CreatureSuspicion"
	_suspicion.config = SuspicionConfig.new()
	add_child(_suspicion)
	# The two-line coupling perception/README.md documents, and the only wiring between those
	# modules.
	_creature.evidence_observed.connect(_suspicion.submit_evidence)
	_creature.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	_navigation.config = NavigationConfig.new()
	# add_child FIRST: the probe binds the world in `_ready()`, and a bake before that samples
	# a space with nothing in it.
	add_child(_navigation)
	var graph: NavGraph = _navigation.bake_now(EncounterSandboxGeometry.bake_region())
	if graph == null:
		push_error("EncounterSandbox could not bake a navigation graph over the cave")
		return
	# Responsibility 1: seed the input half of the locomotion loop from the real body, before
	# anything asks the crawler to slew away from it.
	_forward = -_creature.global_transform.basis.z
	_navigation.set_body_state(_creature.global_position, Vector3.ZERO, _forward, Vector3.UP)
	_navigation.motion_planned.connect(_on_motion_planned)


## Level-scoped, so it is a sibling of the creature rather than a child of it, and it is added
## BEFORE the behavior on purpose: Godot ticks in tree order, so the directive a creature reads
## was integrated this frame rather than last. A freshness preference, never a correctness
## requirement -- see EncounterDirector's class docstring.
##
## Shipped defaults, and there is deliberately no way to hurry them from this scene. A sandbox
## with a tuned config proves only that SOME config works, which is the trap
## `navigation_sandbox.gd` names; `director_sandbox.tscn` scales the CLOCK instead and leaves
## the numbers alone.
func _build_director() -> void:
	director = EncounterDirector.new()
	director.name = "EncounterDirector"
	director.config = DirectorConfig.new()
	director.players = [_player]
	add_child(director)


func _build_behavior() -> void:
	behavior = CreatureBehavior.new()
	behavior.name = "CreatureBehavior"
	behavior.config = BehaviorConfig.new()
	# Two creatures with the same seed wait out the slot identically. Anything non-zero will
	# do; what matters is that it is not shared with another creature in the same level.
	behavior.behavior_seed = 20250816
	behavior.suspicion = _suspicion
	behavior.perception = _creature
	behavior.navigation = _navigation
	behavior.director = director
	# THE PERCEPTION NODE IS THE BODY. It is a Node3D and measures hearing and touch from its
	# own position, so moving it moves the creature and there is no second transform to keep in
	# step. Added last: on its first tick it mutes the other three facades' own
	# `_physics_process` and drives steps 1-8 itself. NOT the Director's, which runs its own --
	# `_mute_subsystems` names three nodes and this is not one of them.
	behavior.body = _creature
	add_child(behavior)
	behavior.state_changed.connect(_on_state_changed)
	behavior.attack_landed.connect(_on_attack)
	director.register(behavior, _suspicion)
	# Publish the resting alertness NOW rather than at the first tick: perception runs its own
	# _physics_process until Behavior mutes it, and one frame at full sharpness with the player
	# standing in the sightline opens the scene already hunting.
	_creature.set_alertness_context(behavior.config.alertness_for(behavior.state()))


func _plant_nests() -> void:
	for at: Vector3 in EncounterSandboxGeometry.NEST_POSITIONS:
		var nest := CreatureNest.new()
		nest.name = "Nest%d" % _nests.size()
		nest.position = at
		var pad := BoxMesh.new()
		pad.size = Vector3(2.0, 0.15, 2.0)
		add_child(nest)
		nest.add_child(_blob(pad, COLOR_NEST))
		_nests.append(nest)


func _build_debug() -> void:
	_graph_overlay = NavigationDebugDraw.new()
	_graph_overlay.name = "NavigationDebugDraw"
	_graph_overlay.navigation = _navigation
	add_child(_graph_overlay)

	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.name = "NavigationLocomotionDraw"
	_locomotion_overlay.navigation = _navigation
	add_child(_locomotion_overlay)

	_perception_overlay = PerceptionDebugDraw.new()
	_perception_overlay.name = "PerceptionDebugDraw"
	_perception_overlay.perception = _creature
	add_child(_perception_overlay)

	_suspicion_overlay = SuspicionDebugDraw.new()
	_suspicion_overlay.name = "SuspicionDebugDraw"
	_suspicion_overlay.suspicion = _suspicion
	add_child(_suspicion_overlay)

	_goal_marker = _blob(_goal_bar(), COLOR_GOAL)
	_goal_marker.name = "GoalMarker"
	add_child(_goal_marker)

	var layer := CanvasLayer.new()
	add_child(layer)

	# One panel per corner. Four readouts stacked on each other are worse than any one of them
	# alone, and NavigationDebugPanel is the odd one out -- it extends Label, where the other
	# three are PanelContainers.
	_perception_panel = PerceptionDebugPanel.new()
	_perception_panel.perception = _creature
	_perception_panel.debug_draw = _perception_overlay
	_perception_panel.position = Vector2(12, 12)
	layer.add_child(_perception_panel)

	_suspicion_panel = SuspicionDebugPanel.new()
	_suspicion_panel.suspicion = _suspicion
	_suspicion_panel.debug_draw = _suspicion_overlay
	_suspicion_panel.anchor_left = 1.0
	_suspicion_panel.anchor_right = 1.0
	_suspicion_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_suspicion_panel.position = Vector2(-12, 12)
	layer.add_child(_suspicion_panel)

	_behavior_panel = BehaviorDebugPanel.new()
	# Assigned BEFORE add_child: the panel connects `state_changed` in its own `_ready()`, and
	# one wired up afterwards renders every line except the transition log.
	_behavior_panel.behavior = behavior
	_behavior_panel.anchor_top = 1.0
	_behavior_panel.anchor_bottom = 1.0
	_behavior_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_behavior_panel.position = Vector2(12, -12)
	layer.add_child(_behavior_panel)

	_navigation_panel = NavigationDebugPanel.new()
	_navigation_panel.navigation = _navigation
	_navigation_panel.anchor_left = 1.0
	_navigation_panel.anchor_right = 1.0
	_navigation_panel.anchor_top = 1.0
	_navigation_panel.anchor_bottom = 1.0
	_navigation_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_navigation_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_navigation_panel.position = Vector2(-12, -12)
	layer.add_child(_navigation_panel)

	# The fifth panel, at the top, because the four corners were already spoken for and the
	# question this scene now raises -- "why did it leave?" -- is answered here rather than in
	# any of them.
	_director_panel = DirectorDebugPanel.new()
	_director_panel.director = director
	_director_panel.creature = behavior
	_director_panel.behavior = behavior
	_director_panel.anchor_left = 0.5
	_director_panel.anchor_right = 0.5
	_director_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_director_panel.position = Vector2(0.0, 12.0)
	layer.add_child(_director_panel)


## Above the cave and off to one side, aimed with look_at rather than left on its default
## rotation -- a Camera3D faces its own -Z, so one dropped here unrotated stares at the sky and
## the whole scene reads as an overlay that failed to draw.
func _build_camera() -> void:
	var interior: AABB = EncounterSandboxGeometry.INTERIOR
	var camera := Camera3D.new()
	camera.name = "SandboxCamera"
	camera.position = Vector3(interior.size.x * 0.5, CAMERA_HEIGHT, interior.size.z + 26.0)
	camera.far = 400.0
	camera.current = true
	add_child(camera)
	camera.look_at(interior.get_center(), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(light)


## The cave as wireframe, not as solid meshes. Solid boxes hide the interior, and translucent
## ones sort PER OBJECT on the GL Compatibility renderer this project targets -- overlapping
## transparent slabs pop and reorder as the camera moves, which reads as a bug in the graph.
func _draw_cave() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for box: AABB in EncounterSandboxGeometry.solids():
		_wire_box(mesh, box)
	mesh.surface_end()

	var view := MeshInstance3D.new()
	view.name = "CaveWireframe"
	view.mesh = mesh
	view.material_override = material
	view.extra_cull_margin = 4096.0
	add_child(view)


func _wire_box(mesh: ImmediateMesh, box: AABB) -> void:
	# Godot's AABB endpoint order: bit 0 is +x, bit 1 is +y, bit 2 is +z. Two corners are
	# joined by an edge exactly when their indices differ in one bit.
	for corner: int in 8:
		for axis: int in 3:
			var neighbor: int = corner | (1 << axis)
			if neighbor == corner:
				continue
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(corner))
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(neighbor))


static func _goal_bar() -> BoxMesh:
	var bar := BoxMesh.new()
	bar.size = Vector3(0.3, 3.0, 0.3)
	return bar


static func _blob(mesh: Mesh, color: Color) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	return view


func _on_state_changed(
	from: CreatureState.State, to: CreatureState.State, reason: StringName
) -> void:
	print(
		(
			"[encounter] %s -> %s (%s)"
			% [CreatureState.state_name(from), CreatureState.state_name(to), reason]
		)
	)


func _on_attack(_target: Node, lethality: EncounterDirective.Lethality) -> void:
	print(
		(
			"[encounter] attack (%s)"
			% ("grace" if lethality == EncounterDirective.Lethality.GRACE else "lethal")
		)
	)
