class_name MultiplayerPowerCube
extends RigidBody3D

## Host-simulated shared power cube with synchronized state and local visuals.
##
## Peer 1 owns physics and charge. Other peers freeze their RigidBody and apply
## the state received by the visible MultiplayerSynchronizer in the cube scene.

@export var synced_transform := Transform3D.IDENTITY
@export var synced_linear_velocity := Vector3.ZERO
@export var synced_angular_velocity := Vector3.ZERO
@export_range(0.0, 1.0, 0.001) var power_fraction := PowerKnobs.CUBE_START_FRACTION:
	set(value):
		power_fraction = clampf(value, 0.0, 1.0)
		_update_power_visuals()

var _authoritative_simulation := false
var _active_player_count := 0
var _cranker_count := 0
var _initial_transform := Transform3D.IDENTITY
var _gauge: CubePowerGauge

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $CubeLight
@onready var _world_label: Label3D = $WorldLabel


func _ready() -> void:
	_initial_transform = global_transform
	_gauge = CubePowerGauge.new()
	_gauge.name = "PowerGauge"
	add_child(_gauge)
	_gauge.build(MovementKnobs.CARRY_OBJECT_SIZE)
	_update_power_visuals()


func _physics_process(delta: float) -> void:
	if _authoritative_simulation and multiplayer.is_server():
		_simulate_power(delta)
		synced_transform = global_transform
		synced_linear_velocity = linear_velocity
		synced_angular_velocity = angular_velocity
	elif not multiplayer.is_server():
		# Replicas display the host's accepted state and never run competing
		# rigid-body physics of their own.
		global_transform = synced_transform
		linear_velocity = synced_linear_velocity
		angular_velocity = synced_angular_velocity


func set_authoritative_simulation(enabled: bool) -> void:
	_authoritative_simulation = enabled
	freeze = not enabled
	if enabled:
		synced_transform = global_transform
		synced_linear_velocity = linear_velocity
		synced_angular_velocity = angular_velocity


## Starts a fresh hosted session from the demo's authored cube state.
func reset_authoritative_state() -> void:
	if not multiplayer.is_server():
		return
	global_transform = _initial_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	power_fraction = PowerKnobs.CUBE_START_FRACTION
	synced_transform = global_transform
	synced_linear_velocity = linear_velocity
	synced_angular_velocity = angular_velocity


func set_power_activity(active_players: int, cranking_players: int) -> void:
	_active_player_count = clampi(active_players, 0, 2)
	_cranker_count = clampi(cranking_players, 0, _active_player_count)


## Keeps the Web networking proof responsive without changing synchronized state.
func use_web_demo_render_profile() -> void:
	_light.shadow_enabled = false


## Tether forces are accepted only by the host's live physics body.
func apply_tether_force(force: Vector3) -> void:
	if _authoritative_simulation and multiplayer.is_server():
		apply_central_force(force)


func _simulate_power(delta: float) -> void:
	# Each active lamp draws the existing prototype's suit drain from the one
	# shared cube. A nearby player holding F feeds the existing crank rate back.
	var spent := (
		float(_active_player_count)
		* PowerKnobs.SUIT_DRAIN_PER_SECOND
		/ PowerKnobs.CUBE_CAPACITY
		* delta
	)
	var generated := (
		float(_cranker_count) * PowerKnobs.CRANK_PER_SECOND / PowerKnobs.CUBE_CAPACITY * delta
	)
	power_fraction += generated - spent


func _update_power_visuals() -> void:
	if not is_node_ready():
		return

	# Presentation is derived locally from one synchronized gameplay value.
	# Light energy and material state therefore never become network protocol.
	var level := smoothstep(0.0, 1.0, power_fraction)
	_light.light_energy = PowerKnobs.CUBE_LIGHT_ENERGY * level
	_light.omni_range = lerpf(
		PowerKnobs.CUBE_LIGHT_RANGE * PowerKnobs.CUBE_LAMP_MIN_RANGE_FRACTION,
		PowerKnobs.CUBE_LIGHT_RANGE,
		level,
	)

	var material := _mesh.material_override as StandardMaterial3D
	if material != null:
		material.emission_enabled = power_fraction > 0.0
		material.emission_energy_multiplier = PowerKnobs.CUBE_GLOW * level

	if _gauge != null:
		_gauge.show_fraction(power_fraction)
	_world_label.text = "SHARED POWER CUBE\n%3.0f%% · HOLD F NEARBY" % (power_fraction * 100.0)
