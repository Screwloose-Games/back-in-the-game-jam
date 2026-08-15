extends Node

## Headless wiring check for the additive network-player prefab.

const NetworkPlayerScene := preload("res://prefabs/character/player/prefab_network_player.tscn")

var _checks := 0
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := NetworkPlayerScene.instantiate() as Node3D
	player.name = "1"
	var driver := player.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	driver.configure(1, 1)
	add_child(player)
	await get_tree().process_frame

	var body := player.get_node("PlayerBody") as CharacterBody3D
	var input := body.get_node("Input") as PlayerInput
	var locomotion := body.get_node("Locomotion") as PlayerLocomotion
	var collision := body.get_node("CollisionResponse") as PlayerCollisionResponse
	var prediction := body.get_node("Prediction") as ClientPredictor3D
	var state_sync := body.get_node("StateSync") as MultiplayerSynchronizer

	_expect(driver.is_locally_controlled(), "peer 1 controls the peer-1 prefab")
	_expect(input.enabled, "the controlling peer polls input")
	_expect(not input.gameplay_actions_enabled, "unimplemented edge actions stay disabled")
	_expect(locomotion.externally_driven, "prediction owns locomotion stepping")
	_expect(collision.externally_driven, "prediction owns collision stepping")
	_expect(prediction.get_multiplayer_authority() == 1, "peer 1 owns authoritative state")
	_expect(state_sync.root_path == NodePath("../Prediction"), "state sync targets prediction")

	var remote_player := NetworkPlayerScene.instantiate() as Node3D
	remote_player.name = "2"
	var remote_driver := remote_player.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	remote_driver.configure(2, 1)
	add_child(remote_player)
	await get_tree().process_frame

	var remote_body := remote_player.get_node("PlayerBody") as CharacterBody3D
	var remote_input := remote_body.get_node("Input") as PlayerInput
	var remote_visibility := remote_body.get_node("Visibility") as PlayerVisibility
	var remote_prediction := remote_body.get_node("Prediction") as ClientPredictor3D
	_expect(not remote_driver.is_locally_controlled(), "peer 1 does not control the peer-2 prefab")
	_expect(not remote_input.enabled, "a remote copy does not poll this machine's input")
	_expect(not remote_visibility.is_local_player, "a remote copy renders as another survivor")
	_expect(remote_input.get_multiplayer_authority() == 2, "peer 2 owns only its input subtree")
	_expect(remote_prediction.get_multiplayer_authority() == 1, "peer 1 retains movement authority")

	player.queue_free()
	remote_player.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("PASS [network-player-scene] %d checks" % _checks)
	else:
		print("FAIL [network-player-scene] %d of %d checks failed" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [network-player-scene] %s" % description)
