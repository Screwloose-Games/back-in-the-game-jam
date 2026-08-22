class_name AsteroidLevel
extends Node3D

## Playable asteroid and game-specific multiplayer composition root.
##
## OnlineSession owns connection lifecycle; this scene owns what a connected
## peer means here: one deterministically named player spawned by peer 1.

const HOST_PEER_ID := 1
const CLIENT_PEER_ID := 2
const PEER_SPAWN_AHEAD_METRES := 2.5
const PLAYER_SCENE := preload("res://prefabs/character/player/prefab_player.tscn")
const NETWORK_PLAYER_SCENE := preload("res://prefabs/character/player/prefab_network_player.tscn")
const CREATURE_SCENE := preload("res://prefabs/character/creature/prefab_creature.tscn")
## Layer 1, `hull`. Bit 2 is `player`, and a creature that probes it holds itself a body
## radius off the thing it is trying to bite.
const WORLD_MASK := 1
## Slack around the mine's own markers, because bake seeds are snapped to lattice cells and
## a cell outside the region is refused.
const BAKE_MARGIN_M := 8.0
## Matches NavigationConfig.normal_speed, which is what every route is costed against.
const CREATURE_MAX_SPEED := 6.0
## How far the alien can hear at all, pushed onto its PerceptionConfig.
##
## RAISED FROM THE MODULE'S 40 M DEFAULT BECAUSE THIS ASTEROID IS BIGGER THAN THE SANDBOX
## THAT NUMBER WAS TUNED IN. Hearing falls off as (1 - d/range)^2 and `received_strength`
## returns a hard 0.0 past the range, so at 40 m a drill two chambers away produces no
## evidence at all -- nothing in the log, which is indistinguishable from a broken chain.
##
## 120, AND 90 WAS MEASURED WRONG in the awareness prototype. Range does not only decide
## what is audible, it decides CONFIDENCE, and confidence is what makes a record survive
## long enough to accumulate: at 90 m a stimulus 60 m away arrives at confidence 0.06 and is
## pruned before anything can cluster, so twenty seconds of holding the beam produced no
## hotspot. At 120 it arrives at 0.21, one pulse forms a faint lead and holding turns that
## lead into a commitment. See prototypes/creature_awareness/creature_awareness_knobs.gd.
const CREATURE_HEARING_RANGE_M := 120.0

## Whether the opening cutscene runs. Off is how you work on anything else in
## this level without watching a descent first.
@export var play_intro: bool = true

var _connection_screen: LoadingScreen
var _transport_ready := false
var _returning_to_menu := false
var _host_spawn_scheduled := false
var _local_player_presentation_started := false
var _local_player_ready := false
var _intro_played := false
var _creature: CreatureAgent
var _director: EncounterDirector
var _debug_panels: VBoxContainer
var _graph_overlay: NavigationDebugDraw
var _locomotion_overlay: NavigationLocomotionDraw
var _trail_overlay: CreatureTrailDraw
var _suspicion_overlay: SuspicionDebugDraw
var _perception_overlay: PerceptionDebugDraw
var _director_panel: DirectorDebugPanel
var _behavior_panel: BehaviorDebugPanel
var _navigation_panel: NavigationDebugPanel
var _perception_panel: PerceptionDebugPanel

@onready var intro: ElevatorIntro = $ElevatorIntro
@onready var players: Node3D = %Players
@onready var player_spawn: Marker3D = %PlayerSpawn
@onready var player_spawner: MultiplayerSpawner = %PlayerSpawner
@onready var creature_spawn: Marker3D = %CreatureInitialSpawnMarker3D


func _ready() -> void:
	player_spawner.spawn_function = _spawn_network_player
	OnlineSession.entry_status_changed.connect(_on_entry_status_changed)
	OnlineSession.entry_ready.connect(_on_entry_ready)
	OnlineSession.entry_failed.connect(_on_entry_failed)
	OnlineSession.session_ended.connect(_on_session_ended)
	OnlineSession.peer_left.connect(_on_peer_left)
	multiplayer.peer_connected.connect(_on_scene_peer_connected)
	player_spawner.spawned.connect(_on_player_spawned)

	# Shown in every mode, not just online: the screen is what the shader warm-up
	# hides behind, and solo needs that as much as a joining peer does.
	_show_connection_screen()
	var result: Error = OnlineSession.begin_queued_entry()
	if result != OK:
		_return_to_main_menu("Could not enter the selected session. Error: %d" % result)
		return
	GlobalSignalBus.level_started.emit()


func _exit_tree() -> void:
	if OnlineSession.is_online() and not _returning_to_menu:
		OnlineSession.leave("Gameplay level exited.")


func _spawn_network_player(raw_data: Variant) -> Node:
	if typeof(raw_data) != TYPE_DICTIONARY:
		push_error("Network player spawn data must be a Dictionary.")
		return Node.new()
	var data: Dictionary = raw_data
	var peer_id := int(data.get("peer_id", 0))
	var spawn_transform: Transform3D = data.get("transform", Transform3D.IDENTITY)
	if peer_id not in [HOST_PEER_ID, CLIENT_PEER_ID]:
		push_error("Network player spawn used invalid peer ID %d." % peer_id)
		return Node.new()

	var player := NETWORK_PLAYER_SCENE.instantiate() as Node3D
	player.name = str(peer_id)
	player.transform = spawn_transform
	var driver := player.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	driver.configure(peer_id, multiplayer.get_unique_id())
	return player


func _spawn_solo_player() -> void:
	if players.get_node_or_null("Player") != null:
		return
	var player := PLAYER_SCENE.instantiate() as Node3D
	player.name = "Player"
	player.transform = players.global_transform.affine_inverse() * player_spawn.global_transform
	var body := player.get_node("PlayerBody")
	(body.get_node("Visibility") as PlayerVisibility).is_local_player = true
	var input := body.get_node("Input") as PlayerInput
	input.enabled = true
	input.captures_mouse = true
	(body.get_node("Head/HeadCamera") as Camera3D).current = true
	players.add_child(player)
	_start_creature()


## Everything the alien needs that only the level can supply: the baked graph, the Director,
## the noise wire and the nests. Solo only for now.
##
## `navigation.source` is read once, in CreatureNavigation._ready(), so it has to be assigned
## before the creature enters the tree -- one authored into the scene would plan against a
## null graph for the whole session without saying so.
func _start_creature() -> void:
	var mine := $LevelFullBlockout/MineBlockout as MineLevel
	var seeds := PackedVector3Array()
	for space: MineSpace in mine.spaces_in_level():
		seeds.append(space.global_position)
	if seeds.is_empty():
		push_error("Asteroid level has no mine spaces to seed navigation from.")
		return

	var crawler := CREATURE_SCENE.instantiate() as CrawlerBody
	crawler.probe_mask = WORLD_MASK
	(crawler.get_node("Tentacles") as TentacleArray).query_mask = WORLD_MASK
	# The prefab is tuned for a player-driven marker in a straight corridor. Routing plans
	# against NavigationConfig.normal_speed, so the body has to be able to keep that promise
	# and no more -- at the prototype's 30 it crosses a chamber between two route anchors.
	crawler.max_speed = CREATURE_MAX_SPEED
	_creature = crawler.get_node("Agent") as CreatureAgent
	var behavior := crawler.get_node("Behavior") as CreatureBehavior
	var navigation := crawler.get_node("Navigation") as CreatureNavigation
	var perception := crawler.get_node("Perception") as CreaturePerception
	# Mutated in place rather than reassigned: CreaturePerception._set_config hands the SAME
	# PerceptionConfig to hearing, vision, touch and geometry, so they are all already holding
	# this object. The prefab authors it as a SubResource, which every instantiation gets its
	# own copy of, so this cannot leak into a second creature.
	perception.config.hearing_max_range = CREATURE_HEARING_RANGE_M

	_director = EncounterDirector.new()
	_director.name = "EncounterDirector"
	_director.config = DirectorConfig.new()
	add_child(_director)

	var source := NavigationSource.new()
	source.name = "NavigationSource"
	source.config = navigation.config
	source.air_seeds = seeds
	add_child(source)
	# Colliders added or entered this frame are not queryable until the physics server has
	# stepped, and a bake before that fills the asteroid with nodes, rock included.
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.bake(_bake_region(seeds))
	await source.graph_baked
	# Two physics frames and a bake have passed since this started; the level can have been
	# torn down under it in that time, and everything below adds children.
	if not is_inside_tree() or _returning_to_menu:
		return

	navigation.source = source
	behavior.director = _director
	# Placed BEFORE it enters the tree: CreatureAgent remembers this pose in _ready() and a
	# reset puts it back here.
	crawler.transform = global_transform.affine_inverse() * creature_spawn.global_transform
	add_child(crawler)
	var nests := _reachable_nests(navigation, seeds)
	# A bake that produces an unusable graph does not error, and the creature then stands
	# there looking like a behaviour bug. One line so it cannot fail quietly.
	var stats: Dictionary = source.stats()
	print(
		(
			"[creature] %d nodes, %d edges | %d/%d nests reachable"
			% [stats["nodes"], stats["edges_normal"], nests.size(), seeds.size()]
		)
	)
	behavior.set_nest_positions(nests)
	behavior.attack_landed.connect(_on_attack_landed)
	_director.register(behavior, crawler.get_node("Suspicion") as CreatureSuspicion)

	var relay := PlayerNoiseRelay.new()
	relay.name = "PlayerNoiseRelay"
	relay.perception = perception
	add_child(relay)

	_build_creature_debug(crawler, behavior, navigation, perception)


## Every debug readout the level can supply, built once and toggled by DebugMode (F3).
##
## Built here rather than authored into the scene because all of it needs the creature or the
## Director, and neither exists until the bake above has finished. It runs last for two
## reasons: `add_child(crawler)` is what makes `navigation.graph` non-null, so the graph
## overlay has something to catch up on, and `_director.register` is what files the track the
## Director panel reads.
##
## SOLO ONLY, like the creature itself -- `_start_creature` is called from
## `_spawn_solo_player` and nowhere else, so in an online session there is no alien and F3
## does nothing here.
func _build_creature_debug(
	crawler: CrawlerBody,
	behavior: CreatureBehavior,
	navigation: CreatureNavigation,
	perception: CreaturePerception
) -> void:
	_graph_overlay = NavigationDebugDraw.new()
	_graph_overlay.name = "NavigationDebugDraw"
	# Assigned BEFORE add_child: the overlay connects `graph_baked` in its own `_ready()` and
	# catches up on the bake that already happened only if it has a navigator by then.
	_graph_overlay.navigation = navigation
	# One line per edge for a whole asteroid. `_apply_debug_mode` owns this from here, so
	# nothing is uploaded until the first F3.
	_graph_overlay.draw_graph = false
	add_child(_graph_overlay)

	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.name = "NavigationLocomotionDraw"
	_locomotion_overlay.navigation = navigation
	add_child(_locomotion_overlay)

	_trail_overlay = CreatureTrailDraw.new()
	_trail_overlay.name = "CreatureTrailDraw"
	_trail_overlay.body = crawler
	_trail_overlay.navigation = navigation
	_trail_overlay.marker = crawler.get_node("Marker") as Node3D
	# BehaviorConfig's arrival radius, pushed in because the navigation module does not name
	# the behaviour module.
	_trail_overlay.goal_radius = behavior.config.arrive_distance
	add_child(_trail_overlay)

	# What the alien BELIEVES, as opposed to what it just sensed: hotspot spheres warming from
	# blue to red, the evidence records under them, and the white spike over the place Behavior
	# is about to be sent. This is the overlay that shows a held mining beam becoming a lead.
	_suspicion_overlay = SuspicionDebugDraw.new()
	_suspicion_overlay.name = "SuspicionDebugDraw"
	_suspicion_overlay.suspicion = crawler.get_node("Suspicion") as CreatureSuspicion
	add_child(_suspicion_overlay)

	# The other half of the pair, and the two answer different questions. This one draws the
	# vision cone and the evidence the creature DID observe; it does not consume
	# `noise_evaluated` at all, so "the alien never heard me" is only legible on the panel
	# below. Exports assigned before add_child, because it connects in its own _ready().
	_perception_overlay = PerceptionDebugDraw.new()
	_perception_overlay.name = "PerceptionDebugDraw"
	_perception_overlay.perception = perception
	add_child(_perception_overlay)

	# The only per-placement wiring in the rig: the readout lives in the prefab and the trail
	# is level-space, so nothing in the scene could have connected them.
	var readout := crawler.get_node("DebugReadout") as CreatureDebugReadout
	readout.trail = _trail_overlay

	var layer := CanvasLayer.new()
	layer.name = "DebugOverlay"
	# Above the HUD, which sets no `layer` and is therefore on the default 1. Below the pause
	# menu's 20 and the loading screen's 25 -- a readout over the pause menu cannot be dismissed.
	layer.layer = 10
	add_child(layer)
	_build_creature_debug_panels(layer, behavior, navigation, perception)

	DebugMode.changed.connect(_apply_debug_mode)
	# Built long after the autoload settled on a value, so the first sync is explicit.
	_apply_debug_mode(DebugMode.enabled)


## One column bottom-left, which is the only corner the HUD does not already use.
##
## A VBoxContainer because the three panels are not the same base type -- NavigationDebugPanel
## extends Label where the other two extend PanelContainer -- and a box container sizes all
## three off their own minimums instead of anchoring each one by hand.
func _build_creature_debug_panels(
	layer: CanvasLayer,
	behavior: CreatureBehavior,
	navigation: CreatureNavigation,
	perception: CreaturePerception
) -> void:
	_debug_panels = VBoxContainer.new()
	_debug_panels.name = "DebugPanels"
	# Anchors, growth and position assigned before add_child, the same order every panel in
	# encounter_sandbox.gd uses.
	_debug_panels.anchor_top = 1.0
	_debug_panels.anchor_bottom = 1.0
	_debug_panels.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_debug_panels.position = Vector2(12.0, -12.0)
	_debug_panels.add_theme_constant_override("separation", 6)
	layer.add_child(_debug_panels)

	# Every @export assigned BEFORE add_child, all three: these panels connect their signals
	# in their own _ready(), and one wired afterwards renders every line except its log.
	_director_panel = DirectorDebugPanel.new()
	_director_panel.director = _director
	# The key the Director filed the track under. `_start_creature` registers `behavior`, not
	# the CrawlerBody, and `track_for` looks up by instance id -- pass the body here and the
	# panel reads "no creature registered" for the whole session.
	_director_panel.creature = behavior
	_director_panel.behavior = behavior
	_debug_panels.add_child(_director_panel)

	_behavior_panel = BehaviorDebugPanel.new()
	_behavior_panel.behavior = behavior
	_debug_panels.add_child(_behavior_panel)

	# The one readout that fires for a noise the creature FAILED to hear, printing NOT HEARD
	# rather than nothing at all. That is the difference between "the mining beam never reached
	# it" and "it heard the beam and did not care", and no overlay can show it -- Perception is
	# forbidden to remember, so `noise_evaluated` is the only place the miss exists.
	_perception_panel = PerceptionDebugPanel.new()
	_perception_panel.perception = perception
	_perception_panel.debug_draw = _perception_overlay
	_debug_panels.add_child(_perception_panel)

	# The odd one out gets a frame: NavigationDebugPanel is a bare Label, and a bare Label
	# over a lit cave wall is unreadable. One node here, against editing a script three
	# modules away.
	var nav_frame := PanelContainer.new()
	nav_frame.name = "NavigationFrame"
	_debug_panels.add_child(nav_frame)
	_navigation_panel = NavigationDebugPanel.new()
	_navigation_panel.navigation = navigation
	nav_frame.add_child(_navigation_panel)

	_make_click_through(_debug_panels)


## Show AND stop.
##
## Hiding a node does not stop its `_process`, and only DirectorDebugPanel checks `visible`
## before working: NavigationDebugPanel rebuilds its string every frame and BehaviorDebugPanel
## allocates a fresh EncounterReport every frame, while all three overlays redraw an
## ImmediateMesh unconditionally. Stopping them here is what lets the rig cost nothing when it
## is off without editing a single script under gameplay/*/debug/.
func _apply_debug_mode(enabled: bool) -> void:
	if _debug_panels == null:
		return
	_debug_panels.visible = enabled
	for node: Node3D in [
		_graph_overlay,
		_locomotion_overlay,
		_trail_overlay,
		_suspicion_overlay,
		_perception_overlay,
	]:
		node.visible = enabled
	# The static half of the graph overlay is rebuilt on demand rather than held: it is one
	# line per edge for the whole asteroid. This pair is what refresh_graph() exists for, and
	# it costs a visible hitch on the frame F3 is pressed.
	_graph_overlay.draw_graph = enabled
	_graph_overlay.refresh_graph()
	if enabled:
		_trail_overlay.clear_trail()
	for node: Node in [
		_graph_overlay,
		_locomotion_overlay,
		_trail_overlay,
		_suspicion_overlay,
		_perception_overlay,
		_director_panel,
		_behavior_panel,
		_navigation_panel,
		_perception_panel,
	]:
		node.set_process(enabled)


## The overlay must never eat a click. Container defaults to MOUSE_FILTER_PASS and Label to
## IGNORE, but the RichTextLabel both PanelContainer panels build in their own _ready() stops
## events -- and the left mouse button is `mine`.
static func _make_click_through(node: Node) -> void:
	var control := node as Control
	if control != null:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_click_through(child)


## The mine's own markers, minus the ones the creature cannot get to.
##
## They are authored for the level rather than for this body, and several sit mid-tunnel in
## strips narrower than the creature is. A nest it cannot reach is a nest it walks at forever.
func _reachable_nests(
	navigation: CreatureNavigation, seeds: PackedVector3Array
) -> PackedVector3Array:
	var from: Vector3 = creature_spawn.global_position
	var reachable := PackedVector3Array()
	for at: Vector3 in seeds:
		var route: NavRoute = navigation.plan_route(from, at)
		if route != null and route.status == NavRoute.Status.COMPLETE:
			reachable.append(at)
	if reachable.is_empty():
		push_error("No mine space is reachable from the creature spawn; it has nowhere to roam.")
	return reachable


func _bake_region(seeds: PackedVector3Array) -> AABB:
	var region := AABB(seeds[0], Vector3.ZERO)
	for at: Vector3 in seeds:
		region = region.expand(at)
	return region.grow(BAKE_MARGIN_M)


func _on_attack_landed(_target: Node, lethality: EncounterDirective.Lethality) -> void:
	if lethality == EncounterDirective.Lethality.LETHAL:
		reset()


## One lethal strike is a death: the creature, every player and the encounter pacing all go
## back to where the level started. Each of the three remembers its own starting state.
func reset() -> void:
	if _creature != null:
		_creature.reset()
	if _director != null:
		# Before note_respawn, which arms a stamp that reset() clears.
		_director.reset()
	for player: Node in players.get_children():
		var respawn := player.get_node_or_null("PlayerBody/Respawn") as PlayerRespawn
		if respawn == null:
			continue
		respawn.reset()
		if _director != null:
			_director.note_respawn(respawn.body)
	GlobalSignalBus.level_reset.emit()


func _spawn_network_player_if_missing(peer_id: int) -> void:
	if not multiplayer.is_server() or players.get_node_or_null(str(peer_id)) != null:
		return
	var spawn_transform := _spawn_transform_for(peer_id)
	var spawned := (
		player_spawner
		. spawn(
			{
				"peer_id": peer_id,
				"transform": spawn_transform,
			}
		)
	)
	if spawned != null:
		# MultiplayerSpawner.spawned is emitted only on receiving peers. Run the
		# same local-readiness hook explicitly for the authority's own instance.
		_on_player_spawned(spawned)


func _spawn_transform_for(peer_id: int) -> Transform3D:
	if peer_id == HOST_PEER_ID:
		return players.global_transform.affine_inverse() * player_spawn.global_transform

	var host_body := players.get_node_or_null("1/PlayerBody") as Node3D
	if host_body == null:
		return players.global_transform.affine_inverse() * player_spawn.global_transform
	var ahead := host_body.global_transform.translated_local(
		Vector3(0.0, 0.0, -PEER_SPAWN_AHEAD_METRES)
	)
	return players.global_transform.affine_inverse() * ahead.rotated_local(Vector3.UP, PI)


func _on_scene_peer_connected(peer_id: int) -> void:
	if OnlineSession.is_host() and peer_id == CLIENT_PEER_ID:
		_spawn_network_player_if_missing(CLIENT_PEER_ID)


func _on_player_spawned(player: Node) -> void:
	var driver := player.get_node_or_null("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	if driver == null or not driver.is_locally_controlled():
		return
	_prepare_local_player_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"cutscene_skip"):
		return
	if intro != null and intro.is_playing() and event.is_action_pressed(&"cutscene_skip"):
		intro.skip()
		get_viewport().set_input_as_handled()


func _on_entry_ready() -> void:
	_transport_ready = true
	if OnlineSession.mode() == OnlineSession.EntryMode.SOLO:
		_spawn_solo_player()
		# The solo player never goes through player_spawner.spawned, so the hook
		# that warms the local view has to be called for it explicitly.
		_prepare_local_player_presentation()
	elif OnlineSession.is_host():
		_prepare_host_player()
	elif _connection_screen != null:
		_connection_screen.set_status("Direct route ready; synchronizing suit", 0.8)
	_finish_connection_screen_if_ready()


func _prepare_host_player() -> void:
	if _host_spawn_scheduled:
		return
	_host_spawn_scheduled = true
	if _connection_screen != null:
		_connection_screen.set_status("Session live; preparing your suit", 0.7)
	await _present_connection_frame()
	if not is_inside_tree() or _returning_to_menu or not OnlineSession.is_host():
		return
	_spawn_network_player_if_missing(HOST_PEER_ID)


func _prepare_local_player_presentation() -> void:
	if _local_player_presentation_started:
		return
	_local_player_presentation_started = true
	if _connection_screen != null:
		_connection_screen.set_status("Warming survivor view", 0.9)
	await _present_connection_frame()
	if not is_inside_tree() or _returning_to_menu:
		return
	await _warm_local_player()
	if not is_inside_tree() or _returning_to_menu:
		return
	# BEFORE the loading screen comes down, not after. Frame 0 of the intro is a
	# full-screen opaque shot of the quota tube, so the screen is replaced by the
	# film rather than by a black gap.
	_start_intro()
	_local_player_ready = true
	_finish_connection_screen_if_ready()


## Parks the local player in the car and rolls the opening.
##
## THE LOCAL PLAYER'S ONLY. The cutscene is client-local: it takes this client's
## camera and input and nobody else's, and the door colliders it touches are
## idempotent. A second player joining mid-intro is untested - see the README.
func _start_intro() -> void:
	if _intro_played or not play_intro or intro == null:
		return
	var player := _local_player()
	if player == null:
		return
	_intro_played = true
	var rig := CutscenePlayerRig.for_player(player)
	if rig == null:
		return
	add_child(rig)
	intro.bind_player(rig, player.get_node_or_null("PlayerBody/UI/HudBinding"))
	intro.play()


func _local_player() -> Node:
	for player: Node in players.get_children():
		var driver := player.get_node_or_null("PlayerBody/NetworkDriver") as PlayerNetworkDriver
		if driver != null and not driver.is_locally_controlled():
			continue
		return player
	return null


## Draws the laser and the rope once behind the screen, so their first real use
## does not stop the game to compile shaders. Skipped if the prefab has no warm-up.
func _warm_local_player() -> void:
	var warmup := _local_player_warmup()
	if warmup == null:
		return
	await warmup.warm()


func _local_player_warmup() -> PlayerWarmup:
	for player: Node in players.get_children():
		var driver := player.get_node_or_null("PlayerBody/NetworkDriver") as PlayerNetworkDriver
		if driver != null and not driver.is_locally_controlled():
			continue
		return player.get_node_or_null("PlayerBody/Warmup") as PlayerWarmup
	return null


func _present_connection_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


func _on_entry_status_changed(description: String, progress: float) -> void:
	if _connection_screen != null:
		_connection_screen.set_status(description, progress)


func _on_entry_failed(description: String) -> void:
	_return_to_main_menu(description)


func _on_session_ended(description: String) -> void:
	_return_to_main_menu(description)


func _on_peer_left(peer_id: int) -> void:
	if not OnlineSession.is_host():
		return
	var departed_player := players.get_node_or_null(str(peer_id))
	if departed_player != null:
		departed_player.queue_free()


func _show_connection_screen() -> void:
	_connection_screen = SceneManager.loading_screen.instantiate() as LoadingScreen
	add_child(_connection_screen)
	if OnlineSession.is_online():
		_connection_screen.set_status("Preparing online descent", 0.05)
	else:
		_connection_screen.set_status("Preparing descent", 0.05)


func _finish_connection_screen_if_ready() -> void:
	if not _transport_ready or _connection_screen == null:
		return
	var local_peer_id := multiplayer.get_unique_id()
	if OnlineSession.is_online() and players.get_node_or_null(str(local_peer_id)) == null:
		return
	if not _local_player_ready:
		return
	_connection_screen.set_status("Descent ready", 1.0)
	_connection_screen.queue_free()
	_connection_screen = null


func _return_to_main_menu(description: String) -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	OnlineSession.leave(description)
	(
		SceneTransitionManager
		. change_scene_with_transition(
			SceneManager.main_menu,
			SceneManager.fade_transition,
		)
	)
