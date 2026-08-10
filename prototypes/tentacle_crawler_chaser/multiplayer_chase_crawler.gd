class_name MultiplayerChaseCrawler
extends CrawlerBody

## Host-authoritative crawler with locally reconstructed tentacle presentation.
##
## Peer 1 runs CrawlerBody's solver and publishes only root motion. Clients do
## not run that integrator; their TentacleArray still raycasts the identical
## static room and TentacleBones poses those cosmetic local results.

@export var synced_transform := Transform3D.IDENTITY
@export var synced_velocity := Vector3.ZERO
@export var synced_travel := Vector3.FORWARD
@export var snapshot_ready := false

var _session_active := false
var _initial_transform := Transform3D.IDENTITY

@onready var _contact: CreatureContact = $CreatureContact
@onready var _creature_light: OmniLight3D = $CreatureLight


func _ready() -> void:
	super()
	_initial_transform = global_transform
	max_speed = MultiplayerChaseKnobs.CRAWLER_MAX_SPEED
	leash_slack = ChaseKnobs.CREATURE_LEASH_SLACK
	probe_comfort = ChaseKnobs.CREATURE_PROBE_COMFORT
	probe_mask = ChaseKnobs.CREATURE_PROBE_MASK
	tentacles.query_mask = ChaseKnobs.CREATURE_TENTACLE_MASK
	tentacles.enabled = false

	_contact.set_catch_radius(MultiplayerChaseKnobs.CRAWLER_CATCH_RADIUS)
	_contact.monitoring = false
	_creature_light.light_color = ChaseKnobs.CREATURE_LIGHT_COLOR
	_creature_light.light_energy = ChaseKnobs.CREATURE_LIGHT_ENERGY
	_creature_light.omni_range = ChaseKnobs.CREATURE_LIGHT_RANGE
	_creature_light.omni_attenuation = ChaseKnobs.CREATURE_LIGHT_ATTENUATION
	_creature_light.shadow_enabled = false


func _physics_process(delta: float) -> void:
	if not _session_active:
		return
	if multiplayer.is_server():
		# CrawlerBody remains the only authoritative transform writer.
		super(delta)
		_publish_snapshot()
	elif snapshot_ready:
		_apply_replica(delta)


func set_session_active(active: bool) -> void:
	_session_active = active
	tentacles.enabled = active
	# Catch signals arrive while the physics server is flushing queries. Defer
	# monitoring changes so a catch/reset cannot mutate Area state in that flush.
	_contact.set_deferred(&"monitoring", active and multiplayer.is_server())
	_contact.armed = active and multiplayer.is_server()
	if not active:
		snapshot_ready = false
	elif multiplayer.is_server():
		_publish_snapshot()


func reset_authoritative_state() -> void:
	if not multiplayer.is_server():
		return
	var basis := _initial_transform.basis.orthonormalized()
	_position = _initial_transform.origin
	_velocity = Vector3.ZERO
	_orientation = basis.get_rotation_quaternion().normalized()
	_forward = -basis.z.normalized()
	_up = basis.y.normalized()
	_travel = _forward
	_time = 0.0
	_pull_lateral = Vector3.ZERO
	_stroke_urge = -1.0
	global_transform = Transform3D(Basis(_orientation), _position)
	_contact.armed = true
	_publish_snapshot()


func set_contact_armed(armed: bool) -> void:
	_contact.armed = armed and multiplayer.is_server()


func _publish_snapshot() -> void:
	synced_transform = global_transform
	synced_velocity = _velocity
	synced_travel = _travel
	# This gate is last in the replication config, after the snapshot it guards.
	snapshot_ready = true


func _apply_replica(delta: float) -> void:
	var basis := synced_transform.basis.orthonormalized()
	_position = synced_transform.origin
	_velocity = synced_velocity
	_orientation = basis.get_rotation_quaternion().normalized()
	_forward = -basis.z.normalized()
	_up = basis.y.normalized()
	_travel = CrawlerMath.direction_or(synced_travel, _forward)
	_time += delta
	global_transform = Transform3D(Basis(_orientation), _position)
	_apply_squash()
