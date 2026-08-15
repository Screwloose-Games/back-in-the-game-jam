class_name AsteroidLevel
extends Node3D

## The playable asteroid. Spawns this machine's player at PlayerSpawn, and — from
## the pause menu's debug button — a stand-in for the peer who will later connect.

## Metres in front of the local player that a joining peer materialises.
const PEER_SPAWN_AHEAD_METRES := 2.5

const PLAYER_SCENE := preload("res://prefabs/character/player/prefab_player.tscn")

@onready var players: Node3D = %Players
@onready var player_spawn: Marker3D = %PlayerSpawn


func _ready() -> void:
	GlobalSignalBus.spawn_second_player_requested.connect(spawn_remote_player)
	spawn_local_player()
	GlobalSignalBus.level_started.emit()


func spawn_local_player() -> Node3D:
	return _spawn_peer("Player", player_spawn.global_transform, true)


## Stands a second character in front of the local player, turned to face them.
func spawn_remote_player() -> Node3D:
	var local := players.get_node_or_null("Player/PlayerBody") as Node3D
	if local == null:
		return _spawn_peer("Player2", player_spawn.global_transform, false)
	var ahead := local.global_transform.translated_local(
		Vector3(0.0, 0.0, -PEER_SPAWN_AHEAD_METRES)
	)
	return _spawn_peer("Player2", ahead.rotated_local(Vector3.UP, PI), false)


## The multiplayer seam: everything that differs between this machine's player and
## somebody else's is set here, before the prefab enters the tree. PlayerRespawn
## records the pose it arrives with, and PlayerUi reads is_local_player on ready.
func _spawn_peer(peer_name: String, pose: Transform3D, is_local: bool) -> Node3D:
	var player: Node3D = PLAYER_SCENE.instantiate()
	player.name = peer_name
	player.transform = players.global_transform.affine_inverse() * pose
	var body := player.get_node("PlayerBody")
	(body.get_node("Visibility") as PlayerVisibility).is_local_player = is_local
	var input := body.get_node("Input") as PlayerInput
	input.enabled = is_local
	input.captures_mouse = is_local
	# The prefab ships current = true; without this the second camera takes the
	# viewport the moment it enters the tree.
	(body.get_node("Head/HeadCamera") as Camera3D).current = is_local
	players.add_child(player)
	return player
