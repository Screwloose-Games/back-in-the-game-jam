class_name MultiplayerPowerPlayer
extends CharacterBody3D

## Host-authoritative zero-g player used by the integrated multiplayer demo.
##
## The controlling peer predicts bounded movement commands immediately. Peer 1
## applies those commands once, owns collision/tether outcomes, and publishes
## authoritative snapshots through ClientPredictor3D.

const TETHER_LENGTH := MovementKnobs.TETHER_LENGTH
const TETHER_PLAYER_ACCELERATION := 5.0
const TETHER_CUBE_FORCE := 900.0
const MAX_TETHER_STRETCH := 4.0
const CRANK_DISTANCE := 3.0
const MAX_TURN_RATE := 8.0

var controlled_peer_id := WebRTCSession.HOST_PEER_ID
var _cube: MultiplayerPowerCube

@onready var _presentation: Node3D = $Presentation
@onready var _body_mesh: MeshInstance3D = $Presentation/BodyMesh
@onready var _camera: Camera3D = $Presentation/HeadCamera
@onready var _helmet_lamp: SpotLight3D = $Presentation/HeadCamera/HelmetLamp
@onready var _nameplate: Label3D = $Presentation/Nameplate
@onready var _tether: MeshInstance3D = $Tether
@onready var _inputs: MultiplayerInputState = $Inputs
@onready var _prediction: ClientPredictor3D = $Prediction


func configure(peer_id: int, spawn_transform: Transform3D) -> void:
	controlled_peer_id = peer_id
	name = str(peer_id)
	transform = spawn_transform
	set_multiplayer_authority(WebRTCSession.HOST_PEER_ID, true)
	# Input capture follows the player, but Prediction and StateSync deliberately
	# retain host authority. Both assignments happen before spawner insertion.
	get_node("Inputs").set_multiplayer_authority(controlled_peer_id, true)
	var presentation := get_node("Presentation") as Node3D
	var prediction := get_node("Prediction") as ClientPredictor3D
	(
		prediction
		. configure(
			controlled_peer_id,
			presentation,
			Callable(self, "_simulate_network_command"),
			true,
		)
	)


func bind_cube(cube: MultiplayerPowerCube) -> void:
	_cube = cube


func _ready() -> void:
	var is_local := multiplayer.get_unique_id() == controlled_peer_id
	# The demo controller activates the local camera only after its loading layer
	# has painted. That keeps first-use WebGL work out of a networking callback.
	_camera.current = false
	_body_mesh.visible = not is_local
	_nameplate.visible = not is_local
	_nameplate.text = "HOST" if controlled_peer_id == WebRTCSession.HOST_PEER_ID else "SURVIVOR-02"
	_apply_player_color()
	if OS.has_feature("web"):
		# Shadows are presentation-only and disproportionately expensive during the
		# browser's cold Compatibility-renderer frame.
		_helmet_lamp.shadow_enabled = false

	if is_local:
		_inputs.begin_local_control(global_transform.basis)
	_prediction.authoritative_reset_received.connect(_on_authoritative_reset_received)


func _process(_delta: float) -> void:
	_update_lamp()
	_update_tether_visual()


func _physics_process(delta: float) -> void:
	_inputs.update_from_local(delta)
	var flags := 0
	if _inputs.stabilizing:
		flags |= ClientPredictor3D.FLAG_STABILIZING
	if _inputs.cranking:
		flags |= ClientPredictor3D.FLAG_PRIMARY_ACTION
	_prediction.physics_step(delta, _inputs.thrust, _inputs.look_orientation, flags)


func is_cranking_cube() -> bool:
	return (
		multiplayer.is_server()
		and bool(_prediction.get_authoritative_flags() & ClientPredictor3D.FLAG_PRIMARY_ACTION)
		and is_near_cube()
	)


func is_near_cube() -> bool:
	return _cube != null and global_position.distance_to(_cube.global_position) <= CRANK_DISTANCE


func activate_local_camera() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_camera.make_current()


func capture_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.capture_mouse()


func release_local_control() -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.release_mouse()


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
	var turn_weight := 1.0
	if angle > 0.0001:
		turn_weight = minf(MAX_TURN_RATE * delta / angle, 1.0)
	global_transform.basis = Basis(current_rotation.slerp(requested_rotation, turn_weight))

	velocity += (
		global_transform.basis
		* thrust.limit_length(1.0)
		* MovementKnobs.THRUST_ACCELERATION
		* delta
	)
	if bool(flags & ClientPredictor3D.FLAG_STABILIZING):
		velocity = (
			velocity
			. lerp(
				Vector3.ZERO,
				minf(MovementKnobs.LINEAR_STABILIZER_RATE * delta, 1.0),
			)
		)
	velocity = velocity.limit_length(MovementKnobs.MAX_SPEED)

	_apply_tether_force(delta)
	move_and_slide()


func _on_authoritative_reset_received(body_transform: Transform3D) -> void:
	if multiplayer.get_unique_id() == controlled_peer_id:
		_inputs.reset_local_orientation(body_transform.basis)


func _apply_tether_force(delta: float) -> void:
	if _cube == null:
		return
	var offset := _cube.global_position - global_position
	var distance := offset.length()
	if distance <= TETHER_LENGTH or distance <= 0.0001:
		return

	var direction := offset / distance
	var stretch := minf(distance - TETHER_LENGTH, MAX_TETHER_STRETCH)
	velocity += direction * TETHER_PLAYER_ACCELERATION * stretch * delta
	# Equal directions, deliberately unequal magnitudes: the cube is roughly ten
	# times the suit's mass, so this produces a readable slow drag rather than a
	# one-tonne light source snapping toward the player.
	_cube.apply_tether_force(-direction * TETHER_CUBE_FORCE * stretch)


func _update_lamp() -> void:
	if _cube == null:
		return
	var level := smoothstep(0.0, 1.0, _cube.power_fraction)
	_helmet_lamp.light_energy = PowerKnobs.HELMET_LAMP_ENERGY * level
	_helmet_lamp.spot_range = lerpf(
		PowerKnobs.HELMET_LAMP_RANGE * PowerKnobs.SUIT_LAMP_MIN_RANGE_FRACTION,
		PowerKnobs.HELMET_LAMP_RANGE,
		level,
	)


func _update_tether_visual() -> void:
	_tether.visible = _cube != null
	if _cube == null:
		return

	var segment := _cube.global_position - global_position
	var distance := segment.length()
	if distance <= 0.0001:
		_tether.visible = false
		return

	var direction := segment / distance
	var reference := Vector3.FORWARD
	if absf(reference.dot(direction)) > 0.98:
		reference = Vector3.RIGHT
	var right := reference.cross(direction).normalized()
	var forward := right.cross(direction).normalized()
	var tether_basis := Basis(right, direction, forward).scaled(Vector3(1.0, distance, 1.0))
	_tether.global_transform = Transform3D(
		tether_basis,
		global_position + segment * 0.5,
	)


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
