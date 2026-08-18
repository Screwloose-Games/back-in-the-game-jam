extends Node3D

## Drives the whole chain with no hands on it, and fails loudly if any link stops working.
##
## THE PROTOTYPE IS WATCHED, NOT ASSERTED, and that is the gap this closes. Every step from
## a noise to an alien arriving is visible on screen and none of it is checked by anything,
## so a regression in the middle of the chain shows up as "it did not come this time", which
## is also what a badly aimed click looks like. These are the same checks a person makes by
## eye, made by a machine that does not get bored.
##
## MUST BE RUN AS ITS .tscn. A node added during `SceneTree._initialize()` never receives
## `_ready()`, so `--script` on this file runs nothing, prints nothing and exits 0 -- which
## looks exactly like a pass.
##
##     godot --headless --path . res://prototypes/creature_awareness/tools/verify_creature_awareness_runtime.tscn
##
## It builds the world itself rather than instancing the prototype scene, because the
## prototype owns a player, three cameras and a HUD that a headless run has no use for and
## that would only add ways for this to fail for reasons unrelated to the chain.

const STIMULUS_INTERVAL: float = 0.3
const STIMULUS_LOUDNESS: float = 1.0
## Long enough for a held stimulus to accumulate at cavern range, short enough that a broken
## chain does not take a minute to say so.
const HOLD_SECONDS: float = 20.0
const SETTLE_FRAMES: int = 8

var _map: CreatureAwarenessMap = null
var _source: NavigationSource = null
var _navigation: CreatureNavigation = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _behaviour: CreatureAwarenessBehaviour = null
var _creature: CreatureAwarenessCreature = null
var _config: NavigationConfig = null
var _perception_config: PerceptionConfig = null
var _suspicion_config: SuspicionConfig = null
var _settings: CreatureAwarenessSettings = null
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_build()
	await _bake()
	_check_graph()
	await _check_chain()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _build() -> void:
	_settings = CreatureAwarenessSettings.new()
	_config = NavigationConfig.new()
	_perception_config = PerceptionConfig.new()
	_suspicion_config = SuspicionConfig.new()
	_settings.apply_to_navigation(_config)
	_settings.apply_to_perception(_perception_config)
	_settings.apply_to_suspicion(_suspicion_config)

	_map = CreatureAwarenessMap.new()
	add_child(_map)

	_source = NavigationSource.new()
	_source.config = _config
	_source.use_flood = true
	_source.air_seeds = CreatureAwarenessMap.air_seeds()
	add_child(_source)

	_navigation = CreatureNavigation.new()
	_navigation.config = _config
	_navigation.source = _source
	add_child(_navigation)

	_creature = CreatureAwarenessCreature.new()
	_creature.navigation = _navigation
	_creature.position = CreatureAwarenessMap.DOCK
	add_child(_creature)

	_perception = CreaturePerception.new()
	_perception.config = _perception_config
	_creature.add_child(_perception)

	_suspicion = CreatureSuspicion.new()
	_suspicion.config = _suspicion_config
	_suspicion.region_resolver = CreatureAwarenessMap.region_id_at
	add_child(_suspicion)

	_perception.evidence_observed.connect(_suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)

	_behaviour = CreatureAwarenessBehaviour.new()
	_behaviour.navigation = _navigation
	_behaviour.perception = _perception
	_behaviour.suspicion = _suspicion
	_behaviour.creature = _creature
	_behaviour.settings = _settings
	# Wandering would move the listener mid-measurement, and every distance below is quoted
	# from the Dock.
	_settings.wander_enabled = false
	add_child(_behaviour)


func _bake() -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	_source.bake(CreatureAwarenessMap.bounds())
	await _source.graph_baked


## The four passage classes. Same checks the prototype prints, asserted here.
func _check_graph() -> void:
	var graph: NavGraph = _source.world_graph
	_check("the bake produced a graph", graph != null and graph.node_count() > 0)
	if graph == null:
		return

	var swim: int = _edges_crossing(graph, _bore(CreatureAwarenessMap.GALLERY, 3.0), true)
	var squeeze_normal: int = _edges_crossing(graph, _bore(CreatureAwarenessMap.WARREN, 2.0), true)
	var squeeze_any: int = _edges_crossing(graph, _bore(CreatureAwarenessMap.WARREN, 2.0), false)
	var shaft: int = _edges_crossing(graph, _bore(CreatureAwarenessMap.LOFT, 1.5), false)

	_check("the 4 m swim tunnel carries normal-volume edges", swim > 0)
	_check("the 2 m squeeze carries NO normal-volume edge (Invariant 5)", squeeze_normal == 0)
	_check("the 2 m squeeze is passable when compressed", squeeze_any > 0)
	_check("the 1 m player shaft carries no edge at all (Scenario G)", shaft == 0)
	# Without this the shaft check above would pass just as happily on a bake that never
	# reached the loft, which is the wrong reason to be reassured.
	_check("the loft still has nodes, so the flood did reach it", _nodes_in_loft(graph) > 0)


## The chain itself: hold a stimulus, and watch belief and behaviour follow.
func _check_chain() -> void:
	# In the Gallery, 60 m from the listener. Chosen because a single pulse at that range
	# cannot form a hotspot and a held one can -- so this also proves the accumulation.
	var at: Vector3 = CreatureAwarenessMap.GALLERY

	_perception.receive_noise(NoiseEvent.make(at, STIMULUS_LOUDNESS, &"mining", null, null))
	await _tick(0.5)
	_check(
		"one pulse at 60 m does not reach the investigate threshold",
		_suspicion.get_hotspots_above(_settings.investigate_threshold).is_empty()
	)

	var elapsed: float = 0.0
	var since_pulse: float = 0.0
	var committed: bool = false
	var peak: float = 0.0
	var pulses: int = 0
	while elapsed < HOLD_SECONDS and not committed:
		var step: float = await _tick(STIMULUS_INTERVAL)
		elapsed += step
		since_pulse += step
		if since_pulse >= STIMULUS_INTERVAL:
			since_pulse = 0.0
			pulses += 1
			_perception.receive_noise(NoiseEvent.make(at, STIMULUS_LOUDNESS, &"mining", null, null))
		for hotspot: SuspicionHotspot in _suspicion.get_hotspots():
			peak = maxf(peak, hotspot.suspicion)
		committed = _behaviour.state() == CreatureAwarenessBehaviour.State.INVESTIGATE
	print(
		(
			"        %d pulses over %.1f s, peak hotspot suspicion %.3f, threshold %.2f"
			% [pulses, elapsed, peak, _settings.investigate_threshold]
		)
	)

	_check("a held stimulus at 60 m eventually forms a hotspot", peak > 0.0)
	_check("the alien commits to investigating it", committed)

	if not committed:
		return
	var goal: Vector3 = _behaviour.goal()
	_check("the goal is not the world origin (a stale hotspot id)", not goal.is_zero_approx())
	# The belief is displaced by hearing's jitter, so this is deliberately generous: the
	# assertion is that it points at the right CHAMBER, not at the exact stimulus.
	_check(
		"the goal is somewhere in the chamber the stimulus was in",
		goal.distance_to(at) <= CreatureAwarenessMap.CAVERN_RADIUS * 1.5
	)
	_check(
		"a route to it exists", _navigation.route != null and _navigation.route.anchors.size() > 0
	)


func _tick(seconds: float) -> float:
	var spent: float = 0.0
	while spent < seconds:
		await get_tree().physics_frame
		var delta: float = float(get_physics_process_delta_time())
		_perception.advance(delta)
		_suspicion.advance(delta)
		_perception.set_alertness_context(_suspicion.get_overall_suspicion())
		_behaviour.advance(delta)
		_navigation.advance(delta, _creature.global_position)
		spent += delta
	return spent


func _edges_crossing(graph: NavGraph, volume: AABB, normal_only: bool) -> int:
	var found: int = 0
	for edge: NavEdge in graph.all_edges():
		if normal_only and edge.type != NavEdge.Type.NORMAL_VOLUME:
			continue
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for step: int in 33:
			if volume.has_point(from.lerp(to, float(step) / 32.0)):
				found += 1
				break
	return found


func _bore(to: Vector3, girth: float) -> AABB:
	var from: Vector3 = CreatureAwarenessMap.DOCK
	var along: Vector3 = (to - from).normalized()
	var far_radius: float = (
		CreatureAwarenessMap.LOFT_RADIUS
		if to == CreatureAwarenessMap.LOFT
		else CreatureAwarenessMap.CAVERN_RADIUS
	)
	var start: Vector3 = from + along * (CreatureAwarenessMap.CAVERN_RADIUS + 1.0)
	var end: Vector3 = to - along * (far_radius + 1.0)
	return AABB(start, Vector3.ZERO).expand(end).grow(girth)


func _nodes_in_loft(graph: NavGraph) -> int:
	var found: int = 0
	for id: int in graph.node_ids():
		if (
			graph.node_at(id).position.distance_to(CreatureAwarenessMap.LOFT)
			<= CreatureAwarenessMap.LOFT_RADIUS
		):
			found += 1
	return found


func _check(what: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("  PASS  " + what)
		return
	_failures += 1
	# printerr, because a print piped into grep is block buffered and a failing run is
	# exactly the one you are watching the output of.
	printerr("  FAIL  " + what)
