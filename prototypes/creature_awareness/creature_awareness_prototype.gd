class_name CreatureAwarenessPrototype
extends Node3D

## Navigation, perception and suspicion in one scene, driving one alien.
##
##     LMB (hold)  perform the selected activity wherever you point; drag to move it
##     Tab / 1 2 3 camera: free fly, ant farm, follow
##     Q / E       select EVA thrust / mining
##     WASD, Space/Ctrl, Shift, Esc   fly (the zero-g player)
##     R           rebake     F1 world graph   F2 locomotion   F3 belief
##
## WHAT TO WATCH, IN ORDER:
##
##   1  Ant farm camera. The near rock is culled away, so all three caverns, both tunnels
##      and the player shaft are visible at once. This is the only view that shows the
##      stimulus and the alien at the same time.
##   2  Pick mining, hold in a cavern the alien is not in. The readout walks down the chain:
##      heard -> evidence -> hotspot -> above threshold. The alien leaves its nest.
##   3  WHERE IT GOES IS NOT WHERE YOU CLICKED. Hearing displaces what it reports by up to
##      the uncertainty radius, so the orange stimulus marker and the hotspot the alien
##      commits to are two different places. That gap is the design working -- drag
##      `hearing_jitter` to 0 in the panel if you want them to coincide while debugging.
##   4  It arrives, searches, finds nothing, and the belief resolves. Back to wandering.
##   5  Tap thrust once from 30 m: heard, but no hotspot. HOLD it: a hotspot forms. That is
##      "one is ignored, five in a row become a lead", visible.
##   6  Ping in the loft, above the Dock. The route comes back PARTIAL, the alien stops at
##      the mouth of the 1 m shaft, and it searches from there without ever resolving it.
##      Fly up the shaft yourself to prove the opening is real.
##
## NOTHING UNDER gameplay/creature/ IS TOUCHED BY ANY OF THIS. Every link is a public call
## or a signal the three modules already expose; the only thing this prototype adds is the
## behaviour layer, which is the one piece none of them ships. See
## `creature_awareness_behaviour.gd`.
##
## THE TICK ORDER IS EXPLICIT AND MATTERS. Perception first, so a noise received this frame
## is evidence before suspicion looks; suspicion next, so hotspots exist before behaviour
## reads them; behaviour next, so a goal is set before navigation plans; navigation last.
## Left to `_physics_process` on each node it would be scene-tree order, which is invisible
## and one drag-and-drop away from changing.

const PLAYER_SCENE := "res://prototypes/navigation/zero_g_player.tscn"
## RMB and T are taken by the neighbouring prototypes. Registered at runtime rather than
## added to project.godot so this scene stays self-contained in a fresh clone.
const ACTION_PERFORM := "creature_awareness_perform"
## How long to wait for CSG to hand its rebuilt trimesh to the physics server.
const COLLIDER_WAIT_FRAMES: int = 40

@export var settings: CreatureAwarenessSettings = null

var _map: CreatureAwarenessMap = null
var _source: NavigationSource = null
var _navigation: CreatureNavigation = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _behaviour: CreatureAwarenessBehaviour = null
var _creature: CreatureAwarenessCreature = null
var _stimulus: CreatureAwarenessStimulus = null
var _cameras: CreatureAwarenessCameras = null
var _hud: CreatureAwarenessHud = null
var _player: Node3D = null
var _config: NavigationConfig = null
var _perception_config: PerceptionConfig = null
var _suspicion_config: SuspicionConfig = null
var _graph_overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _belief_overlay: SuspicionDebugDraw = null


func _enter_tree() -> void:
	if InputMap.has_action(ACTION_PERFORM):
		return
	InputMap.add_action(ACTION_PERFORM)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(ACTION_PERFORM, click)


func _ready() -> void:
	if settings == null:
		# Fresh clone, or someone deleted it. A bare instance IS the knobs consts.
		settings = CreatureAwarenessSettings.new()
		push_warning(
			(
				"No creature_awareness_settings.tres wired; "
				+ "running on creature_awareness_knobs.gd defaults."
			)
		)
	_build_configs()
	_build_map()
	_build_source()
	_build_navigation()
	_build_creature()
	_build_senses()
	_build_behaviour()
	_build_player()
	_build_stimulus()
	_build_cameras()
	_build_overlays()

	settings.changed.connect(_apply_settings)
	_apply_settings()
	await _bake()


func _physics_process(delta: float) -> void:
	if _perception == null:
		return
	# See the class docstring: this order is the contract, not the scene tree's.
	_perception.advance(delta)
	_suspicion.advance(delta)
	if settings.alertness_feedback:
		# Section 14. Read-only context: it changes how hard the creature looks, never what
		# it finds. It also doubles the credit an arrival scan earns, because a scan that
		# checked two senses clears more than one that checked one.
		_perception.set_alertness_context(_suspicion.get_overall_suspicion())
	_behaviour.advance(delta)
	_navigation.advance(delta, _creature.global_position)


func _process(_delta: float) -> void:
	# Rebound every frame rather than on a signal, because the pick's meaning depends on
	# which camera it is cast from and a stale binding places stimuli from the wrong one.
	if _stimulus != null and _cameras != null:
		_stimulus.bind_camera(_cameras.active())
	if _hud != null:
		_hud.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_PERFORM):
		_stimulus.begin()
		return
	if event.is_action_released(ACTION_PERFORM):
		_stimulus.end()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			_cameras.cycle()
		KEY_1:
			_cameras.select(CreatureAwarenessCameras.View.FREE_FLY)
		KEY_2:
			_cameras.select(CreatureAwarenessCameras.View.ANT_FARM)
		KEY_3:
			_cameras.select(CreatureAwarenessCameras.View.FOLLOW)
		KEY_Q:
			_stimulus.set_kind(CreatureAwarenessStimulus.Kind.THRUST)
		KEY_E:
			_stimulus.set_kind(CreatureAwarenessStimulus.Kind.MINING)
		KEY_F1:
			_graph_overlay.visible = not _graph_overlay.visible
		KEY_F2:
			_locomotion_overlay.visible = not _locomotion_overlay.visible
		KEY_F3:
			_belief_overlay.visible = not _belief_overlay.visible
		KEY_R:
			_rebake()


func _build_configs() -> void:
	_config = NavigationConfig.new()
	_perception_config = PerceptionConfig.new()
	_suspicion_config = SuspicionConfig.new()


func _build_map() -> void:
	_map = CreatureAwarenessMap.new()
	_map.name = "Cave"
	add_child(_map)


## Bounds and seeds, wired the way a real level would wire them. No `bake_bounds` on the
## node itself, because the collider does not exist yet -- see `_bake`.
func _build_source() -> void:
	_source = NavigationSource.new()
	_source.name = "NavigationSource"
	_source.config = _config
	# Flooding from known-open points rather than sweeping the lattice. Mandatory here: the
	# collider is a concave CSG trimesh, and an overlap test deep inside one reports the
	# clearance ceiling, so a sweep would decimate rock FIRST and fill the stone with nodes.
	_source.use_flood = true
	_source.air_seeds = CreatureAwarenessMap.air_seeds()
	add_child(_source)


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	_navigation.config = _config
	# The per-level / per-creature split. This navigator owns a route and a belief and no
	# graph; a second creature would share the bake rather than repeat it.
	_navigation.source = _source
	add_child(_navigation)


func _build_creature() -> void:
	_creature = CreatureAwarenessCreature.new()
	_creature.name = "Creature"
	_creature.navigation = _navigation
	_creature.position = CreatureAwarenessMap.DOCK
	add_child(_creature)


## Perception is parented to the CREATURE, not to this node.
##
## `CreaturePerception._own_position` returns its own `global_position`, so anywhere else
## and every noise is measured from the wrong listener -- which at this node would be the
## world origin, i.e. the middle of the Dock, and the alien would hear as though it never
## left home.
func _build_senses() -> void:
	_perception = CreaturePerception.new()
	_perception.name = "CreaturePerception"
	_perception.config = _perception_config
	_creature.add_child(_perception)

	_suspicion = CreatureSuspicion.new()
	_suspicion.name = "CreatureSuspicion"
	_suspicion.config = _suspicion_config
	# Which chamber a point is in, so a trail of stimuli down a tunnel cannot chain two
	# caverns into one hotspot centred in the rock between them. Suspicion never touches
	# geometry itself -- this Callable is the whole of its access to the world.
	_suspicion.region_resolver = CreatureAwarenessMap.region_id_at
	add_child(_suspicion)

	# The entire coupling between the two modules, in the two lines their READMEs promise.
	_perception.evidence_observed.connect(_suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)


func _build_behaviour() -> void:
	_behaviour = CreatureAwarenessBehaviour.new()
	_behaviour.name = "Behaviour"
	_behaviour.navigation = _navigation
	_behaviour.perception = _perception
	_behaviour.suspicion = _suspicion
	_behaviour.creature = _creature
	_behaviour.settings = settings
	add_child(_behaviour)


func _build_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	_player = packed.instantiate()
	_player.position = CreatureAwarenessMap.DOCK + Vector3(6.0, 2.0, 6.0)
	add_child(_player)


func _build_stimulus() -> void:
	_stimulus = CreatureAwarenessStimulus.new()
	_stimulus.name = "Stimulus"
	_stimulus.perception = _perception
	_stimulus.settings = settings
	add_child(_stimulus)


func _build_cameras() -> void:
	_cameras = CreatureAwarenessCameras.new()
	_cameras.name = "Cameras"
	_cameras.settings = settings
	add_child(_cameras)
	var head: Camera3D = _player.get_node("HeadCamera")
	head.far = CreatureAwarenessKnobs.CAMERA_FAR
	_cameras.setup(_map, head, _creature)
	# The pick depends on where the camera stands, so it has to follow the selection.
	_stimulus.bind_camera(_cameras.active())


func _build_overlays() -> void:
	_graph_overlay = NavigationDebugDraw.new()
	_graph_overlay.navigation = _navigation
	add_child(_graph_overlay)

	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.navigation = _navigation
	add_child(_locomotion_overlay)

	_belief_overlay = SuspicionDebugDraw.new()
	_belief_overlay.suspicion = _suspicion
	add_child(_belief_overlay)

	_hud = get_node_or_null("HUD") as CreatureAwarenessHud
	if _hud != null:
		_hud.bind(_behaviour, _navigation, _perception, _suspicion, _stimulus, _cameras)


## Pushes every tunable onto the scene. MUST NOT write back into `settings`, or it re-enters
## `changed`.
func _apply_settings() -> void:
	settings.apply_to_navigation(_config)
	settings.apply_to_perception(_perception_config)
	settings.apply_to_suspicion(_suspicion_config)
	if _cameras != null:
		_cameras.apply_settings()
	if _graph_overlay != null:
		_graph_overlay.visible = settings.show_world_graph
	if _locomotion_overlay != null:
		_locomotion_overlay.visible = settings.show_locomotion
	if _belief_overlay != null:
		_belief_overlay.visible = settings.show_belief


func _bake() -> void:
	await _await_collider(CreatureAwarenessMap.DOCK, CreatureAwarenessMap.CAVERN_RADIUS)
	_source.bake(CreatureAwarenessMap.bounds())
	# The creature is held still until there is a graph. A frame-budgeted bake over three
	# 40 m caverns takes a moment, and an alien spending it planning against null looks
	# stuck rather than busy.
	var graph: NavGraph = await _source.graph_baked
	# Printed rather than only shown on the HUD, because a bake that finds NOTHING is the one
	# failure here that looks like an empty cave rather than an error.
	print(
		(
			"[creature_awareness] baked %d nodes, %d edges from %d seeds"
			% [graph.node_count(), graph.edge_count(), _source.seeds().size()]
		)
	)
	_check_passages(graph)
	_creature.enabled = true


## Invariant 5, checked on every bake, because these are the failures that look like
## success.
##
## An extra edge does not error, does not stall the alien and does not look wrong from
## outside -- the creature simply gains a route it should not have, and starts working
## better. Nothing in the scene would tell you. So:
##
##   swim tunnel     MUST carry normal-volume edges, or the alien cannot leave the Dock
##   squeeze tunnel  must carry NO normal-volume edge; wiggle edges are the point of it
##   player shaft    must carry NO edge of either kind
##   the loft        must still be FULL of nodes -- the flood crosses a 1 m bore happily,
##                   and a loft with none would pass the check above for the wrong reason
func _check_passages(graph: NavGraph) -> void:
	var swim: int = 0
	var squeeze_normal: int = 0
	var squeeze_wiggle: int = 0
	var shaft: int = 0
	var swim_bore: AABB = _bore(CreatureAwarenessMap.DOCK, CreatureAwarenessMap.GALLERY, 3.0)
	var squeeze_bore: AABB = _bore(CreatureAwarenessMap.DOCK, CreatureAwarenessMap.WARREN, 2.0)
	var shaft_bore: AABB = _bore(CreatureAwarenessMap.DOCK, CreatureAwarenessMap.LOFT, 1.5)

	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for step: int in 33:
			var point: Vector3 = from.lerp(to, float(step) / 32.0)
			if swim_bore.has_point(point) and edge.type == NavEdge.Type.NORMAL_VOLUME:
				swim += 1
				break
			if squeeze_bore.has_point(point):
				if edge.type == NavEdge.Type.NORMAL_VOLUME:
					squeeze_normal += 1
				else:
					squeeze_wiggle += 1
				break
			if shaft_bore.has_point(point):
				shaft += 1
				break

	var in_loft: int = 0
	for id: int in graph.node_ids():
		if graph.node_at(id).position.distance_to(CreatureAwarenessMap.LOFT) <= 6.0:
			in_loft += 1
	print(
		(
			(
				"[creature_awareness] swim %d normal   squeeze %d wiggle / %d normal   "
				+ "shaft %d   loft %d nodes"
			)
			% [swim, squeeze_wiggle, squeeze_normal, shaft, in_loft]
		)
	)

	if swim == 0:
		push_warning("The 4 m swim tunnel carries no normal-volume edge; the Gallery is cut off.")
	if squeeze_normal > 0:
		push_warning(
			(
				"Invariant 5 broken: the normal body is being routed through the 2 m squeeze. "
				+ "It is no longer a squeeze."
			)
		)
	if squeeze_wiggle == 0:
		push_warning("The 2 m squeeze carries no wiggle edge; the Warren is unreachable.")
	if shaft > 0:
		push_warning(
			(
				"Invariant 5 broken: an edge crosses the 1 m player shaft. "
				+ "The loft is no longer player-only."
			)
		)
	if in_loft == 0:
		push_warning(
			(
				"The loft has no nodes, so the shaft check above passed for the wrong reason: "
				+ "the flood never got up there at all."
			)
		)


## The span of a bore between two chambers, pulled in at each end so the box measures the
## PASSAGE and not the open space either side of it.
func _bore(from: Vector3, to: Vector3, girth: float) -> AABB:
	var along: Vector3 = (to - from).normalized()
	var near_radius: float = CreatureAwarenessMap.CAVERN_RADIUS
	var far_radius: float = (
		CreatureAwarenessMap.LOFT_RADIUS
		if to == CreatureAwarenessMap.LOFT
		else CreatureAwarenessMap.CAVERN_RADIUS
	)
	var start: Vector3 = from + along * (near_radius + 1.0)
	var end: Vector3 = to - along * (far_radius + 1.0)
	return AABB(start, Vector3.ZERO).expand(end).grow(girth)


func _rebake() -> void:
	_creature.enabled = false
	_source.bake(CreatureAwarenessMap.bounds())
	await _source.graph_baked
	_creature.enabled = true


## Waits for the CSG trimesh to reach the physics server, by asking whether it has.
##
## DO NOT COUNT FRAMES HERE. CSG remeshes on the main thread during `_process` and the new
## collider reaches Jolt on the step after, so "two physics frames" is a MEASUREMENT rather
## than a contract -- and the failure when it is wrong is silent. A bake against a collider
## that is not there yet does not error: every cast reports clear, every candidate reports
## the clearance ceiling, and the graph comes back full of nodes inside solid rock.
func _await_collider(witness: Vector3, radius: float) -> void:
	for _attempt: int in COLLIDER_WAIT_FRAMES:
		await get_tree().physics_frame
		if _is_carved(witness, radius):
			return
	push_warning("creature_awareness: the CSG collider never appeared; baking anyway.")


## Whether a pocket of roughly `radius` exists at `witness`, asked with RAYS rather than an
## overlap test.
##
## THE OBVIOUS TEST CANNOT WORK HERE. `shape_fits` at the witness is an overlap test, and a
## concave trimesh has no interior -- a point buried in stone touches no triangle and reports
## "it fits" exactly as loudly as a point in mid-air. It answers "has this been carved?" with
## yes before the carve, after it, and in an empty world.
##
## A ray does work. From inside a fresh cavity it strikes that cavity's wall; from inside
## undisturbed rock it crosses only back faces, which Godot's trimesh collision does not
## report; in an empty world it hits nothing. Six of them, because one axis can look straight
## down a bore and miss.
func _is_carved(witness: Vector3, radius: float) -> bool:
	var probe: NavigationProbe = _source.probe
	var reach: float = radius * 4.0
	for direction: Vector3 in [
		Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK
	]:
		var sample: NavSurfaceSample = probe.surface_along(
			witness, direction, reach, _config.world_mask
		)
		if sample.hit and sample.distance <= radius * 1.5:
			return true
	return false
