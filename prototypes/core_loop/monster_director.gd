class_name MonsterDirector
extends Node3D

## The creature's senses, which it does not otherwise have.
##
## The chase prototype wires the creature straight to the player: it always knows
## where you are, from anywhere, through rock. This node is what replaces that
## with hearing, and it does it WITHOUT TOUCHING THE CREATURE AT ALL.
##
## The chain over there is three decoupled nodes, and the first one is the seam:
##
##   ChaseTarget           where should it go   (projects a quarry onto the navmesh)
##     -> ChaseTargetFollower   how does it get there
##        -> CrawlerBody        how does it look moving
##
## `ChaseTarget.quarry` is typed Node3D and nothing downstream ever asks what it
## is. So THIS NODE IS THE QUARRY: it moves itself to the last thing the creature
## heard, and the creature walks to it believing it is chasing something. Pointing
## `quarry` at a player instead is the whole difference between the two prototypes.
##
## THREE STATES, and the middle one is the interesting one:
##
##   DORMANT   not in the world at all. Loud noise can roll it awake.
##   HUNTING   spawned, walking to the last noise it heard. Deaf to anything
##             further away than that noise carried, and gives up after silence.
##   CHASING   it has you. The quarry tracks the player continuously, and only a
##             short timer - refreshed by any noise you make nearby - holds it.
##
## The escape that falls out of this is the one the design is for: sprint until
## you are outside CHASE_TRIGGER_RADIUS, then stop thrusting and be silent until
## the chase timer runs down. Both halves are needed. Distance alone does not save
## you while you are still making noise inside the radius, and silence alone does
## not save you while it is standing on top of you.

## Emitted on every state change, for the HUD and for the verifier.
signal state_changed(state: State)

enum State { DORMANT, HUNTING, CHASING }

## Names in enum order, so the HUD never has to hold a second copy of the list.
const STATE_NAMES: Array[String] = ["dormant", "hunting", "chasing"]

@export_group("Wiring")
@export var crawler: CrawlerBody
@export var follower: ChaseTargetFollower
@export var contact: CreatureContact
@export var quarry_of: ChaseTarget

## Live-tunable, pushed in from the prototype root.
var spawn_chance_per_second := CoreLoopKnobs.SPAWN_CHANCE_PER_SECOND
var chase_trigger_radius := CoreLoopKnobs.CHASE_TRIGGER_RADIUS
var chase_duration := CoreLoopKnobs.CHASE_DURATION
var despawn_silence := CoreLoopKnobs.DESPAWN_SILENCE

var _state: State = State.DORMANT
var _suit: Node3D
var _navigation_map: RID

## Seconds since the creature last heard anything, and how much chase is left.
var _silence := 0.0
var _chase_left := 0.0
var _chase_refresh := 0.0

## Where the last heard noise was and how loud, for the HUD.
var _heard_position := Vector3.ZERO
var _heard_radius := 0.0

## How far the last spawn was from the noise that caused it, along the navmesh.
## Reported rather than asserted - it is the number that says whether "one or two
## tunnels away" is what the filter actually produces.
var _last_spawn_path_length := 0.0


func _ready() -> void:
	_set_active(false)


func _physics_process(delta: float) -> void:
	if _suit == null:
		return
	match _state:
		State.HUNTING:
			_run_hunting(delta)
		State.CHASING:
			_run_chasing(delta)
		_:
			pass


func bind(suit: Node3D, navigation_map: RID) -> void:
	_suit = suit
	_navigation_map = navigation_map
	if contact != null and not contact.caught.is_connected(_on_caught):
		contact.caught.connect(_on_caught)


## The only way in. Everything that makes a sound ends up here.
func hear(position: Vector3, radius: float) -> void:
	if not CoreLoopKnobs.MONSTER_ENABLED or _suit == null:
		return
	_heard_position = position
	_heard_radius = radius

	if _state == State.DORMANT:
		_consider_waking(position, radius)
		return

	# Deaf past the radius the noise carries. This is what makes moving away
	# useful even while you are still making noise: a drill at 60 m is heard from
	# anywhere in the network, footsteps at 12 m are not.
	if crawler.global_position.distance_to(position) > radius:
		return

	_silence = 0.0
	if _state == State.HUNTING:
		global_position = position
		if crawler.global_position.distance_to(_suit.global_position) <= chase_trigger_radius:
			_enter(State.CHASING)
	else:
		# Already chasing. Any noise inside the trigger radius buys it more time,
		# which is why going quiet is the only thing that ends a chase.
		if crawler.global_position.distance_to(_suit.global_position) <= chase_trigger_radius:
			_chase_left = chase_duration


func get_state() -> State:
	return _state


func state_name() -> String:
	return STATE_NAMES[_state]


func is_spawned() -> bool:
	return _state != State.DORMANT


## Everything the HUD's monster block prints. One call, so the readout cannot show
## a state from one frame next to a timer from another.
func debug_state() -> Dictionary:
	var distance := 0.0
	if _suit != null and _state != State.DORMANT:
		distance = crawler.global_position.distance_to(_suit.global_position)
	return {
		"state": state_name(),
		"distance": distance,
		"chase_left": _chase_left,
		"silence": _silence,
		"heard_radius": _heard_radius,
		"heard_position": _heard_position,
		"spawn_path": _last_spawn_path_length,
	}


## Puts it away, wherever it is. The reset key and the verifier both need this.
func despawn() -> void:
	if _state == State.DORMANT:
		return
	_enter(State.DORMANT)


## Wakes it deliberately at the best spawn point for a noise. Returns whether it
## found one. The verifier drives the state machine through this rather than
## waiting on a dice roll.
func force_spawn(noise_position: Vector3) -> bool:
	var chosen := _pick_spawn_point(noise_position)
	if chosen.is_empty():
		return false
	_last_spawn_path_length = chosen["path_length"]
	_place_creature(chosen["point"])
	global_position = noise_position
	_enter(State.HUNTING)
	return true


func _run_hunting(delta: float) -> void:
	_silence += delta
	if _silence >= despawn_silence:
		despawn()


func _run_chasing(delta: float) -> void:
	_chase_left -= delta
	if _chase_left <= 0.0:
		# The marker stays where the player last was rather than snapping back to
		# the creature. Losing you should leave it searching your last position,
		# not standing still.
		_enter(State.HUNTING)
		return

	_chase_refresh -= delta
	if _chase_refresh <= 0.0:
		_chase_refresh = CoreLoopKnobs.CHASE_REFRESH_INTERVAL
		global_position = _suit.global_position


## Rolls for a spawn against a noise loud enough to be worth waking for.
##
## The chance is per SECOND and the roll happens per noise tick, so it is scaled
## by the tick length - otherwise shortening the tick would silently make the
## creature commoner without any number changing.
func _consider_waking(position: Vector3, radius: float) -> void:
	if radius < CoreLoopKnobs.SPAWN_TRIGGER_MIN_RADIUS:
		return
	if randf() >= spawn_chance_per_second * CoreLoopKnobs.NOISE_TICK_INTERVAL:
		return
	force_spawn(position)


## The best place to come from: one or two tunnels off, and never in your lap.
##
## MEASURED ALONG THE NAVMESH, not through the rock. A point can be 15 m away
## across a wall and 80 m away by tunnel, and it is the second number that decides
## whether the creature arriving feels like something walking towards you or like
## something materialising. The straight-line floor is the other half of the same
## thought: a route that doubles back can satisfy the path window while still
## putting it just behind your shoulder.
##
## Returns {} when nothing qualifies, which is a legitimate answer - it means you
## are somewhere the creature has no good approach to, and it stays away.
func _pick_spawn_point(noise_position: Vector3) -> Dictionary:
	if not NavigationServer3D.map_is_active(_navigation_map):
		return {}

	var candidates: Array[Dictionary] = []
	for point: Vector3 in CoreLoopKnobs.MONSTER_SPAWN_POINTS:
		if point.distance_to(_suit.global_position) < CoreLoopKnobs.SPAWN_MIN_PLAYER_DISTANCE:
			continue
		var length := _path_length(point, noise_position)
		if length < CoreLoopKnobs.SPAWN_MIN_PATH or length > CoreLoopKnobs.SPAWN_MAX_PATH:
			continue
		candidates.append({"point": point, "path_length": length})

	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]


## Metres along the navmesh between two points, or INF when they do not connect.
##
## NavigationServer answers an unreachable query with a partial path to the
## nearest polygon it CAN reach rather than with a failure, so the last corner is
## checked. Without that, a spawn point on the far side of a break would report a
## short path and the creature would set off for somewhere it can never arrive.
func _path_length(from: Vector3, to: Vector3) -> float:
	var corners := NavigationServer3D.map_get_path(_navigation_map, from, to, true)
	if corners.size() < 2:
		return INF
	if corners[corners.size() - 1].distance_to(to) > CoreLoopKnobs.NAVMESH_CELL * 2.0:
		return INF
	var total := 0.0
	for index: int in range(1, corners.size()):
		total += corners[index - 1].distance_to(corners[index])
	return total


func _place_creature(point: Vector3) -> void:
	# teleport() rather than writing global_position: CrawlerBody integrates its
	# own velocity from a cached position, so a creature moved the other way
	# spends the first second swimming back to where it thought it was.
	crawler.teleport(point)
	follower.teleport(point)


func _enter(state: State) -> void:
	if _state == state:
		return
	_state = state
	_silence = 0.0
	_chase_left = chase_duration if state == State.CHASING else 0.0
	_chase_refresh = 0.0
	_set_active(state != State.DORMANT)
	state_changed.emit(state)


## Whether the creature is in the world.
##
## Parked far outside the network when it is not, rather than left where it stood.
## A disabled node still owns its collision shapes, and the catch sphere is 8.5 m
## across - leaving it in a corridor would put an invisible trigger in a tunnel
## you are about to fly down.
func _set_active(active: bool) -> void:
	if crawler == null or follower == null:
		return
	if not active:
		crawler.teleport(CoreLoopKnobs.CREATURE_DORMANT_POSITION)
		follower.teleport(CoreLoopKnobs.CREATURE_DORMANT_POSITION)

	crawler.visible = active
	crawler.process_mode = PROCESS_MODE_INHERIT if active else PROCESS_MODE_DISABLED
	follower.process_mode = PROCESS_MODE_INHERIT if active else PROCESS_MODE_DISABLED
	# Only ever true once the navmesh is live; the root owns that gate and clears
	# this again on despawn.
	follower.enabled = active and quarry_of != null
	if contact != null:
		contact.process_mode = PROCESS_MODE_INHERIT if active else PROCESS_MODE_DISABLED
		contact.armed = active


## Being touched is not a death in this prototype - it is the creature getting a
## proper look at you. CATCH_IS_LETHAL is the knob that changes its mind.
func _on_caught(_body: Node3D) -> void:
	if _state == State.DORMANT:
		return
	_enter(State.CHASING)
	_chase_left = chase_duration
