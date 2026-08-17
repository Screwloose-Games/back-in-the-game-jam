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

var _connection_screen: LoadingScreen
var _transport_ready := false
var _returning_to_menu := false
var _host_spawn_scheduled := false
var _local_player_presentation_started := false
var _local_player_ready := false
var _creature: CreatureAgent
var _director: EncounterDirector

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
	relay.perception = crawler.get_node("Perception") as CreaturePerception
	add_child(relay)


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
	_local_player_ready = true
	_finish_connection_screen_if_ready()


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
