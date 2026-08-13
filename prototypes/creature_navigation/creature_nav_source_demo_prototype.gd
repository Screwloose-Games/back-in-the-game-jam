class_name CreatureNavSourceDemoPrototype
extends Node3D

## NavigationSource, baking a navigation graph out of an arbitrary concave mesh that the
## player can change while the alien is using it.
##
##     RMB / T   send the creature to whatever you are pointing at
##     LMB       mine (F3 toggles brush size)
##     WASD      thrust, Space/Ctrl up and down, Q/E roll, Shift sprint
##     Esc       release the mouse
##     1-3       jump the creature's goal to each chamber
##     F1        graph overlay      F2  locomotion + leap overlay
##     F3        mining brush size  R   rebake
##
## THIS SCENE EXISTS FOR ONE COMPONENT. `creature_nav_demo_prototype.tscn` next door is the
## tour of everything the navigation module can do; this is the answer to "what do we drop
## into the real level". The answer is `NavigationSource`, and everything here is either the
## source, the arbitrary mesh it bakes, or the minimum needed to see that it worked.
##
## THE THREE THINGS TO CHECK, IN ORDER:
##
##   1  F1, and look at the rock. NOTHING may be inside it. Then set `use_flood = false` on
##      the source, press R, and look again: the section 12.1 sweep fills the stone with
##      maximum-clearance nodes, because a concave trimesh has no interior and every point
##      deep inside one measures as wide open. That contrast IS the reason this scene is
##      here.
##   2  Send the creature to chamber B (key 2). It crosses the wide diagonal bore.
##   3  Send it to chamber C (key 3). The route comes back PARTIAL and it stops at the
##      1.2 m bore rather than grinding into it -- and chamber C is FULL of nodes on the
##      other side, which is Invariant 5 being a property of edge validation rather than of
##      the sampler. Fly through the bore yourself to prove the opening is real.
##
## THEN MINE. A hole between two chambers is patched into the shared graph within a second,
## and the route re-plans through it; the creature never re-bakes anything, because the
## graph is not its. Mine into the rock away from everything and the patch correctly finds
## nothing to connect.
##
## THE CAVE IS GENERATED, not saved into the .tscn, for the same reason the neighbouring
## scene's is: the editor rewrites relative ext_resource paths on every re-save, and
## generated geometry cannot drift from the numbers its own file documents.

const PLAYER_SCENE := "res://prototypes/navigation/zero_g_player.tscn"
## RMB and T on one action. See creature_nav_demo_prototype.gd -- same reasoning, and a
## different action name so the two scenes cannot fight over one InputMap entry.
const COMMAND_ACTION := "creature_nav_source_demo_command"
## Radius of the alien-sized brush. Comfortably above the normal body's 1.25 m envelope, so
## what it carves is a passage the alien can actually use.
const DIG_WIDE: float = 2.5
## Radius of the player-only brush. Below the squeezed body's 0.75 m, so the graph gains
## open space the alien still cannot follow the player into.
const DIG_NARROW: float = 0.55
const PICK_RANGE: float = 200.0
## How long to wait for CSG to hand its rebuilt trimesh to the physics server. Frames, not
## seconds -- see `_await_collider`.
const COLLIDER_WAIT_FRAMES: int = 30

@export var settings: CreatureNavDemoSettings = null

var _source: NavigationSource = null
var _navigation: CreatureNavigation = null
var _creature: CreatureNavDemoCreature = null
var _map: CreatureNavSourceDemoMap = null
var _player: Node3D = null
var _camera: Camera3D = null
var _graph_overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _hud: CreatureNavSourceDemoHud = null
var _config: NavigationConfig = null
var _wide_brush: bool = true


func _enter_tree() -> void:
	if not InputMap.has_action(COMMAND_ACTION):
		InputMap.add_action(COMMAND_ACTION)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(COMMAND_ACTION, click)
		var key := InputEventKey.new()
		key.keycode = KEY_T
		InputMap.action_add_event(COMMAND_ACTION, key)


func _ready() -> void:
	if settings == null:
		settings = CreatureNavDemoSettings.new()
		push_warning("No creature_nav_demo_settings.tres wired; running on knobs defaults.")
	settings.changed.connect(_apply_settings)

	_config = NavigationConfig.new()
	_build_map()
	_build_source()
	_build_navigation()
	_build_creature()
	_build_player()
	_build_overlays()
	_apply_settings()
	await _bake()


func _process(_delta: float) -> void:
	if _hud != null:
		_hud.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(COMMAND_ACTION):
		_command()
		return
	if event.is_action_pressed("mine"):
		_mine()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_navigation.set_goal(CreatureNavSourceDemoMap.CHAMBER_A)
		KEY_2:
			_navigation.set_goal(CreatureNavSourceDemoMap.CHAMBER_B)
		KEY_3:
			_navigation.set_goal(CreatureNavSourceDemoMap.CHAMBER_C)
		KEY_F1:
			_graph_overlay.visible = not _graph_overlay.visible
		KEY_F2:
			_locomotion_overlay.visible = not _locomotion_overlay.visible
		KEY_F3:
			_wide_brush = not _wide_brush
		KEY_R:
			_reset()


func brush_is_wide() -> bool:
	return _wide_brush


func digs_spent() -> int:
	return _map.digs


# ----- setup -----


func _build_map() -> void:
	_map = CreatureNavSourceDemoMap.new()
	_map.name = "Cave"
	add_child(_map)


## THE DELIVERABLE, WIRED THE WAY A REAL LEVEL WOULD WIRE IT. Bounds, seeds, a config; no
## bake_bounds on the node itself, because the collider does not exist yet -- see `_bake`.
func _build_source() -> void:
	_source = NavigationSource.new()
	_source.name = "NavigationSource"
	_source.config = _config
	_source.air_seeds = CreatureNavSourceDemoMap.air_seeds()
	add_child(_source)


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	_navigation.config = _config
	# The whole split, in one line. This navigator now owns a route and a belief and nothing
	# else; a second creature added here would share the graph rather than re-bake it.
	_navigation.source = _source
	add_child(_navigation)


func _build_creature() -> void:
	_creature = CreatureNavDemoCreature.new()
	_creature.name = "Creature"
	_creature.navigation = _navigation
	_creature.position = CreatureNavSourceDemoMap.CHAMBER_A
	add_child(_creature)


func _build_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	_player = packed.instantiate()
	_player.position = CreatureNavSourceDemoMap.CHAMBER_A + Vector3(0.0, 3.0, 4.0)
	add_child(_player)
	_camera = _player.get_node("HeadCamera")
	_camera.far = CreatureNavDemoKnobs.CAMERA_FAR


func _build_overlays() -> void:
	_graph_overlay = NavigationDebugDraw.new()
	_graph_overlay.navigation = _navigation
	add_child(_graph_overlay)

	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.navigation = _navigation
	add_child(_locomotion_overlay)

	_hud = get_node_or_null("HUD") as CreatureNavSourceDemoHud
	if _hud != null:
		_hud.bind(_source, _navigation, self)


func _bake() -> void:
	await _await_collider(
		CreatureNavSourceDemoMap.CHAMBER_A, CreatureNavSourceDemoMap.CHAMBER_A_RADIUS
	)
	_source.bake(CreatureNavSourceDemoMap.bounds())
	# The creature is held still until there is a graph. A frame-budgeted bake takes a
	# moment, and an alien that spends it planning against null looks stuck.
	var graph: NavGraph = await _source.graph_baked
	# Printed rather than only shown on the HUD, because a bake that finds NOTHING is the one
	# failure this scene can have that looks like an empty cave rather than an error.
	print(
		(
			"[creature_nav_source_demo] baked %d nodes, %d edges from %d seeds"
			% [graph.node_count(), graph.edge_count(), _source.seeds().size()]
		)
	)
	_warn_if_the_tight_bore_is_passable(graph)
	_creature.enabled = true


## Waits for the CSG trimesh to reach the physics server, by asking whether it has.
##
## DO NOT COUNT FRAMES HERE. CSG remeshes on the main thread during _process and the new
## collider reaches Jolt on the step after that, so "two physics frames" is what the rest of
## this repo does and it is a MEASUREMENT rather than a contract -- and the failure when it
## is wrong is silent. A bake against a collider that is not there yet does not error: every
## shape cast reports clear, every candidate reports the clearance ceiling, and the graph
## comes back full of nodes inside solid rock, which is exactly the symptom this whole scene
## exists to make visible. Polling a witness costs nothing and cannot be wrong.
func _await_collider(witness: Vector3, radius: float) -> void:
	for _attempt: int in COLLIDER_WAIT_FRAMES:
		await get_tree().physics_frame
		if _is_carved(witness, radius):
			return
	push_warning("creature_nav_source_demo: the CSG collider never appeared; baking anyway.")


## Whether a pocket of roughly `radius` exists at `witness`, asked with RAYS rather than
## with an overlap test.
##
## THE OBVIOUS TEST IS THE ONE THAT CANNOT WORK HERE, and it is worth stating plainly because
## it was written first and looked right. `shape_fits` at the witness is an OVERLAP test, and
## a concave trimesh has no interior -- so a point buried in solid stone touches no triangle
## and reports "it fits" just as loudly as a point in mid-air. It answers "has this been
## carved?" with yes both before and after the carve, and with yes again when there is no
## collider in the world at all.
##
## A ray does work. From inside a fresh cavity it strikes the cavity's own wall at about
## `radius`; from inside undisturbed rock it crosses only back faces, which Godot's trimesh
## collision does not report; and in an empty world it hits nothing. Six of them, because a
## single axis can look straight down a bore and miss.
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


## Invariant 5, checked on every bake.
##
## THE ONLY FAILURE IN THIS SCENE THAT LOOKS LIKE SUCCESS. An edge across the 1.2 m bore
## does not error, does not stall the alien and does not look wrong -- the creature simply
## gains a route it should not have and follows the player into chamber C. Every other way
## this scene can break is visible; this one has to be asserted.
##
## ITS COMPANION IS THE OTHER HALF OF SCENARIO G: chamber C must be FULL of nodes. A bake
## that never reached it would pass the check above for entirely the wrong reason.
func _warn_if_the_tight_bore_is_passable(graph: NavGraph) -> void:
	var bore: AABB = CreatureNavSourceDemoMap.tight_bore_volume()
	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for step: int in 33:
			if bore.has_point(from.lerp(to, float(step) / 32.0)):
				push_warning(
					(
						"Invariant 5 broken: an edge crosses the 1.2 m bore. "
						+ "Scenarios C and G no longer hold in this scene."
					)
				)
				return
	if _nodes_in_chamber_c(graph) == 0:
		push_warning(
			(
				"Chamber C has no nodes, so the check above proves nothing: the flood never "
				+ "crossed the tight bore. Look at flood_passage_radius."
			)
		)


func _nodes_in_chamber_c(graph: NavGraph) -> int:
	var found: int = 0
	var reach: float = CreatureNavSourceDemoMap.CHAMBER_C_RADIUS
	for id: Variant in graph.node_ids():
		if graph.node_at(id).position.distance_to(CreatureNavSourceDemoMap.CHAMBER_C) < reach:
			found += 1
	return found


# ----- commanding -----


func _command() -> void:
	var hit: Dictionary = _pick()
	if hit.is_empty():
		return
	# THE STANDOFF IS NOT OPTIONAL. The hit is ON the wall, so a goal placed there is inside
	# it, endpoint attachment fails at the destination, and every click returns a PARTIAL
	# route -- indistinguishable from broken pathfinding.
	var standoff: float = (
		_config.clearance_profile.normal_clearance() * settings.goal_standoff_scale
	)
	_navigation.set_goal(Vector3(hit["position"]) + Vector3(hit["normal"]) * standoff)


func _mine() -> void:
	var hit: Dictionary = _pick()
	if hit.is_empty():
		return
	var radius: float = DIG_WIDE if _wide_brush else DIG_NARROW
	var at: Vector3 = Vector3(hit["position"]) - Vector3(hit["normal"]) * (radius * 0.5)
	var hole: AABB = _map.carve(at, radius)
	if hole.size.is_zero_approx():
		return
	await _await_collider(at, radius)
	# Section 24.2. The source patches the shared graph; what the alien BELIEVES does not
	# change until it observes or inspects (Invariant 8).
	_source.notify_terrain_changed(hole)


func _pick() -> Dictionary:
	if _camera == null:
		return {}
	var from: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_transform.basis.z
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var at: Vector2 = get_viewport().get_mouse_position()
		from = _camera.project_ray_origin(at)
		direction = _camera.project_ray_normal(at)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + direction * PICK_RANGE, CreatureNavSourceDemoMap.TERRAIN_LAYER
	)
	return _camera.get_world_3d().direct_space_state.intersect_ray(query)


func _reset() -> void:
	_creature.enabled = false
	_creature.velocity = Vector3.ZERO
	_creature.position = CreatureNavSourceDemoMap.CHAMBER_A
	_navigation.clear_goal()
	await _bake()


# ----- settings -----


## Must not write back to `settings`, or it re-enters `changed`.
func _apply_settings() -> void:
	settings.apply_to(_config)
	_navigation.use_knowledge = settings.use_knowledge
	if _graph_overlay != null:
		_graph_overlay.draw_graph = settings.show_world_graph
		_graph_overlay.refresh_graph()
	if _locomotion_overlay != null:
		_locomotion_overlay.visible = settings.show_locomotion
