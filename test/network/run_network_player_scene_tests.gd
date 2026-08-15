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
	var presentation_sync := body.get_node("PresentationSync") as MultiplayerSynchronizer
	var mining_tool := body.get_node("MiningTool") as PlayerMiningTool
	var lamp := body.get_node("Lamp") as PlayerLamp

	_expect(driver.is_locally_controlled(), "peer 1 controls the peer-1 prefab")
	_expect(input.enabled, "the controlling peer polls input")
	_expect(input.gameplay_actions_enabled, "the controlling peer raises its edge actions")
	_expect(locomotion.externally_driven, "prediction owns locomotion stepping")
	_expect(collision.externally_driven, "prediction owns collision stepping")
	_expect(prediction.get_multiplayer_authority() == 1, "peer 1 owns authoritative state")
	_expect(state_sync.root_path == NodePath("../Prediction"), "state sync targets prediction")
	_expect(
		presentation_sync.root_path == NodePath("../NetworkDriver"),
		"presentation sync targets the driver",
	)

	# The regression this suite exists for: every one of these was switched off
	# wholesale, which killed the mining beam and the lamp for the host as well.
	for component_name in [
		"Grab", "Tether", "Hands", "PowerClient", "Oxygen", "Lamp", "MiningTool"
	]:
		var component := body.get_node(NodePath(component_name))
		_expect(
			component.process_mode != Node.PROCESS_MODE_DISABLED,
			"peer 1 runs its own %s" % component_name,
		)

	_expect(not mining_tool.presentation_only, "peer 1 owns its own mining effects")
	_expect(not mining_tool.externally_driven, "peer 1 reads its own held fire")
	# Stop the device poll first, exactly as the driver does before republishing a
	# remote peer's accepted intent; otherwise this frame's sample overwrites it.
	input.enabled = false
	input.mine_held = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(mining_tool.is_firing(), "held fire reaches the mining tool")
	input.mine_held = false
	input.enabled = true

	var lit_before := lamp.is_switched_on()
	input.lamp_toggled.emit()
	_expect(lamp.is_switched_on() != lit_before, "the lamp answers its edge action")

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
	_expect(not remote_input.gameplay_actions_enabled, "a remote copy raises no edge actions")

	# Peer 1 hosts here, so its copy of peer 2 is still the authoritative one: it
	# reads that peer's intent from the command stream rather than from a device.
	var remote_mining := remote_body.get_node("MiningTool") as PlayerMiningTool
	_expect(not remote_mining.presentation_only, "peer 1 owns peer 2's mining effects")
	_expect(not remote_mining.externally_driven, "peer 1 republishes peer 2's held fire")
	_expect(
		remote_body.get_node("Grab").process_mode != Node.PROCESS_MODE_DISABLED,
		"peer 1 runs peer 2's shared-object components",
	)

	await _check_client_configuration()

	player.queue_free()
	remote_player.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("PASS [network-player-scene] %d checks" % _checks)
	else:
		print("FAIL [network-player-scene] %d of %d checks failed" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


## The half a single-machine run cannot reach otherwise: on a joining peer no
## copy is authoritative, so both draw the beam and the lamp without owning them.
func _check_client_configuration() -> void:
	var own := NetworkPlayerScene.instantiate() as Node3D
	own.name = "own"
	(own.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver).configure(2, 2)
	add_child(own)

	var host_copy := NetworkPlayerScene.instantiate() as Node3D
	host_copy.name = "host_copy"
	(host_copy.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver).configure(1, 2)
	add_child(host_copy)
	await get_tree().process_frame

	var own_body := own.get_node("PlayerBody")
	var own_mining := own_body.get_node("MiningTool") as PlayerMiningTool
	_expect(own_mining.presentation_only, "a client owns none of its own mining effects")
	_expect(not own_mining.externally_driven, "a client predicts its own beam from its device")
	_expect(
		(own_body.get_node("Lamp") as PlayerLamp).presentation_only, "a client pays for no lamp"
	)
	_expect(
		(own_body.get_node("PowerClient") as PlayerPowerClient).externally_driven,
		"a client adopts the charge peer 1 publishes",
	)
	_expect(
		own_body.get_node("Grab").process_mode == Node.PROCESS_MODE_DISABLED,
		"a client runs no shared-object components",
	)

	var host_mining := host_copy.get_node("PlayerBody/MiningTool") as PlayerMiningTool
	_expect(host_mining.externally_driven, "a client draws peer 1's beam from replicated state")
	_expect(host_mining.presentation_only, "a client applies none of peer 1's mining effects")

	own.queue_free()
	host_copy.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [network-player-scene] %s" % description)
