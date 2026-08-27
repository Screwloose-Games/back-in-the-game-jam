extends Node

## Headless ownership and gameplay-state checks for the additive network player.

const NetworkPlayerScene := preload("res://prefabs/character/player/prefab_network_player.tscn")
const HOST_PEER_ID := 1
const CLIENT_PEER_ID := 2
const AUTHORITY_COMPONENTS: Array[StringName] = [
	&"PowerClient",
	&"Oxygen",
	&"Lamp",
	&"MiningTool",
	&"NoiseEmitter",
	&"Respawn",
]
const NETWORK_DRIVEN_COMPONENTS: Array[StringName] = [
	&"Grab",
	&"Interactor",
	&"Tether",
	&"PowerClient",
	&"Oxygen",
	&"Lamp",
	&"MiningTool",
	&"NoiseEmitter",
	&"Respawn",
]
const RESERVED_SHARED_COMPONENTS: Array[StringName] = [&"Grab", &"Interactor", &"Tether"]
const GAMEPLAY_STATE_PATHS: Array[NodePath] = [
	NodePath(".:gameplay_lamp_requested"),
	NodePath(".:gameplay_mining_active"),
	NodePath(".:gameplay_mining_endpoint"),
	NodePath(".:gameplay_power_fraction"),
	NodePath(".:gameplay_oxygen_fraction"),
	NodePath(".:gameplay_action_ack"),
	NodePath(".:gameplay_state_sequence"),
]

var _checks := 0
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := NetworkPlayerScene.instantiate() as Node3D
	player.name = str(HOST_PEER_ID)
	var driver := player.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	driver.configure(HOST_PEER_ID, HOST_PEER_ID)
	add_child(player)
	await get_tree().process_frame

	var body := player.get_node("PlayerBody") as CharacterBody3D
	var input := body.get_node("Input") as PlayerInput
	var locomotion := body.get_node("Locomotion") as PlayerLocomotion
	var collision := body.get_node("CollisionResponse") as PlayerCollisionResponse
	var prediction := body.get_node("Prediction") as ClientPredictor3D
	var state_sync := body.get_node("StateSync") as MultiplayerSynchronizer
	var gameplay := body.get_node("NetworkGameplay") as PlayerNetworkGameplay
	var lamp := body.get_node("Lamp") as PlayerLamp
	var mining_tool := body.get_node("MiningTool") as PlayerMiningTool
	var power := body.get_node("PowerClient") as PlayerPowerClient
	var oxygen := body.get_node("Oxygen") as PlayerOxygen
	var respawn := body.get_node("Respawn") as PlayerRespawn

	_expect(driver.is_locally_controlled(), "peer 1 controls the peer-1 prefab")
	_expect(input.enabled, "the controlling peer polls input")
	_expect(input.gameplay_actions_enabled, "the controlling peer publishes gameplay actions")
	_expect(
		locomotion.externally_driven and collision.externally_driven,
		"prediction owns movement component stepping",
	)
	_expect(prediction.get_multiplayer_authority() == HOST_PEER_ID, "peer 1 owns movement state")
	_expect(state_sync.root_path == NodePath("../Prediction"), "state sync targets prediction")
	_expect_gameplay_sync(body)
	_expect_component_policy(body, true, "host-local player")
	_expect(
		body.collision_layer == 2 and body.collision_mask == 1,
		"the host player occupies the authority layer and collides only with the hull",
	)
	_test_local_action_routing(input, lamp, respawn, body)
	await _test_host_mining(input, mining_tool, power)
	_test_resource_apis(power, oxygen)

	var host_remote := NetworkPlayerScene.instantiate() as Node3D
	host_remote.name = str(CLIENT_PEER_ID)
	var host_remote_driver := (
		host_remote.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	)
	host_remote_driver.configure(CLIENT_PEER_ID, HOST_PEER_ID)
	add_child(host_remote)
	await get_tree().process_frame

	var host_remote_body := host_remote.get_node("PlayerBody") as CharacterBody3D
	var host_remote_input := host_remote_body.get_node("Input") as PlayerInput
	var host_remote_visibility := host_remote_body.get_node("Visibility") as PlayerVisibility
	var host_remote_prediction := host_remote_body.get_node("Prediction") as ClientPredictor3D
	var host_remote_gameplay := (
		host_remote_body.get_node("NetworkGameplay") as PlayerNetworkGameplay
	)
	_expect(
		not host_remote_driver.is_locally_controlled(), "the host does not poll peer 2 controls"
	)
	_expect(
		not host_remote_input.enabled and not host_remote_input.gameplay_actions_enabled,
		"the host copy of peer 2 suppresses local input",
	)
	_expect(not host_remote_visibility.is_local_player, "the host copy renders as another survivor")
	_expect(
		(
			host_remote_input.get_multiplayer_authority() == CLIENT_PEER_ID
			and host_remote_prediction.get_multiplayer_authority() == HOST_PEER_ID
		),
		"peer 2 owns input while the host owns movement state",
	)
	_expect_component_policy(host_remote_body, true, "host authority for peer 2")
	_expect(
		host_remote_body.collision_layer == 2 and host_remote_body.collision_mask == 1,
		"the host authority for peer 2 collides only with the hull",
	)
	_test_protocol_guards(host_remote_gameplay, host_remote_prediction)

	# configure() accepts the local peer explicitly, so replica safety can be
	# checked under the default offline peer without WebRTC or signaling.
	var client_local := NetworkPlayerScene.instantiate() as Node3D
	var client_local_driver := (
		client_local.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	)
	client_local_driver.configure(CLIENT_PEER_ID, CLIENT_PEER_ID)
	client_local_driver.set_physics_process(false)
	client_local.name = "ClientLocalFixture"
	add_child(client_local)
	await get_tree().process_frame

	var client_local_body := client_local.get_node("PlayerBody") as CharacterBody3D
	var client_local_input := client_local_body.get_node("Input") as PlayerInput
	var client_local_gameplay := (
		client_local_body.get_node("NetworkGameplay") as PlayerNetworkGameplay
	)
	_expect(
		client_local_input.enabled and client_local_input.gameplay_actions_enabled,
		"a joining client polls and publishes its own gameplay input",
	)
	_expect_component_policy(client_local_body, false, "joining client's local player")
	_expect(
		client_local_body.collision_layer == 0 and client_local_body.collision_mask == 1,
		"local prediction is nonauthoritative and collides only with the hull",
	)
	_test_client_local_prediction(client_local_body, client_local_gameplay, client_local_input)
	client_local.queue_free()

	var client_remote := NetworkPlayerScene.instantiate() as Node3D
	var client_remote_driver := (
		client_remote.get_node("PlayerBody/NetworkDriver") as PlayerNetworkDriver
	)
	client_remote_driver.configure(HOST_PEER_ID, CLIENT_PEER_ID)
	client_remote_driver.set_physics_process(false)
	client_remote.name = "ClientRemoteFixture"
	add_child(client_remote)
	await get_tree().process_frame

	var client_remote_body := client_remote.get_node("PlayerBody") as CharacterBody3D
	var client_remote_input := client_remote_body.get_node("Input") as PlayerInput
	var client_remote_gameplay := (
		client_remote_body.get_node("NetworkGameplay") as PlayerNetworkGameplay
	)
	_expect(
		not client_remote_input.enabled and not client_remote_input.gameplay_actions_enabled,
		"a client replica suppresses another peer's input",
	)
	_expect(
		client_remote_body.collision_layer == 0 and client_remote_body.collision_mask == 0,
		"an interpolated replica cannot create collisions",
	)
	_expect_action_suppressed(client_remote_input)
	_test_replica_state_apis(client_remote_body, client_remote_gameplay)
	client_remote.queue_free()

	player.queue_free()
	host_remote.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("PASS [network-player-scene] %d checks" % _checks)
	else:
		print("FAIL [network-player-scene] %d of %d checks failed" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_local_action_routing(
	input: PlayerInput,
	lamp: PlayerLamp,
	respawn: PlayerRespawn,
	body: CharacterBody3D,
) -> void:
	var was_requested := lamp.requested_lit()
	input._input(_action_event(&"toggle_lamp"))
	_expect(
		lamp.requested_lit() != was_requested,
		"host-local lamp input reaches authoritative gameplay",
	)

	var spawn_transform := respawn.spawn_transform()
	body.global_position += Vector3(4.0, -2.0, 3.0)
	input._input(_action_event(&"reset_player"))
	_expect(
		body.global_transform.is_equal_approx(spawn_transform),
		"host-local reset reaches respawn and restores the authoritative pose",
	)


func _test_host_mining(
	input: PlayerInput,
	mining_tool: PlayerMiningTool,
	power: PlayerPowerClient,
) -> void:
	var charge_before := power.charge
	Input.action_press(&"mine")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(input.mine_held, "local held mining input is sampled")
	_expect(
		mining_tool.is_firing() and power.charge < charge_before,
		"host-authoritative mining starts and spends suit power",
	)
	Input.action_release(&"mine")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(not mining_tool.is_firing(), "releasing mining input stops the authoritative tool")


func _test_resource_apis(power: PlayerPowerClient, oxygen: PlayerOxygen) -> void:
	var power_before := power.charge
	var spent := power.spend(1.0)
	var stored := power.store(spent)
	_expect(
		(
			is_equal_approx(spent, 1.0)
			and is_equal_approx(stored, spent)
			and is_equal_approx(power.charge, power_before)
		),
		"authoritative power spend/store reports amounts and round-trips",
	)

	var oxygen_before := oxygen.fraction()
	oxygen.refill(1.0)
	_expect(oxygen.fraction() >= oxygen_before, "authoritative oxygen refill is monotonic")


func _test_protocol_guards(gameplay: PlayerNetworkGameplay, prediction: ClientPredictor3D) -> void:
	var lamp_action := PlayerNetworkGameplay.Action.LAMP_SET
	_expect(
		gameplay._accepts_action_request(CLIENT_PEER_ID, 1, lamp_action),
		"action guard accepts a fresh valid request from the controlled peer",
	)
	_expect(
		(
			not gameplay._accepts_action_request(HOST_PEER_ID, 1, lamp_action)
			and not gameplay._accepts_action_request(CLIENT_PEER_ID, 0, lamp_action)
			and not gameplay._accepts_action_request(CLIENT_PEER_ID, 1, 2)
		),
		"action guard rejects host senders, stale sequences, and invalid actions",
	)

	var current_epoch := prediction.authoritative_epoch
	_expect(
		gameplay._accepts_mining_intent(CLIENT_PEER_ID, current_epoch, 1),
		"mining guard accepts fresh intent from the controlled peer in the current epoch",
	)
	_expect(
		(
			not gameplay._accepts_mining_intent(HOST_PEER_ID, current_epoch, 1)
			and not gameplay._accepts_mining_intent(CLIENT_PEER_ID, current_epoch - 1, 1)
			and not gameplay._accepts_mining_intent(CLIENT_PEER_ID, current_epoch, 0)
		),
		"mining guard rejects host senders, stale epochs, and stale sequences",
	)


func _test_client_local_prediction(
	body: CharacterBody3D,
	gameplay: PlayerNetworkGameplay,
	input: PlayerInput,
) -> void:
	var lamp := body.get_node("Lamp") as PlayerLamp
	var mining_tool := body.get_node("MiningTool") as PlayerMiningTool
	var power := body.get_node("PowerClient") as PlayerPowerClient
	var gameplay_sync := body.get_node("GameplaySync") as MultiplayerSynchronizer

	var initial_lamp_requested := lamp.requested_lit()
	input._input(_action_event(&"toggle_lamp"))
	_expect(
		lamp.requested_lit() != initial_lamp_requested,
		"client-local lamp switches immediately before host acknowledgement",
	)

	# An older host snapshot can arrive while the reliable request is in flight.
	gameplay.gameplay_lamp_requested = initial_lamp_requested
	gameplay.gameplay_action_ack = 0
	gameplay_sync.synchronized.emit()
	_expect(
		lamp.requested_lit() != initial_lamp_requested,
		"pre-ack lamp state preserves the optimistic local switch",
	)

	gameplay.gameplay_action_ack = 1
	gameplay_sync.synchronized.emit()
	_expect(
		lamp.requested_lit() == initial_lamp_requested,
		"acknowledged lamp state reconciles to authority",
	)

	gameplay.gameplay_power_fraction = 0.75
	gameplay_sync.synchronized.emit()
	var charge_before_preview := power.charge
	input.mine_held = true
	gameplay.call("_step_local_gameplay")
	_expect(
		mining_tool.is_firing() and power.charge == charge_before_preview,
		"client-local mining previews immediately without spending replica power",
	)
	input.mine_held = false
	gameplay.call("_step_local_gameplay")
	_expect(not mining_tool.is_firing(), "releasing client input stops the mining preview")


func _test_replica_state_apis(body: CharacterBody3D, gameplay: PlayerNetworkGameplay) -> void:
	var lamp := body.get_node("Lamp") as PlayerLamp
	var mining_tool := body.get_node("MiningTool") as PlayerMiningTool
	var power := body.get_node("PowerClient") as PlayerPowerClient
	var oxygen := body.get_node("Oxygen") as PlayerOxygen
	var gameplay_sync := body.get_node("GameplaySync") as MultiplayerSynchronizer

	gameplay.gameplay_lamp_requested = true
	gameplay.gameplay_mining_active = true
	gameplay.gameplay_mining_endpoint = Vector3(3.0, -2.0, 7.0)
	gameplay.gameplay_power_fraction = 0.25
	gameplay.gameplay_oxygen_fraction = 0.5
	gameplay_sync.synchronized.emit()
	_expect(
		lamp.requested_lit() and lamp.lamp.visible,
		"a powered replica applies the authoritative lamp request and presentation",
	)
	_expect(
		is_equal_approx(power.fraction(), 0.25) and is_equal_approx(oxygen.fraction(), 0.5),
		"GameplaySync applies replica resource fractions",
	)
	_expect(
		(
			mining_tool.is_firing()
			and mining_tool.beam_endpoint().is_equal_approx(gameplay.gameplay_mining_endpoint)
		),
		"a replica applies authoritative mining presentation",
	)

	gameplay.gameplay_power_fraction = 0.0
	gameplay.gameplay_mining_active = false
	gameplay_sync.synchronized.emit()
	_expect(
		lamp.requested_lit() and not lamp.lamp.visible,
		"zero replica power suppresses effective light without losing its request",
	)
	_expect(not mining_tool.is_firing(), "a replica can stop mining presentation")

	power.apply_network_fraction(INF)
	oxygen.apply_network_fraction(-1.0)
	_expect(
		is_zero_approx(power.fraction()) and is_zero_approx(oxygen.fraction()),
		"invalid replica resource fractions fail closed",
	)


func _expect_component_policy(
	body: CharacterBody3D, authority_enabled: bool, context: String
) -> void:
	var not_network_driven: Array[StringName] = []
	for component_name in NETWORK_DRIVEN_COMPONENTS:
		var component := body.get_node(NodePath(component_name))
		if not bool(component.get("externally_driven")):
			not_network_driven.append(component_name)
	_expect(
		not_network_driven.is_empty(),
		"%s components are externally driven (%s)" % [context, not_network_driven],
	)

	var wrong_authority_mode: Array[StringName] = []
	for component_name in AUTHORITY_COMPONENTS:
		var component := body.get_node(NodePath(component_name))
		var is_enabled := component.process_mode != Node.PROCESS_MODE_DISABLED
		if is_enabled != authority_enabled:
			wrong_authority_mode.append(component_name)
	_expect(
		wrong_authority_mode.is_empty(),
		"%s authority processing matches ownership (%s)" % [context, wrong_authority_mode],
	)

	var enabled_reserved_components: Array[StringName] = []
	for component_name in RESERVED_SHARED_COMPONENTS:
		var component := body.get_node(NodePath(component_name))
		if component.process_mode != Node.PROCESS_MODE_DISABLED:
			enabled_reserved_components.append(component_name)
	_expect(
		enabled_reserved_components.is_empty(),
		"%s shared-object actions remain disabled (%s)" % [context, enabled_reserved_components],
	)


func _expect_gameplay_sync(body: CharacterBody3D) -> void:
	var gameplay_sync := body.get_node_or_null("GameplaySync") as MultiplayerSynchronizer
	_expect(
		gameplay_sync != null and gameplay_sync.root_path == NodePath("../NetworkGameplay"),
		"gameplay sync targets the game-specific network state",
	)
	var configured_paths := (
		gameplay_sync.replication_config.get_properties()
		if gameplay_sync != null and gameplay_sync.replication_config != null
		else []
	)
	var missing_paths: Array[NodePath] = []
	for property_path in GAMEPLAY_STATE_PATHS:
		if property_path not in configured_paths:
			missing_paths.append(property_path)
	_expect(
		missing_paths.is_empty(),
		"gameplay sync publishes the complete personal-state snapshot (%s)" % [missing_paths],
	)


func _expect_action_suppressed(input: PlayerInput) -> void:
	var events := [0]
	input.lamp_toggled.connect(func() -> void: events[0] += 1)
	input._input(_action_event(&"toggle_lamp"))
	_expect(events[0] == 0, "a remote replica cannot emit local gameplay actions")


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [network-player-scene] %s" % description)
