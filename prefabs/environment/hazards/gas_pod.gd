@tool
class_name GasPod
extends StaticBody3D

## A pressurised bubble welded to the rock. It goes if you cut it, if you touch it, or if
## you linger inside its proximity ring -- and it hisses and swells first, so lingering is
## a decision rather than an ambush.

## Loud, positioned, and nobody's fault. AsteroidLevel wires this to the creature.
signal world_noise(at: Vector3, loudness: float)
signal detonated(at: Vector3)

## The proximity countdown started or stopped. Not emitted for a cut, which commits.
signal arming_changed(arming: bool)

const ARMED_LIGHT_ENERGY := 3.5
const FLASH_SECONDS := 0.35

## How far the shell swells at the end of the countdown, and how the throb accelerates
## across it. The animation is the warning; the sound only says it started.
const SWELL := 0.4
const PULSE_HZ_START := 2.0
const PULSE_HZ_END := 9.0

## MineralDeposit's snapping numbers, doing the same job on one body.
const SNAP_MAX_DISTANCE := 5.0
const SNAP_RAY_DIRECTIONS := 32
const SNAP_EMBED_DEPTH := 0.08
const SNAP_COLLISION_MASK := 1

## Where a pod's size and reach come from. The prefab points this at
## player_settings.tres, so a pod is sized and armed from the same resource the suit
## is tuned with rather than from a second copy of the numbers.
@export var settings: PlayerSettings

@export_group("Detonation")

## How much beam it takes. Low on purpose: cutting one is easy, which is the point.
@export_range(0.5, 20.0, 0.5) var pod_health: float = 2.0

## The beat between a cut opening it and it going. Committed -- backing off will not
## call this one off.
@export_range(0.0, 2.0, 0.05, "suffix:s") var cut_fuse_seconds: float = 0.35

@export_group("Proximity")

## This placement's share of PlayerSettings.hazard_gas_pod_trigger_range, so one pod
## can reach further than another without a second copy of the figure to drift.
##
## Flying straight at a pod still detonates it on contact -- the countdown is for
## someone who STOPS next to one, which is the player who parked to mine beside it.
@export_range(0.1, 4.0, 0.05) var trigger_range_scale: float = 1.0:
	set(value):
		trigger_range_scale = value
		_apply_dimensions()

## How long you may stay that close before it goes. The countdown resets if you leave.
@export_range(0.1, 20.0, 0.1, "suffix:s") var proximity_fuse_seconds: float = 2.0

@export_group("Blast")

@export_range(0.5, 20.0, 0.5, "suffix:m") var blast_radius: float = 6.0

## The shove, before mass. PlayerLocomotion divides by player_mass.
@export_range(0.0, 4000.0, 10.0, "suffix:N") var blast_impulse: float = 1400.0

## This placement's share of PlayerSettings.hazard_gas_pod_damage, so one pod can be
## nastier than another without a second copy of the figure to drift.
@export_range(0.0, 4.0, 0.05) var damage_scale: float = 1.0

## Raw loudness handed to the creature. ABOVE 1.0 DELIBERATELY: CreatureHearing clamps
## the RECEIVED strength, not this, so a value past the ceiling is what makes a
## detonation carry farther than the beam that lit it.
@export_range(0.0, 4.0, 0.1) var noise_loudness: float = 2.5

@export_tool_button("Snap to Nearest Wall") var snap_action := snap_to_nearest_wall

## True while anything is inside the ring. Derived from the occupant list rather than from
## whichever signal fired last, so one of two players leaving cannot call the all-clear.
var any_trigger_in_proximity := false

var _occupants: Array[Node3D] = []
var _proximity_left := INF
var _fuse_left := INF
var _pulse_phase := 0.0
var _damage_taken := 0.0
var _hit_this_frame := false
var _spent := false

@onready var _shell: MeshInstance3D = $Shell
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _contact: Area3D = $ContactTrigger
@onready var _proximity: Area3D = $ProximityTrigger
@onready var _contact_shape: CollisionShape3D = $ContactTrigger/CollisionShape3D
@onready var _proximity_shape: CollisionShape3D = $ProximityTrigger/CollisionShape3D
@onready var _impact: MiningImpact = $MiningImpact
@onready var _light: OmniLight3D = $BlastLight
@onready var _sfx: AudioStreamPlayer3D = $Sfx
@onready var _warn_sfx: AudioStreamPlayer3D = $WarnSfx


## Where a pod sits to look welded to a surface: base buried, dome pointing out along the
## wall normal. Static so the editor button and a headless placement pass share the maths.
static func surface_transform(at: Vector3, normal: Vector3) -> Transform3D:
	var up := normal.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	return Transform3D(Basis(side, up, side.cross(up).normalized()), at - up * SNAP_EMBED_DEPTH)


## The nearest surface around `anchor`, as a position and an outward normal, or an empty
## dictionary when nothing is in reach.
static func nearest_surface(
	space: PhysicsDirectSpaceState3D, exclude: Array[RID], anchor: Vector3
) -> Dictionary:
	var found := {}
	var closest := SNAP_MAX_DISTANCE
	for direction: Vector3 in sample_sphere_directions(SNAP_RAY_DIRECTIONS):
		var far_point := anchor + direction * SNAP_MAX_DISTANCE
		# Probed from both ends, as MineralDeposit does: the trimesh is backface-blind, so
		# a pod already inside rock can only see the face it is behind from the far side.
		var probes: Array[PackedVector3Array] = [
			PackedVector3Array([anchor, far_point]), PackedVector3Array([far_point, anchor])
		]
		for probe: PackedVector3Array in probes:
			var query := PhysicsRayQueryParameters3D.create(
				probe[0], probe[1], SNAP_COLLISION_MASK, exclude
			)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var at: Vector3 = hit["position"]
			var distance := anchor.distance_to(at)
			if distance >= closest:
				continue
			closest = distance
			var heading := (probe[1] - probe[0]).normalized()
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if normal.length_squared() < 0.5:
				normal = -heading
			found = {"position": at, "normal": normal.normalized()}
	return found


## Evenly spaced directions on the unit sphere, via a Fibonacci sphere.
static func sample_sphere_directions(count: int) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (float(i) / float(count - 1)) * 2.0
		var radius := sqrt(1.0 - y * y)
		directions.append(
			Vector3(cos(golden_angle * i) * radius, y, sin(golden_angle * i) * radius)
		)
	return directions


func _ready() -> void:
	_apply_dimensions()
	if Engine.is_editor_hint():
		return
	add_to_group(HazardDamage.NOISE_GROUP)
	_light.light_energy = 0.0
	_contact.body_entered.connect(_on_contact)
	_proximity.body_entered.connect(_on_proximity_entered)
	_proximity.body_exited.connect(_on_proximity_exited)


## Called every physics frame the beam is on it, so it latches and integrates rather than
## treating one call as one hit -- the contract MineralChunk already implements.
func take_mining_damage(damage: float, at: Vector3, _tool: PlayerMiningTool) -> void:
	if _spent:
		return
	_hit_this_frame = true
	_damage_taken += damage
	_impact.global_position = at


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _spent:
		return
	# A committed fuse outranks everything: backing off does not call off a cut pod.
	if _fuse_left < INF:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			detonate()
		return
	if any_trigger_in_proximity:
		_proximity_left -= delta
		if _proximity_left <= 0.0:
			detonate()
			return
		_warn(1.0 - _proximity_left / maxf(proximity_fuse_seconds, 0.001), delta)
	if not _hit_this_frame:
		_impact.stop()
		return
	_hit_this_frame = false
	_impact.start()
	if _damage_taken >= pod_health:
		commit_fuse(cut_fuse_seconds)


## Starts a fuse nothing can call off. Idempotent, and never lengthens one already running.
func commit_fuse(seconds: float) -> void:
	if _spent:
		return
	_fuse_left = minf(_fuse_left, maxf(seconds, 0.0))
	_impact.start()
	_light.light_energy = ARMED_LIGHT_ENERGY
	_warn_sfx.stop()


## Bills everyone in range, tells the creature, and takes the pod out of the world.
func detonate() -> void:
	if _spent:
		return
	_spent = true
	_fuse_left = INF
	for body: Node3D in HazardDamage.players(get_tree()):
		var share := HazardDamage.falloff(
			global_position.distance_to(body.global_position), blast_radius
		)
		if share <= 0.0:
			continue
		var health := HazardDamage.health_of(body)
		if health != null:
			health.take_damage(
				health.settings.hazard_gas_pod_damage * damage_scale * share,
				PlayerHealth.Source.GAS_POD
			)
		HazardDamage.shove(body, global_position, blast_impulse * share)
	world_noise.emit(global_position, noise_loudness)
	detonated.emit(global_position)
	_clear_out()


## How wide this pod's bubble is across its base.
func bubble_diameter() -> float:
	return _settings().hazard_gas_pod_diameter


## How close anything may get, from this pod's centre, before the countdown starts.
func trigger_range() -> float:
	return _settings().hazard_gas_pod_trigger_range * trigger_range_scale


## Lazy rather than resolved in _ready(), because the export setters run during scene
## load and a pod dropped in without a resource still has to size itself.
func _settings() -> PlayerSettings:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("GasPod has no settings; running on PlayerSettings defaults.")
	return settings


## How far through the proximity countdown this pod is, 0 to 1.
func arming_progress() -> float:
	if not any_trigger_in_proximity or _proximity_left >= INF:
		return 0.0
	return clampf(1.0 - _proximity_left / maxf(proximity_fuse_seconds, 0.001), 0.0, 1.0)


## Editor-only dressing pass: move onto the nearest rock and dome outward from it.
func snap_to_nearest_wall() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var found := nearest_surface(get_world_3d().direct_space_state, [get_rid()], global_position)
	if found.is_empty():
		push_warning(
			"GasPod %s found no rock within %.1f m; not moved." % [name, SNAP_MAX_DISTANCE]
		)
		return
	global_transform = surface_transform(found["position"], found["normal"])
	# Looked up by name rather than named directly: the bare EditorInterface identifier is
	# compiled out of export templates, and this script ships.
	if Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").mark_scene_as_unsaved()


## Swells and throbs harder the closer it is to going, so the warning is the object itself
## rather than an icon floating over it.
func _warn(progress: float, delta: float) -> void:
	_pulse_phase += delta * lerpf(PULSE_HZ_START, PULSE_HZ_END, progress) * TAU
	var beat := 0.5 - 0.5 * cos(_pulse_phase)
	_shell.scale = Vector3.ONE * bubble_diameter() * (1.0 + SWELL * progress * beat)
	_light.light_energy = ARMED_LIGHT_ENERGY * (0.25 + 0.75 * progress) * (0.4 + 0.6 * beat)


func _on_contact(body: Node3D) -> void:
	if body.is_in_group(HazardDamage.PLAYER_GROUP):
		detonate()


func _on_proximity_entered(body: Node3D) -> void:
	if not body.is_in_group(HazardDamage.PLAYER_GROUP) or _occupants.has(body):
		return
	_occupants.append(body)
	_refresh_proximity()


func _on_proximity_exited(body: Node3D) -> void:
	_occupants.erase(body)
	_refresh_proximity()


## Derived from the whole list, never from the one signal that just fired: with two suits
## inside, one of them leaving must not call the all-clear.
func _refresh_proximity() -> void:
	_occupants = _occupants.filter(func(body: Node3D) -> bool: return is_instance_valid(body))
	var live := not _occupants.is_empty()
	if live == any_trigger_in_proximity:
		return
	any_trigger_in_proximity = live
	_proximity_left = proximity_fuse_seconds
	_pulse_phase = 0.0
	if live:
		_warn_sfx.play(0.0)
	else:
		_warn_sfx.stop()
		_shell.scale = Vector3.ONE * bubble_diameter()
		_light.light_energy = 0.0
	arming_changed.emit(live)


## Sizes the dome and both triggers off the central figures.
##
## The mesh is authored one metre across and SCALED rather than rebuilt, so every pod
## shares one mesh -- and the base scale composes with the swell the countdown
## animates. The collision spheres cannot be scaled that way (Godot warns, and it does
## not work), so those are resized, which is why the prefab marks them local to it.
func _apply_dimensions() -> void:
	if _shell == null:
		return
	var radius := bubble_diameter() * 0.5
	_shell.scale = Vector3.ONE * bubble_diameter()
	_set_radius(_shape, radius)
	_set_radius(_contact_shape, radius)
	_set_radius(_proximity_shape, trigger_range())
	# The cue and the glow ride just off the rock rather than inside it.
	var lift := radius * 0.6
	_impact.position.y = lift
	_light.position.y = lift
	_warn_sfx.position.y = lift


static func _set_radius(shape: CollisionShape3D, radius: float) -> void:
	if shape == null:
		return
	var sphere := shape.shape as SphereShape3D
	if sphere != null:
		sphere.radius = maxf(radius, 0.01)


## The pod stops being an object the instant it goes, but the cue outlives it.
func _clear_out() -> void:
	_impact.stop()
	_warn_sfx.stop()
	_shell.visible = false
	_shape.set_deferred("disabled", true)
	_contact.set_deferred("monitoring", false)
	_proximity.set_deferred("monitoring", false)
	create_tween().tween_property(_light, "light_energy", 0.0, FLASH_SECONDS)
	_sfx.play(0.0)
	# A tree timer rather than `await _sfx.finished`, which needs an audio driver a headless
	# run does not have -- and a pod that never frees is a leak nobody finds.
	await get_tree().create_timer(_linger_seconds()).timeout
	queue_free()


## Long enough for the flash and the cue, whichever outlasts the other.
func _linger_seconds() -> float:
	if _sfx.stream == null:
		return FLASH_SECONDS
	return maxf(FLASH_SECONDS, _sfx.stream.get_length())
