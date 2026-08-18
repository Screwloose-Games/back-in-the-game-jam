class_name CreatureNavDemoPrototype
extends Node3D

## Click a wall; watch the alien work out how to get there.
##
##     RMB / T   send the creature to whatever you are pointing at
##     LMB       mine (F3 toggles brush size)
##     WASD      thrust, Space/Ctrl up and down, Q/E roll, Shift sprint
##     Esc       release the mouse
##     1-5       jump the creature's goal to each room
##     F1        world graph overlay      F2  locomotion + leap overlay
##     F3        mining brush size        F4  believed graph vs world graph
##     R         rebake
##
## WHAT TO TRY, IN ORDER. Each of these is one of section 43's acceptance scenarios, and
## each looks like nothing at all if you are not watching the label above the ball:
##
##   1  Send it to the Gallery. crawl -> tunnel_swim -> crawl (Scenario A).
##   2  Send it to the Warren. It compresses -- the ball visibly shrinks -- then wiggles
##      through the 2 m bore and expands (Scenario B).
##   3  Send it to the Vent Loft. PARTIAL route; it stops at the slot rather than grinding
##      into it. Fly through yourself to prove the opening is real (Scenarios C and G).
##   4  Send it to the top of the Gallery. It leaps rather than crawling round the walls
##      (Scenario D). Drag `leap_bias` up until it stops -- that is section 11.4's ~10 m.
##   5  Turn on `use_knowledge`, mine a new passage, press F4. The world graph has the
##      route and the believed graph does not; the alien has to find out (Scenario F).
##
## THE CAVE IS GENERATED, not saved into the .tscn -- the editor rewrites relative
## ext_resource paths on every re-save, and generated geometry cannot drift from the
## numbers its own file documents.

const PLAYER_SCENE := "res://prototypes/navigation/zero_g_player.tscn"
## RMB, and T. Registered at runtime rather than added to project.godot, so the prototype
## stays self-contained; LMB is the project-wide `mine` and is left alone.
##
## TWO EVENTS ON ONE ACTION RATHER THAN A SECOND CODE PATH. T is here because RMB is
## awkward while flying -- the mouse is captured for looking, so aiming and commanding are
## the same hand -- and a key on the same action means the two cannot drift apart. A match
## arm alongside the room hotkeys would have been a second call site for `_command`, and the
## standoff in there is the kind of thing that gets fixed in one of two places.
const COMMAND_ACTION := "creature_nav_demo_command"

@export var settings: CreatureNavDemoSettings = null

var _navigation: CreatureNavigation = null
var _creature: CreatureNavDemoCreature = null
var _map: CreatureNavDemoMap = null
var _player: Node3D = null
var _camera: Camera3D = null
var _graph_overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _hud: CreatureNavDemoHud = null
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
			_send_to(CreatureNavDemoMap.GALLERY_FLOOR)
		KEY_2:
			_send_to(CreatureNavDemoMap.WARREN_CENTRE)
		KEY_3:
			_send_to(CreatureNavDemoMap.VENT_LOFT_CENTRE)
		KEY_4:
			_send_to(CreatureNavDemoMap.GALLERY_HIGH)
		KEY_5:
			_send_to(CreatureNavDemoMap.DOCK_SPAWN)
		KEY_F1:
			_graph_overlay.visible = not _graph_overlay.visible
		KEY_F2:
			_locomotion_overlay.visible = not _locomotion_overlay.visible
		KEY_F3:
			_wide_brush = not _wide_brush
		KEY_F4:
			_navigation.use_knowledge = not _navigation.use_knowledge
			_graph_overlay.refresh_graph()
		KEY_R:
			_reset()


# ----- setup -----


func _build_map() -> void:
	_map = CreatureNavDemoMap.new()
	_map.name = "Cave"
	add_child(_map)


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	_navigation.config = _config
	add_child(_navigation)


func _build_creature() -> void:
	_creature = CreatureNavDemoCreature.new()
	_creature.name = "Creature"
	_creature.navigation = _navigation
	_creature.position = CreatureNavDemoMap.DOCK_SPAWN
	add_child(_creature)


## Instances the neighbouring prototype's zero-g player, unchanged.
##
## `bind_settings` there is typed `NavigationSettings` -- the OTHER prototype's class -- so
## a fresh instance is constructed rather than its committed .tres loaded. Loading it would
## couple two prototypes' saved playtest values together, and moving a slider here would
## silently retune a scene nobody opened.
func _build_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	_player = packed.instantiate()
	_player.position = CreatureNavDemoMap.DOCK_SPAWN + Vector3(4.0, 0.0, 4.0)
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

	_hud = get_node_or_null("HUD") as CreatureNavDemoHud
	if _hud != null:
		_hud.bind(_navigation, self)


## CSG BUILDS ITS COLLIDER DURING PROCESSING, so on the frame `_ready` runs there is no
## collision in the world at all -- and a bake against it finds nothing WITHOUT RAISING A
## SINGLE ERROR. Two physics frames, exactly as
## `prototypes/tentacle_crawler_chaser/tentacle_crawler_chaser_prototype.gd` does.
##
## The colliders here are plain StaticBody3D boxes rather than CSG, so strictly this only
## needs one frame -- but the CSG visual is in the same tree and the cost is two frames.
func _bake() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_navigation.bake(CreatureNavDemoMap.bounds())
	# The creature is held still until there is a graph. A frame-budgeted bake takes a
	# moment, and an alien that spends it planning against null looks stuck.
	var graph: NavGraph = await _navigation.graph_baked
	# Printed rather than only shown on the HUD, because a bake that finds NOTHING is the
	# one failure this prototype can have that looks like an empty room rather than an
	# error -- and it is exactly what happens if the colliders are not there yet.
	var stats: Dictionary = _navigation.bake_stats()
	print(
		(
			"[creature_nav_demo] baked %d nodes, %d edges (%d normal, %d wiggle)"
			% [graph.node_count(), graph.edge_count(), stats["edges_normal"], stats["edges_wiggle"]]
		)
	)
	_warn_if_the_slot_is_passable(graph)
	_creature.enabled = true


## Section 43's Scenarios C and G, checked on every bake.
##
## THE ONLY FAILURE IN THIS PROTOTYPE THAT LOOKS LIKE SUCCESS. An edge across the 1 m slot
## does not error, does not stall the alien and does not look wrong -- the creature simply
## gains a route it should not have and starts following the player into a vent. Every
## other way this scene can break is visible; this one has to be asserted.
func _warn_if_the_slot_is_passable(graph: NavGraph) -> void:
	var slot: AABB = CreatureNavDemoMap.PLAYER_SLOT.grow(0.25)
	for edge: NavEdge in graph.all_edges():
		var from: Vector3 = graph.node_at(edge.from_id).position
		var to: Vector3 = graph.node_at(edge.to_id).position
		for step: int in 33:
			if slot.has_point(from.lerp(to, float(step) / 32.0)):
				push_warning(
					(
						"Invariant 5 broken: an edge crosses the player-only slot. "
						+ "Scenarios C and G no longer hold in this scene."
					)
				)
				return


# ----- commanding -----


## Points a ray where the player is looking (or where the cursor is, if it has been
## released) and sends the creature to whatever it hits. RMB and T both land here.
func _command() -> void:
	var hit: Dictionary = _pick()
	if hit.is_empty():
		return
	# THE STANDOFF IS NOT OPTIONAL. The hit is ON the wall, so a goal placed there is
	# inside it, endpoint attachment fails at the destination, and every click returns a
	# PARTIAL route -- indistinguishable from broken pathfinding.
	var standoff: float = (
		_config.clearance_profile.normal_clearance() * settings.goal_standoff_scale
	)
	_send_to(Vector3(hit["position"]) + Vector3(hit["normal"]) * standoff)


func _send_to(target: Vector3) -> void:
	_navigation.set_goal(target)


func _mine() -> void:
	var hit: Dictionary = _pick()
	if hit.is_empty():
		return
	var size: float = (
		CreatureNavDemoKnobs.DIG_WIDE if _wide_brush else CreatureNavDemoKnobs.DIG_NARROW
	)
	var hole: AABB = _map.carve(Vector3(hit["position"]), size)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Section 24.2. The WORLD graph learns immediately; what the alien believes does not
	# change until it observes or inspects (Invariant 8).
	_navigation.notify_terrain_changed(hole)


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
		from, from + direction * CreatureNavDemoKnobs.PICK_RANGE, CreatureNavDemoMap.TERRAIN_LAYER
	)
	return _camera.get_world_3d().direct_space_state.intersect_ray(query)


func _reset() -> void:
	_creature.enabled = false
	_creature.velocity = Vector3.ZERO
	_creature.position = CreatureNavDemoMap.DOCK_SPAWN
	_navigation.clear_goal()
	_navigation.bake(CreatureNavDemoMap.bounds())
	_creature.enabled = true


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


func brush_is_wide() -> bool:
	return _wide_brush
