@tool
class_name Clinger
extends CharacterBody3D

## SURFACE FAUNA, MINOR. It crawls rock toward whatever it heard, leaps at a suit inside
## `clinger_jump_range`, and rides the visor draining air, charge and health until the
## player mashes it off. Deliberately not a citizen of `gameplay/creature/`: that module's
## HFSM, suspicion board and A* navigator are all dead weight on a thing whose entire life
## is wake, crawl, latch.
##
## Every number it runs on lives in the Clinger group on `PlayerSettings`. This file
## carries geometry, timing and one per-placement flag, which is the split GasPod and
## ArcHazard already use.

signal state_changed(phase: ClingerState.Phase)
signal attached(victim: Node3D)
signal shed(victim: Node3D)
signal died(at: Vector3)

## The stalker's ear. AsteroidLevel._wire_hazard_noise connects every member of
## HazardDamage.NOISE_GROUP straight into CreaturePerception, so a leap, a struggle and a
## death are all things the big creature can come and look at. Thrashing is loud.
signal world_noise(at: Vector3, loudness: float)

## What it holds on to. Layer 1, `hull` -- and emphatically NOT what this body sits on:
## NavigationSource.bake() runs once against that mask and never again, so a clinger on
## layer 1 freezes into the stalker's graph as permanent rock that then walks away.
const SURFACE_MASK := 1

## Layer 5, `creature`. Cleared to nothing while attached or dead, which stops the suit
## colliding with a shape inside its own hull and stops the mining ray finding it.
const CREATURE_LAYER := 1 << 4

## Half the shell, so the belly rides ClingerSurface.SURFACE_LIFT clear of the rock.
##
## THE COLLIDER HAS TO BE NARROWER THAN _lift(). The body holds its origin that far off
## the rock, so a wider shape starts every leap already embedded in the wall it is pushing
## off, and move_and_collide reports a hit on the first frame and lands it again. Checked
## in _ready rather than written in the .tscn, because an editor save drops scene comments.
const BODY_HALF_THICKNESS := 0.06

## How far the seat ray looks before the body counts as having lost its grip, and how far
## the fourteen-ray fan reaches when it has.
const SEAT_REACH := 0.9
const RECOVERY_REACH := 14.0

## One ray ahead, so a wall gets slid along rather than walked into.
const PEEK_DISTANCE := 0.4

## Turned this far about the surface normal every time a step finds nothing to stand on.
## A body with no legal move should take a bad move over no move.
const EDGE_TURN_DEGREES := 40.0
const STALL_LIMIT := 9

const ADHESION_RATE := 12.0

## How much faster than a crawl a body may re-seat itself on a surface it has lost.
const REGRIP_SPEED_MULTIPLIER := 4.0
const TURN_RATE := 3.2
const ORIENT_SLEW_RATE := 5.0

## Multiplies a leap's straight-line flight time to give it a deadline, so one that misses
## everything still ends.
const LEAP_TIMEOUT_SLACK := 2.5

## Push-off along the surface normal as it launches, so departure reads as a leap off the
## rock rather than a dart out of it.
const LEAP_KICK := 1.4

## Seconds a landed clinger spends re-gripping before it crawls again.
const SETTLE_SECONDS := 0.3

## How hard a shed one shoves itself clear of the visor, and how fast a dead one drifts.
const SHED_PUSH := 0.5
const DEATH_KICK := 0.35
const DEATH_TUMBLE := 0.6

## In the world-noise scale CreaturePerception reads, where 1.0 is as loud as anything
## gets. A leap is a scrabble; a death is quieter than the beam that caused it.
const LEAP_LOUDNESS := 0.35
const DEATH_LOUDNESS := 0.2
const STRUGGLE_LOUDNESS := 0.7

@export var settings: PlayerSettings

## Motionless until something wakes it. The first one a player meets should be a thing
## they get to circle, light and decide is dead -- see it on a dead man, then feel it on
## yourself. Off for a sandbox copy somebody is iterating on.
@export var starts_dormant: bool = true

@export_tool_button("Snap to Nearest Wall") var snap_action := snap_to_nearest_wall

var _phase := ClingerState.Phase.DORMANT
var _position := Vector3.ZERO
var _forward := Vector3.FORWARD
var _up := Vector3.UP
var _velocity := Vector3.ZERO
var _noise_at := Vector3.ZERO
var _noise_age := INF
var _cooldown_left := 0.0
var _leap_left := 0.0
var _settle_left := 0.0
var _despawn_left := 0.0
var _orbit_phase := 0.0
var _stalls := 0
var _damage_taken := 0.0
var _hit_this_frame := false
var _hit_at := Vector3.ZERO
var _victim: Node3D = null

@onready var _ears: ClingerEars = $Ears
@onready var _grip: ClingerGrip = $Grip
@onready var _legs: ClingerLegs = $Legs
@onready var _impact: MiningImpact = $MiningImpact
@onready var _model: Node3D = $sm_clinger


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("Clinger has no settings; running on PlayerSettings defaults.")
	add_to_group(HazardDamage.NOISE_GROUP)
	# After PlayerCollisionResponse (100), which owns move_and_slide, and PlayerHealth
	# (110). An attached clinger has to read a head that has already moved this frame or
	# it swims a frame behind the eye it is sitting on.
	process_physics_priority = 120
	_ears.settings = settings
	_grip.settings = settings
	_ears.heard.connect(_on_heard)
	_grip.shed.connect(_on_shed)
	_grip.peeled.connect(_on_peeled)
	_legs.bind(_model)
	var shape := ($Collider as CollisionShape3D).shape as SphereShape3D
	if shape != null and shape.radius >= _lift():
		push_warning(
			(
				"Clinger collider is %.2f m against a %.2f m lift; every leap will stall on launch."
				% [shape.radius, _lift()]
			)
		)
	_position = global_position
	_forward = -global_transform.basis.z
	_up = global_transform.basis.y
	_set_phase(ClingerState.Phase.DORMANT if starts_dormant else ClingerState.Phase.CRAWLING)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _resolve_mining():
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_noise_age += delta
	_ears.advance(delta, _position)
	match _phase:
		ClingerState.Phase.DEAD:
			_advance_dead(delta)
		ClingerState.Phase.ATTACHED:
			_advance_attached(delta)
		ClingerState.Phase.LEAPING:
			_advance_leap(delta)
		_:
			_advance_crawl(delta)
	if not is_queued_for_deletion():
		_legs.advance(delta, ClingerLegs.pose_for(_phase, _grip.peel()))


## Called every physics frame the beam is on it, so it latches and integrates rather than
## treating one call as one hit -- the contract MineralChunk, GasPod and Blockage share.
func take_mining_damage(damage: float, at: Vector3, _tool: PlayerMiningTool) -> void:
	if _phase == ClingerState.Phase.DEAD:
		return
	_hit_this_frame = true
	_damage_taken += damage
	_hit_at = at
	wake(at)


## Puts the body somewhere, integrator and all.
##
## Setting global_position alone does not work and fails quietly: the crawl owns the
## transform and writes its own `_position` back over it every frame, so a clinger moved
## after it entered the tree simply walks back. Same reason CrawlerBody has one. A
## placement authored into a level scene needs none of this -- _ready reads the pose it
## arrived with.
func teleport(to: Vector3) -> void:
	_position = to
	global_position = to
	_velocity = Vector3.ZERO


## Points it at a noise, and starts it moving if it was not already.
func wake(at: Vector3) -> void:
	_noise_at = at
	_noise_age = 0.0
	if _phase == ClingerState.Phase.DORMANT:
		_set_phase(ClingerState.Phase.CRAWLING)


## Seats this placement on the rock behind it, in the editor. GasPod's probe, whose two
## statics are public for exactly this: it casts from both ends of every direction,
## because the level trimesh is backface-blind and a body already inside rock can only see
## the face it is behind from the far side.
func snap_to_nearest_wall() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var found := GasPod.nearest_surface(
		get_world_3d().direct_space_state, [get_rid()], global_position
	)
	if found.is_empty():
		push_warning("Clinger %s found no rock nearby; not moved." % name)
		return
	var normal: Vector3 = found["normal"]
	global_transform = Transform3D(
		ClingerSurface.basis_from(global_transform.basis.x, normal),
		found["position"] as Vector3 + normal * _lift()
	)
	# Looked up by name rather than named directly: the bare EditorInterface identifier is
	# compiled out of export templates, and this script ships.
	if Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").mark_scene_as_unsaved()


func debug_state() -> Dictionary:
	return {
		"phase": ClingerState.phase_name(_phase),
		"lift": _lift(),
		"damage_taken": _damage_taken,
		"cooldown_left": _cooldown_left,
		"noise_age": _noise_age,
		"noise_at": _noise_at,
		"despawn_left": _despawn_left,
		"stalls": _stalls,
		"grip": _grip.debug_state(),
		"ears": _ears.debug_state(),
		"legs": _legs.debug_state(),
	}


## How far the origin rides off the rock: the lift, plus the half of the shell below it.
func _lift() -> float:
	return ClingerSurface.SURFACE_LIFT + BODY_HALF_THICKNESS


func _resolve_mining() -> bool:
	if not _hit_this_frame:
		_impact.stop()
		return false
	_hit_this_frame = false
	_impact.global_position = _hit_at
	_impact.start()
	if _damage_taken < settings.clinger_hp:
		return false
	_die()
	return true


func _advance_crawl(delta: float) -> void:
	var seat := _seat()
	if seat.is_empty():
		_drift(delta)
		return
	_up = seat["normal"]
	var wanted: Vector3 = seat["position"] as Vector3 + _up * _lift()
	var pull := _position.lerp(wanted, ClingerSurface.smoothing(ADHESION_RATE, delta)) - _position
	# Capped, so a body that lost its grip swims back at a speed you can watch rather than
	# snapping across the room on the frame a ray finally finds something.
	var limit := settings.clinger_crawl_speed * delta * REGRIP_SPEED_MULTIPLIER
	if pull.length() > limit:
		pull = pull.normalized() * limit
	_position += pull
	if _phase != ClingerState.Phase.DORMANT and _settle_left <= 0.0:
		_steer(delta, _target(delta))
		_step(delta)
		_consider_leap()
	_settle_left = maxf(_settle_left - delta, 0.0)
	if _phase == ClingerState.Phase.CRAWLING and _noise_age > settings.clinger_forget_seconds:
		_set_phase(ClingerState.Phase.DORMANT)
	_apply_pose(delta)


## Where it is trying to be. A shed clinger circles the suit that shed it; everything else
## walks to the last thing it heard.
func _target(delta: float) -> Vector3:
	if _phase != ClingerState.Phase.ORBITING or not is_instance_valid(_victim):
		return _noise_at
	var radius := settings.clinger_orbit_radius()
	_orbit_phase += ClingerState.orbit_step(settings.clinger_crawl_speed, radius, delta)
	return ClingerSurface.orbit_target(
		_victim.global_position, _position, _up, radius, _orbit_phase
	)


func _steer(delta: float, goal: Vector3) -> void:
	var to_goal := ClingerSurface.project(goal - _position, _up)
	if to_goal.is_zero_approx():
		to_goal = _forward
	var wanted := ClingerSurface.turn_limited(_forward, to_goal, TURN_RATE * delta)
	var ahead := _ray(_position, wanted, PEEK_DISTANCE)
	if ahead.is_empty():
		_forward = wanted
		return
	# Head-on into a dead end leaves nothing to slide along; keeping the old heading is a
	# lean, and normalising a zero flips the body inside out.
	var slid := ClingerSurface.project(wanted, ahead["normal"])
	_forward = slid.normalized() if not slid.is_zero_approx() else _forward


func _step(delta: float) -> void:
	var reach := settings.clinger_crawl_speed * delta
	if reach <= 0.0:
		return
	var ahead := _position + _forward * reach
	# One ray from above the step point back into the surface. This is what carries the
	# body round a concave corner and onto the next face.
	var seat := _ray(ahead + _up * SEAT_REACH * 0.5, -_up, SEAT_REACH)
	if seat.is_empty():
		# It walked off a convex lip. Look back under itself for the far side of it.
		seat = _ray(ahead, -_forward, SEAT_REACH)
	if seat.is_empty():
		_stalls += 1
		_forward = _forward.rotated(_up, deg_to_rad(EDGE_TURN_DEGREES))
		if _stalls >= STALL_LIMIT:
			_stalls = 0
		return
	_stalls = 0
	_up = seat["normal"]
	_position = seat["position"] as Vector3 + _up * _lift()


## Knocked into open space, which is where a shed clinger or a leap that missed everything
## ends up. Coast toward whatever it was heading for until a ray lands again.
func _drift(delta: float) -> void:
	var heading := _target(delta) - _position
	if heading.is_zero_approx():
		heading = _forward
	_forward = ClingerSurface.turn_limited(_forward, heading, TURN_RATE * delta)
	_position += _forward * settings.clinger_crawl_speed * delta
	_consider_leap()
	_apply_pose(delta)


func _consider_leap() -> void:
	var victim := _nearest_victim()
	if victim == null:
		if _phase == ClingerState.Phase.ORBITING:
			_set_phase(ClingerState.Phase.CRAWLING)
		return
	var head := HazardDamage.head_of(victim)
	var at: Vector3 = head.global_position if head != null else victim.global_position
	var reachable := ClingerState.can_leap(
		_cooldown_left, _position.distance_to(at), settings.clinger_jump_range
	)
	if reachable and _can_see(at):
		_begin_leap(victim, at)


func _begin_leap(victim: Node3D, at: Vector3) -> void:
	_victim = victim
	var aim := at - _position
	if aim.is_zero_approx():
		aim = _forward
	var speed := maxf(settings.clinger_leap_speed, 0.01)
	_velocity = aim.normalized() * speed + _up * LEAP_KICK
	_leap_left = _position.distance_to(at) / speed * LEAP_TIMEOUT_SLACK
	_cooldown_left = settings.clinger_attack_cooldown
	global_transform = Transform3D(ClingerSurface.basis_from(_forward, _up), _position)
	_set_phase(ClingerState.Phase.LEAPING)
	world_noise.emit(_position, LEAP_LOUDNESS)


func _advance_leap(delta: float) -> void:
	var hit := move_and_collide(_velocity * delta)
	_position = global_position
	if hit == null:
		_leap_left -= delta
		if _leap_left <= 0.0:
			_land_on_nearest()
			return
		_apply_flight_pose()
		return
	var victim := _player_root(hit.get_collider() as Node)
	# Anywhere on the suit is the face. The only collider a player body owns is one hull
	# sphere, so there is no per-limb bookkeeping to get wrong.
	if victim != null and _grip.attach(victim):
		_take_hold(victim)
		return
	_land_on(hit.get_position(), hit.get_normal())


func _take_hold(victim: Node3D) -> void:
	_victim = victim
	_velocity = Vector3.ZERO
	# Layer 0 does two jobs at once. The suit stops colliding with a shape sitting inside
	# its own 0.4 m hull, and the mining ray -- which passes no mask and excludes only the
	# player body -- stops finding it. The beam fires from the same head this is riding, so
	# burning one off your own face would be strictly better than mashing and would delete
	# the struggle outright. The beam is the answer while it crawls; mashing is the answer
	# while it is on you.
	collision_layer = 0
	# Drawn like the world but kept out of the helmet lamp's shadow casters. The lamp sits
	# a hand's width behind this thing, and on the world layer its shadow is the screen.
	_set_render_layers(PlayerRenderLayers.own_tool_mask())
	_set_phase(ClingerState.Phase.ATTACHED)
	attached.emit(victim)


func _advance_attached(delta: float) -> void:
	_grip.authority_step(delta)
	if not _grip.is_attached():
		_let_go()
		return
	global_transform = _grip.anchor_transform()
	_position = global_position
	_up = global_transform.basis.y
	_forward = -global_transform.basis.z


func _let_go() -> void:
	if _phase != ClingerState.Phase.ATTACHED:
		return
	_grip.release()
	collision_layer = CREATURE_LAYER
	_set_render_layers(PlayerRenderLayers.world_mask())
	_cooldown_left = maxf(_cooldown_left, settings.clinger_attack_cooldown)
	_orbit_phase = 0.0
	# Shoved clear along the shell's own normal, which is straight out of the visor, so it
	# is not still inside the suit's hull on the next frame.
	_position += _up * SHED_PUSH
	global_position = _position
	_set_phase(ClingerState.Phase.ORBITING)
	shed.emit(_victim)


func _land_on(at: Vector3, normal: Vector3) -> void:
	if not normal.is_zero_approx():
		_up = normal.normalized()
	_position = at + _up * _lift()
	global_position = _position
	var ahead := ClingerSurface.project(_forward, _up)
	if not ahead.is_zero_approx():
		_forward = ahead.normalized()
	_velocity = Vector3.ZERO
	_settle_left = SETTLE_SECONDS
	global_transform = Transform3D(ClingerSurface.basis_from(_forward, _up), _position)
	_set_phase(
		ClingerState.Phase.ORBITING if is_instance_valid(_victim) else ClingerState.Phase.CRAWLING
	)


func _land_on_nearest() -> void:
	var seat := _seat()
	if not seat.is_empty():
		_land_on(seat["position"], seat["normal"])
		return
	_velocity = Vector3.ZERO
	_set_phase(
		ClingerState.Phase.ORBITING if is_instance_valid(_victim) else ClingerState.Phase.CRAWLING
	)


func _die() -> void:
	_grip.release()
	_impact.stop()
	collision_layer = 0
	# It lets go. A thing that dies still clamped to a wall reads as a bug in a game with
	# no gravity, and the drift is how a player knows it is over.
	_velocity = _up * DEATH_KICK
	_despawn_left = settings.clinger_death_despawn_time
	_set_phase(ClingerState.Phase.DEAD)
	world_noise.emit(_position, DEATH_LOUDNESS)
	died.emit(_position)


func _advance_dead(delta: float) -> void:
	_despawn_left -= delta
	if _despawn_left <= 0.0:
		queue_free()
		return
	_position += _velocity * delta
	var tumbled := Basis(Vector3.UP, DEATH_TUMBLE * delta) * global_transform.basis
	global_transform = Transform3D(tumbled.orthonormalized(), _position)


## The surface this body is holding, or the nearest one it can still reach.
func _seat() -> Dictionary:
	var under := _ray(_position, -_up, SEAT_REACH)
	if not under.is_empty():
		return under
	var near := _reacquire(SEAT_REACH)
	return near if not near.is_empty() else _reacquire(RECOVERY_REACH)


func _reacquire(reach: float) -> Dictionary:
	var best := {}
	var closest := reach
	for direction: Vector3 in ClingerSurface.FAN:
		var hit := _ray(_position, direction, reach)
		if hit.is_empty():
			continue
		var distance := _position.distance_to(hit["position"])
		if distance >= closest:
			continue
		closest = distance
		best = hit
	return best


func _ray(from: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var heading := direction.normalized()
	if heading.is_zero_approx() or reach <= 0.0:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, from + heading * reach, SURFACE_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	# A hit from inside a backface-blind trimesh reports nothing usable, and a normal that
	# disagrees with the heading would push the body further in rather than out.
	if normal.length_squared() < 0.5 or normal.dot(heading) > -0.1:
		normal = -heading
	return {"position": hit["position"], "normal": normal.normalized()}


func _can_see(at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_position, at, SURFACE_MASK)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _nearest_victim() -> Node3D:
	var best: Node3D = null
	var closest := settings.clinger_hearing_range
	for body: Node3D in HazardDamage.players(get_tree()):
		var health := HazardDamage.health_of(body)
		# Online, a suit is driven by somebody else's authority and is not ours to grab.
		if health == null or health.externally_driven:
			continue
		var distance := _position.distance_to(body.global_position)
		if distance >= closest:
			continue
		closest = distance
		best = body
	return best


func _apply_pose(delta: float) -> void:
	if ClingerSurface.too_parallel(_forward, _up):
		var side := ClingerSurface.project(global_transform.basis.x, _up)
		if not side.is_zero_approx():
			_forward = side.normalized()
	var wanted := ClingerSurface.basis_from(_forward, _up)
	var slewed := ClingerSurface.slew(_forward, _up, wanted, ORIENT_SLEW_RATE * delta)
	_forward = -slewed.z
	_up = slewed.y
	global_transform = Transform3D(slewed, _position)


## Belly first, so it arrives the way it means to land.
func _apply_flight_pose() -> void:
	var heading := _velocity.normalized()
	if heading.is_zero_approx():
		return
	_up = -heading
	var side := ClingerSurface.project(_forward, _up)
	if side.is_zero_approx():
		side = ClingerSurface.project(Vector3.UP, _up)
	if not side.is_zero_approx():
		_forward = side.normalized()
	global_transform = Transform3D(ClingerSurface.basis_from(_forward, _up), _position)


func _set_render_layers(mask: int) -> void:
	for child: Node in _model.get_children():
		var mesh := child as VisualInstance3D
		if mesh != null:
			mesh.layers = mask


func _set_phase(phase: ClingerState.Phase) -> void:
	if phase == _phase:
		return
	_phase = phase
	state_changed.emit(phase)


func _on_heard(at: Vector3, _strength: float) -> void:
	if _phase == ClingerState.Phase.DEAD or _phase == ClingerState.Phase.ATTACHED:
		return
	wake(at)


func _on_peeled() -> void:
	world_noise.emit(global_position, STRUGGLE_LOUDNESS)


func _on_shed(_victim: Node3D) -> void:
	_let_go()


## The player body a collider belongs to, whichever part of the suit was struck.
static func _player_root(node: Node) -> Node3D:
	var walk := node
	while walk != null:
		if walk.is_in_group(HazardDamage.PLAYER_GROUP):
			return walk as Node3D
		walk = walk.get_parent()
	return null
