class_name NavKnowledgeGraph
extends RefCounted

## What the alien believes the cave looks like (navigation.md sections 27, 28).
##
## INVARIANT 8 IS THE ENTIRE POINT: "updating the world graph does not automatically
## update alien knowledge". The world graph is patched the instant the player mines;
## nothing here changes until an observation arrives or an inspection completes. That gap
## is not a limitation to be worked around -- it is the feature section 28 is asking for,
## and section 43's Scenario F is a test of the gap existing.
##
## IT NEVER MEASURES THE WORLD. There is no probe here, and `verify_navigation_static.gd`
## fails the build if this folder names one. Knowledge learns from observations it is
## handed and from a world graph it is handed; if it could look for itself, the alien
## would be omniscient by a shorter route than the one Invariant 9 blocks.
##
## THE SEAM IS `project()`. It returns a plain NavGraph, which the planner and the
## follower consume without knowing or caring where it came from -- which is exactly why
## `graph/` is forbidden from naming a probe, a builder or the facade. A believed graph
## and a real one have to be the same type, and that is what makes Invariant 9 cost
## nothing: not one line of `route/` changes when the alien starts planning on beliefs.
##
## TWO CLOCKS MEET HERE, AND THEY ARE NOT THE SAME CLOCK. `GeometryObservation.observed_at`
## is on perception's clock; `now` is navigation's. Both start at zero and drift apart.
## The rule: an observation's own timestamp is authoritative for when it was seen, and
## navigation's clock is used only for events navigation originates -- ageing, grind
## aborts, inspections.

## Keyed by world node id -> NavKnownNode. Untyped because gdlint's parser rejects
## Dictionary[K, V], the same reason NavAStar.edge_costs is untyped.
var _nodes: Dictionary = {}
## Keyed by NavAStar.key_for(a, b) -> NavKnownEdge.
var _edges: Dictionary = {}
## Suspected openings have no world node id to key on -- the alien noticed a space, not a
## node -- so they are held apart. They are never projected either way (section 40.6).
var _suspected: Array[NavKnownNode] = []
var _cache: NavGraph = null
var _dirty: bool = true

# ----- learning -----


## Section 20 of spatial_memory: the alien has lived here, and knows the shape of it.
##
## What it does NOT know is what has changed since, which is the interesting half and the
## reason `knowledge_starts_known` defaults true for a resident creature.
func learn_all(world: NavGraph, now: float) -> void:
	if world == null:
		return
	for id: Variant in world.node_ids():
		learn_node(world.node_at(id), now, NavKnowledgeState.State.KNOWN)
	for edge: NavEdge in world.all_edges():
		learn_edge(edge, now, NavKnowledgeState.State.KNOWN)


func learn_node(node: NavNode, now: float, state: NavKnowledgeState.State) -> void:
	if node == null:
		return
	_nodes[node.id] = NavKnownNode.make(node, state, now)
	_dirty = true


func learn_edge(edge: NavEdge, now: float, state: NavKnowledgeState.State) -> void:
	if edge == null:
		return
	_edges[NavAStar.key_for(edge.from_id, edge.to_id)] = NavKnownEdge.make(edge, state, now)
	_dirty = true


## Section 30's payoff: an inspection completed, so this much of the world may now be
## believed.
##
## THE ONLY PATH BY WHICH AUTHORITATIVE TOPOLOGY ENTERS, and it is never called
## automatically. Section 29 puts it at the END of the RELEARNING beat, which is the whole
## of "delayed knowledge acquisition": mid-inspection, the believed graph is byte-identical
## to what it was before.
func learn_region(world: NavGraph, at: Vector3, radius: float, now: float) -> NavKnowledgeUpdate:
	var update := NavKnowledgeUpdate.new()
	if world == null:
		return update
	var learned: Dictionary = {}
	_learn_ball(world, at, radius, now, learned, update)
	_learn_edges_among(world, learned, now)
	_forget_suspected_near(at, radius)
	return update


## The same payoff, following the geometry rather than a radius: everything the alien had
## no opinion about that CONNECTS to what it just looked at.
##
## THE BALL ALONE MAKES THE ALIEN STOP SEVEN TIMES IN ONE TUNNEL. `_observe_one` plants a
## suspicion every `node_separation` of unbelieved free space, and each one is a section 29
## stop; a `relearn_radius` ball resolves the first 6 m of a 20 m passage and leaves the
## rest to be noticed again a few metres later. One continuous section is one thing to
## investigate, so one inspection should finish it.
##
## CONNECTED MEANS THROUGH WORLD EDGES, NOT THROUGH PROXIMITY. Section 13.2's edges are
## shape-cast validated, so following them says "the body can actually get from here to
## there at this size". Clustering the suspicion POINTS instead would join two of them a
## metre apart through a wall, which is the specific mistake this module exists to avoid.
##
## What it learns out here is PARTIALLY_EXPLORED rather than KNOWN, and the distinction is
## the honest one: the alien looked down the passage from its mouth. Routable at remembered
## cost, at half confidence -- not the memory of having been there.
func learn_connected_region(
	world: NavGraph, at: Vector3, config: NavigationConfig, now: float
) -> NavKnowledgeUpdate:
	var update := NavKnowledgeUpdate.new()
	if world == null:
		return update
	var learned: Dictionary = {}
	var frontier: Array[int] = _learn_ball(world, at, config.relearn_radius, now, learned, update)

	var cursor: int = 0
	var capped: bool = false
	while cursor < frontier.size() and not capped:
		var id: int = frontier[cursor]
		cursor += 1
		for neighbor: int in world.get_neighbors(id):
			# Anything already believed ends the flood here, whatever the belief is.
			# `learned` catches this call's own work and `_nodes` every earlier one.
			#
			# STALE IS A WALL AND NOT A DOORWAY, which is the reason this is not simply
			# "not routable". `age()` turns every KNOWN node STALE after a few minutes of
			# not looking at it, so a flood that crossed STALE would hand the alien the
			# whole cave on any inspection late in a run.
			if learned.has(neighbor) or _nodes.has(neighbor):
				continue
			var node: NavNode = world.node_at(neighbor)
			if node == null:
				continue
			if node.position.distance_to(at) > config.relearn_connected_radius:
				update.truncated = true
				continue
			if learned.size() >= config.relearn_max_nodes:
				update.truncated = true
				capped = true
				break
			learn_node(node, now, NavKnowledgeState.State.PARTIALLY_EXPLORED)
			learned[neighbor] = NavKnowledgeState.State.PARTIALLY_EXPLORED
			update.changed_nodes.append(neighbor)
			frontier.append(neighbor)

	_learn_edges_among(world, learned, now)
	_forget_suspected_near(at, config.relearn_radius)
	# The rest of the section, not just the ball. A suspicion left standing beside geometry
	# the alien now believes is a stop it will make again for somewhere it has already been.
	_forget_suspected_covered(learned.keys(), config.node_separation)
	return update


# ----- observation -----


## Section 9 of spatial_memory, and the wiring line perception's README already writes.
##
## `observations` is UNTYPED on purpose: the elements are perception's GeometryObservation,
## and typing the parameter would make this module fail to parse in a project that has
## navigation and not perception. The fields are read by duck-typing, which is the price.
func observe_geometry_batch(observations: Array, config: NavigationConfig) -> NavKnowledgeUpdate:
	var update := NavKnowledgeUpdate.new()
	for observation: Variant in observations:
		_observe_one(observation, config, update)
	if not update.is_empty():
		_dirty = true
	return update


## Section 40.2. The alien tried this and got nowhere; prefer the other way.
func mark_edge_questionable(a: int, b: int, now: float, config: NavigationConfig) -> void:
	var known: NavKnownEdge = _edges.get(NavAStar.key_for(a, b))
	if known == null:
		return
	known.questionable = true
	known.confidence *= config.knowledge_contradiction_penalty
	known.last_observed_time = now
	_dirty = true


## Section 12 of spatial_memory. Belief in unvisited terrain fades.
##
## DELIBERATELY VERY SLOW. Terrain does not move, so memory of it should decay orders of
## magnitude more slowly than memory of a player -- the default loses 0.002 per second,
## which takes five minutes to move a certain memory into STALE.
func age(delta: float, config: NavigationConfig) -> void:
	if config.knowledge_decay_per_second <= 0.0:
		return
	var loss: float = config.knowledge_decay_per_second * delta
	for id: Variant in _nodes:
		var known: NavKnownNode = _nodes[id]
		if known.state != NavKnowledgeState.State.KNOWN:
			continue
		known.confidence = maxf(known.confidence - loss, 0.0)
		if known.confidence <= config.knowledge_stale_confidence:
			known.state = NavKnowledgeState.State.STALE
			_dirty = true


# ----- reading -----


func node_state(world_id: int) -> NavKnowledgeState.State:
	var known: NavKnownNode = _nodes.get(world_id)
	return known.state if known != null else NavKnowledgeState.State.UNKNOWN


func edge_state(a: int, b: int) -> NavKnowledgeState.State:
	var known: NavKnownEdge = _edges.get(NavAStar.key_for(a, b))
	return known.state if known != null else NavKnowledgeState.State.UNKNOWN


func is_dirty() -> bool:
	return _dirty


## The believed cave, as a graph the planner consumes unchanged.
##
## Cached and rebuilt only when something actually changed -- section 32's "event driven",
## not per frame. A cave-sized projection every tick would be the most expensive thing in
## the module by a wide margin, and it would recompute an identical answer.
func project(config: NavigationConfig) -> NavGraph:
	if not _dirty and _cache != null:
		return _cache
	var graph := NavGraph.new()
	# The same triple NavGraphBuilder configures a baked graph with. A projection bucketed
	# differently would answer find_nearby_nodes differently, and endpoint attachment
	# would start behaving differently depending on which graph it was handed.
	graph.configure(
		maxf(config.node_separation, config.edge_search_radius * 0.5),
		config.chunk_size,
		config.best_seconds_per_metre()
	)
	for id: Variant in _nodes:
		var known: NavKnownNode = _nodes[id]
		if known.is_routable():
			graph.add_node_with_id(known.world_node_id, known.position, known.clearance)
	for key: Variant in _edges:
		var edge: NavKnownEdge = _edges[key]
		if not edge.is_routable():
			continue
		if not graph.has_node(edge.from_id) or not graph.has_node(edge.to_id):
			continue
		graph.add_edge(
			NavEdge.make(
				edge.from_id,
				edge.to_id,
				edge.type,
				edge.distance,
				edge.min_clearance,
				edge.planning_cost(config)
			)
		)
	_cache = graph
	_dirty = false
	return graph


func counts() -> Dictionary:
	var by_state: Dictionary = {}
	for id: Variant in _nodes:
		var label: String = NavKnowledgeState.state_name(_nodes[id].state)
		by_state[label] = int(by_state.get(label, 0)) + 1
	by_state["suspected_openings"] = _suspected.size()
	by_state["edges"] = _edges.size()
	return by_state


func debug_state() -> Dictionary:
	return {"nodes": _nodes.size(), "edges": _edges.size(), "states": counts()}


## Suspected openings, for the section 39 overlay and for inspection targeting.
func suspected_openings() -> Array[NavKnownNode]:
	return _suspected


# ----- internals -----


## Section 29's mismatch detection.
##
## THIS IS KNOWLEDGE'S JOB AND NOT PERCEPTION'S, because a GeometryObservation carries no
## delta -- it is a stateless report about one cell right now, with no notion of
## "changed", "unexpected" or "previously". Comparing it against a prior belief requires
## the prior belief, which lives here and nowhere else.
func _observe_one(
	observation: Variant, config: NavigationConfig, update: NavKnowledgeUpdate
) -> void:
	var at: Vector3 = observation.position
	var seen_at: float = observation.observed_at
	var nearest: NavKnownNode = _nearest_believed(at, config.node_separation)

	if _reads_as_solid(observation, config):
		if nearest == null or not nearest.is_routable():
			return
		# Contradiction: passage was believed here. STALE rather than INVALID -- section 29
		# wants this inspected before it is acted on as fact.
		nearest.state = NavKnowledgeState.State.STALE
		nearest.confidence *= config.knowledge_contradiction_penalty
		nearest.last_observed_time = seen_at
		_stale_edges_of(nearest.world_node_id)
		update.changed_nodes.append(nearest.world_node_id)
		update.contradictions.append(at)
		return

	if nearest != null:
		# Confirmation. Blend toward what was seen rather than snapping, so one distant
		# glimpse cannot overwrite a memory formed by walking through.
		nearest.confidence = lerpf(
			nearest.confidence, observation.confidence, config.knowledge_learn_rate
		)
		nearest.last_observed_time = seen_at
		return
	if _has_suspicion_near(at, config.node_separation):
		return
	# Free space where nothing was believed at all: section 40.6's unknown opening.
	_suspected.append(NavKnownNode.suspected(at, seen_at))
	update.suspected_openings.append(at)


## SOLID, or a clearance report too tight for the alien's compressed body -- which is the
## same news as far as navigation is concerned.
func _reads_as_solid(observation: Variant, config: NavigationConfig) -> bool:
	var kind: int = observation.type
	if kind == GeometryObservation.ObservationType.SOLID:
		return true
	if kind != GeometryObservation.ObservationType.CLEARANCE:
		return false
	return observation.clearance < config.clearance_profile.min_traversal_clearance()


func _nearest_believed(at: Vector3, radius: float) -> NavKnownNode:
	var best: NavKnownNode = null
	var nearest: float = radius
	for id: Variant in _nodes:
		var known: NavKnownNode = _nodes[id]
		var span: float = known.position.distance_to(at)
		if span <= nearest:
			nearest = span
			best = known
	return best


func _has_suspicion_near(at: Vector3, radius: float) -> bool:
	for known: NavKnownNode in _suspected:
		if known.position.distance_to(at) <= radius:
			return true
	return false


## The seed pass both learn functions share: the ball around a completed inspection, at
## full confidence. Fills `learned` with id -> state and returns the ids in order.
func _learn_ball(
	world: NavGraph,
	at: Vector3,
	radius: float,
	now: float,
	learned: Dictionary,
	update: NavKnowledgeUpdate
) -> Array[int]:
	var seeds: Array[int] = []
	for id: int in world.find_nearby_nodes(at, radius):
		learn_node(world.node_at(id), now, NavKnowledgeState.State.KNOWN)
		learned[id] = NavKnowledgeState.State.KNOWN
		update.changed_nodes.append(id)
		seeds.append(id)
	return seeds


## Every world edge joining two nodes this call learned.
##
## EDGES AS WELL AS NODES. Learning the nodes alone gives the alien a memory of places it
## cannot get between, which routes exactly as badly as not learning them at all.
##
## Walked through adjacency rather than through `all_edges()`, which is what this used to
## do: a connected relearn learns far more nodes than a ball did, and a scan of every edge
## in the cave per inspection is a section 32 problem waiting for a big enough cave.
##
## A PARTIALLY_EXPLORED edge is only ever written where there was no belief at all. An
## edge the alien had walked must not be downgraded to one it merely glimpsed.
func _learn_edges_among(world: NavGraph, learned: Dictionary, now: float) -> void:
	for id: Variant in learned:
		for neighbor: int in world.get_neighbors(id):
			if not learned.has(neighbor):
				continue
			var edge: NavEdge = world.edge_between(id, neighbor)
			if edge == null:
				continue
			var both_walked: bool = (
				learned[id] == NavKnowledgeState.State.KNOWN
				and learned[neighbor] == NavKnowledgeState.State.KNOWN
			)
			if both_walked:
				learn_edge(edge, now, NavKnowledgeState.State.KNOWN)
				continue
			if _edges.has(NavAStar.key_for(id, neighbor)):
				continue
			learn_edge(edge, now, NavKnowledgeState.State.PARTIALLY_EXPLORED)


func _forget_suspected_near(at: Vector3, radius: float) -> void:
	var kept: Array[NavKnownNode] = []
	for known: NavKnownNode in _suspected:
		if known.position.distance_to(at) > radius:
			kept.append(known)
	_suspected = kept


## Drops every suspicion that now sits beside something believed.
##
## `radius` IS `node_separation` AT THE ONE CALLER, and that is not a coincidence: it is
## exactly the distance at which `_observe_one` will find a believed node and read a future
## observation as a confirmation. Matching it makes the two rules agree -- nothing dropped
## here could be suspected again, and nothing kept here is being forgotten wrongly.
func _forget_suspected_covered(ids: Array, radius: float) -> void:
	if _suspected.is_empty() or ids.is_empty():
		return
	var kept: Array[NavKnownNode] = []
	for known: NavKnownNode in _suspected:
		var covered: bool = false
		for id: Variant in ids:
			var believed: NavKnownNode = _nodes.get(id)
			if believed != null and believed.position.distance_to(known.position) <= radius:
				covered = true
				break
		if not covered:
			kept.append(known)
	_suspected = kept


## Every connection touching a contradicted node becomes doubtful too. Leaving them KNOWN
## gives the alien a node it distrusts joined by edges it does not, which routes straight
## through the thing it was supposed to be wary of.
func _stale_edges_of(world_id: int) -> void:
	for key: Variant in _edges:
		var edge: NavKnownEdge = _edges[key]
		if edge.from_id != world_id and edge.to_id != world_id:
			continue
		if edge.state == NavKnowledgeState.State.KNOWN:
			edge.state = NavKnowledgeState.State.STALE
