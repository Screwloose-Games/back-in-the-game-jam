class_name MultiplayerChasePlayer
extends CharacterBody3D

## Host-authoritative zero-g survivor for the crawler demo.
##
## The controlling peer predicts bounded movement commands immediately. Peer 1
## applies those commands once, owns collision outcomes, and publishes
## authoritative snapshots through ClientPredictor3D.

var controlled_peer_id := WebRTCSession.HOST_PEER_ID

@onready var _presentation: Node3D = $Presentation
@onready var _body_mesh: MeshInstance3D = $Presentation/BodyMesh
@onready var _camera: Camera3D = $Presentation/HeadCamera
@onready var _helmet_lamp: SpotLight3D = $Presentation/HeadCamera/HelmetLamp
@onready var _inputs: MultiplayerChaseInput = $Inputs
@onready var _nameplate: Label3D = $Presentation/Nameplate
@onready var _prediction: ClientPredictor3D = $Prediction


func configure(peer_id: int, spawn_transform: Transform3D) -> void:
	controlled_peer_id = peer_id
	name = str(peer_id)
	transform = spawn_transform
	# This must happen before MultiplayerSpawner inserts the node into the tree.
	# Changing synchronizer authority from _ready is too late in Godot 4.7.
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
	_body_mesh.visible = not is_local
	_nameplate.visible = not is_local
	_nameplate.text = "HOST" if controlled_peer_id == WebRTCSession.HOST_PEER_ID else "SURVIVOR-02"
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


func activate_local_camera() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_camera.make_current()


func capture_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.capture_mouse()


func release_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.release_mouse()


func is_ready_for_chase() -> bool:
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
			MultiplayerChaseKnobs.PLAYER_MAX_TURN_RATE * delta / angle,
			1.0,
		)
	global_transform.basis = Basis(current_rotation.slerp(requested_rotation, turn_weight))

	velocity += (
		global_transform.basis * thrust.limit_length(1.0) * CarryKnobs.THRUST_ACCELERATION * delta
	)
	if bool(flags & ClientPredictor3D.FLAG_STABILIZING):
		velocity = (
			velocity
			. lerp(
				Vector3.ZERO,
				minf(CarryKnobs.LINEAR_STABILIZER_RATE * delta, 1.0),
			)
		)
	velocity = velocity.limit_length(CarryKnobs.MAX_SPEED)
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
