extends Node3D

## A lit box room with one of each hazard and a real player, for tuning them by feel.
##
## Not registered in SceneManager and not reachable from the menu -- name it on the
## command line:
##
##     godot --path . res://levels/hazard_sandbox/hazard_sandbox.tscn
##
## There is no creature here, so nothing connects the hazards' world_noise; that wire
## belongs to AsteroidLevel, which is the only place that has a CreaturePerception.

const PLAYER_SCENE := preload("res://prefabs/character/player/prefab_player.tscn")

@onready var players: Node3D = %Players
@onready var player_spawn: Marker3D = %PlayerSpawn


func _ready() -> void:
	GlobalSignalBus.level_started.emit()
	_spawn_player()


## The presentation lines AsteroidLevel._spawn_solo_player() does and a bare prefab
## instance is missing: nothing else claims the camera or turns the controls on.
func _spawn_player() -> void:
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
