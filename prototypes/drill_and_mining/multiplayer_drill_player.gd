class_name MultiplayerDrillPlayer
extends CharacterBody3D

## Host-authoritative zero-g miner with client-predicted movement.
##
## The player carries input intent and presentation only. The multiplayer world
## owns ray validation, ore mutation, carve replication, debris, and crystal
## outcomes so those rules cannot accidentally run once on every peer.

var controlled_peer_id := WebRTCSession.HOST_PEER_ID

@onready var _presentation: Node3D = $Presentation
@onready var _body_mesh: MeshInstance3D = $Presentation/BodyMesh
@onready var _camera: Camera3D = $Presentation/HeadCamera
@onready var _helmet_lamp: SpotLight3D = $Presentation/HeadCamera/HelmetLamp
@onready var _drill_tool: MultiplayerDrillTool = $Presentation/HeadCamera/DrillTool
@onready var _nameplate: Label3D = $Presentation/Nameplate
@onready var _inputs: MultiplayerDrillInput = $Inputs
@onready var _prediction: ClientPredictor3D = $Prediction


func configure(peer_id: int, spawn_transform: Transform3D) -> void:
	controlled_peer_id = peer_id
	name = str(peer_id)
	transform = spawn_transform
	# These assignments must happen before MultiplayerSpawner inserts this node.
	# The body, prediction, and state synchronizer always remain host-owned.
	set_multiplayer_authority(WebRTCSession.HOST_PEER_ID, true)
	get_node("Inputs").set_multiplayer_authority(controlled_peer_id, true)
	var presentation := get_node("Presentation") as Node3D
	var prediction := get_node("Prediction") as ClientPredictor3D
	(
		prediction
		. configure(
			controlled_peer_id,
			presentation,
			Callable(self, "_simulate_network_command"),
			false,
		)
	)


func _ready() -> void:
	var is_local := multiplayer.get_unique_id() == controlled_peer_id
	_camera.current = false
	_camera.far = DrillKnobs.CAMERA_FAR
	_helmet_lamp.spot_range = DrillKnobs.HELMET_LAMP_RANGE
	_helmet_lamp.spot_angle = DrillKnobs.HELMET_LAMP_ANGLE
	_helmet_lamp.light_energy = DrillKnobs.HELMET_LAMP_ENERGY
	_body_mesh.visible = not is_local
	_nameplate.visible = not is_local
	_nameplate.text = "HOST" if controlled_peer_id == WebRTCSession.HOST_PEER_ID else "MINER-02"
	_apply_player_color()
	if OS.has_feature("web"):
		_helmet_lamp.shadow_enabled = false

	if is_local:
		_inputs.begin_local_control(global_transform.basis)
	_prediction.authoritative_reset_received.connect(_on_authoritative_reset_received)


func _physics_process(delta: float) -> void:
	_inputs.update_from_local(delta)
	var flags := 0
	if _inputs.stabilizing:
		flags |= ClientPredictor3D.FLAG_STABILIZING
	if _inputs.drilling:
		flags |= ClientPredictor3D.FLAG_PRIMARY_ACTION
	_prediction.physics_step(delta, _inputs.thrust, _inputs.look_orientation, flags)


func set_authoritative_active(active: bool) -> void:
	if not multiplayer.is_server():
		return
	if not active and _prediction.simulation_active:
		velocity = Vector3.ZERO
	_prediction.set_authoritative_active(active)


func reset_authoritative_state(spawn_transform: Transform3D, active: bool) -> void:
	if not multiplayer.is_server():
		return
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.reset_local_orientation(spawn_transform.basis)
	_prediction.authoritative_reset(active)


func get_authoritative_drill_active() -> bool:
	return (
		multiplayer.is_server()
		and bool(_prediction.get_authoritative_flags() & ClientPredictor3D.FLAG_PRIMARY_ACTION)
	)


func is_local_drill_active() -> bool:
	return multiplayer.get_unique_id() == controlled_peer_id and _inputs.drilling


func get_drill_origin() -> Vector3:
	return _camera.global_position


func get_drill_direction() -> Vector3:
	return -_camera.global_transform.basis.z.normalized()


func show_drill_preview(endpoint: Vector3, has_hit: bool, active: bool) -> void:
	_drill_tool.show_preview(endpoint, has_hit, active)


func pulse_remote_drill(endpoint: Vector3) -> void:
	_drill_tool.pulse(endpoint)


func activate_local_camera() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_camera.make_current()


func capture_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.capture_mouse()


func release_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.release_mouse()


func is_ready_for_mining() -> bool:
	return _inputs.ready_to_play


func _simulate_network_command(
	thrust: Vector3,
	look: Quaternion,
	flags: int,
	delta: float,
	_context: int,
) -> void:
	var requested_rotation := look.normalized()
	var current_rotation := global_transform.basis.get_rotation_quaternion().normalized()
	var angle := current_rotation.angle_to(requested_rotation)
	var turn_weight: float = 1.0
	if angle > 0.0001:
		turn_weight = minf(
			DrillMovementKnobs.MAX_ANGULAR_SPEED * delta / angle,
			1.0,
		)
	global_transform.basis = Basis(current_rotation.slerp(requested_rotation, turn_weight))

	velocity += (
		global_transform.basis
		* thrust.limit_length(1.0)
		* DrillMovementKnobs.THRUST_ACCELERATION
		* delta
	)
	if bool(flags & ClientPredictor3D.FLAG_STABILIZING):
		velocity = (
			velocity
			. lerp(
				Vector3.ZERO,
				minf(DrillMovementKnobs.LINEAR_STABILIZER_RATE * delta, 1.0),
			)
		)
	velocity = velocity.limit_length(DrillMovementKnobs.MAX_SPEED)
	move_and_slide()


func _on_authoritative_reset_received(body_transform: Transform3D) -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.reset_local_orientation(body_transform.basis)


func _apply_player_color() -> void:
	var material := _body_mesh.material_override as StandardMaterial3D
	if material == null:
		return
	if controlled_peer_id == WebRTCSession.HOST_PEER_ID:
		material.albedo_color = Color(0.35, 0.95, 0.68)
		material.emission = Color(0.08, 0.35, 0.2)
	else:
		material.albedo_color = Color(0.42, 0.68, 1.0)
		material.emission = Color(0.08, 0.18, 0.42)
