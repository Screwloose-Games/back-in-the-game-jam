extends Node

## End-to-end check that a clinger survives a real scene: seats itself on rock, hears the
## player, crawls, leaps, latches, bills the suit, sheds, and dies to the beam.
##
##     godot --headless --path . res://tests/verify_clinger.tscn
##
## As a SCENE, never `--script`: a node added during SceneTree._initialize() never receives
## _ready(), so the bare-script form runs nothing, prints nothing and exits 0 -- which looks
## exactly like a pass. Not an McpTestSuite and deliberately outside `test_*` because every
## case here awaits physics frames and the runner calls tests synchronously. Same split as
## verify_hazards.gd.

const CLINGER_SCENE := preload("res://prefabs/character/clinger/prefab_clinger.tscn")
const PLAYER_SCENE := preload("res://prefabs/character/player/prefab_player.tscn")

## A room big enough that a crawl has somewhere to go and the far walls are out of reach.
const ROOM := Vector3(16.0, 8.0, 16.0)
const WALL := 0.5

## Layer 1, `hull`, which is the only thing the clinger's probe looks for.
const HULL_LAYER := 1

## prefab_mineral_chunk.tscn's BoxShape3D, to the centimetre. The chunk itself is on `ore`
## now, but anything this size on layer 1 -- a blockage, a shaft rib, a fold of the cave --
## is the same unnavigable island, and that is what the escape leap is really for.
const CHUNK := Vector3(1.2, 2.6, 1.2)

## Two stuck windows at the shipped 3 s, plus the crossing, plus slack. Not open-ended: a
## case that passes only because it waited long enough is not a pass.
const ESCAPE_FRAMES := 900

## Past the corner of the box with room to spare, so a clinger that merely slid off it does
## not count as having escaped it.
const ESCAPE_DISTANCE := 5.0

var _failures: PackedStringArray = []
var _leaps := 0
var _escapes := 0
var _attaches := 0
var _sheds := 0
var _deaths := 0
var _noises := 0

@onready var _settings: PlayerSettings = load("res://prefabs/character/player/player_settings.tres")


func _ready() -> void:
	await _verify_seating()
	await _verify_hearing()
	await _verify_crawl()
	await _verify_leap_and_grip()
	await _verify_struggle()
	await _verify_drains()
	await _verify_reattack()
	await _verify_a_leap_that_misses()
	await _verify_release_on_death()
	await _verify_mining_death()
	await _verify_escape_from_a_surface_too_small_to_crawl()
	await _verify_a_healthy_crawl_is_left_alone()
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	if _failures.is_empty():
		print("\nverify_clinger: all checks passed")
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(passed: bool, what: String) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures.append(what)


# ----- fixture --------------------------------------------------------------------------


## A sealed box on layer 1, centred on `at`, so every case gets an uncontaminated room.
func _room(at: Vector3) -> StaticBody3D:
	var room := StaticBody3D.new()
	room.collision_layer = HULL_LAYER
	room.collision_mask = 0
	add_child(room)
	room.global_position = at
	var half := ROOM * 0.5
	var faces: Array = [
		[Vector3(0, -half.y, 0), Vector3(ROOM.x, WALL, ROOM.z)],
		[Vector3(0, half.y, 0), Vector3(ROOM.x, WALL, ROOM.z)],
		[Vector3(-half.x, 0, 0), Vector3(WALL, ROOM.y, ROOM.z)],
		[Vector3(half.x, 0, 0), Vector3(WALL, ROOM.y, ROOM.z)],
		[Vector3(0, 0, -half.z), Vector3(ROOM.x, ROOM.y, WALL)],
		[Vector3(0, 0, half.z), Vector3(ROOM.x, ROOM.y, WALL)],
	]
	for face: Array in faces:
		var shape := BoxShape3D.new()
		shape.size = face[1]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		room.add_child(collider)
		collider.position = face[0]
	return room


func _spawn_clinger(at: Vector3, dormant := true) -> Clinger:
	var clinger := CLINGER_SCENE.instantiate() as Clinger
	clinger.starts_dormant = dormant
	# Placed BEFORE it enters the tree, the way AsteroidLevel places the stalker: _ready
	# snapshots the pose it arrives with, and the crawl integrator writes that back over
	# anything assigned afterwards.
	clinger.position = at
	add_child(clinger)
	clinger.state_changed.connect(_on_state_changed)
	clinger.attached.connect(_on_attached)
	clinger.shed.connect(_on_shed)
	clinger.died.connect(_on_died)
	clinger.world_noise.connect(_on_world_noise)
	_leaps = 0
	_escapes = 0
	_attaches = 0
	_sheds = 0
	_deaths = 0
	_noises = 0
	await _step(2)
	return clinger


func _spawn_player(at: Vector3) -> Node3D:
	var player := PLAYER_SCENE.instantiate() as Node3D
	add_child(player)
	var body := player.get_node("PlayerBody") as Node3D
	body.global_position = at
	await _step(2)
	return body


## Drives a woken clinger onto the player's face, or reports why it could not.
func _latch(clinger: Clinger, body: Node3D) -> bool:
	clinger.wake(body.global_position)
	await _step(120)
	return clinger.debug_state()["phase"] == "ATTACHED"


func _step(frames: int) -> void:
	for _frame: int in frames:
		await get_tree().physics_frame


## How far a point is from the nearest inner face of a room centred on `centre`.
func _depth_in(at: Vector3, centre: Vector3) -> float:
	var local := at - centre
	var half := ROOM * 0.5 - Vector3.ONE * (WALL * 0.5)
	return minf(minf(half.x - absf(local.x), half.y - absf(local.y)), half.z - absf(local.z))


## A box the size of a mineral chunk, on layer 1, for a clinger to get marooned on.
func _pillar(at: Vector3) -> StaticBody3D:
	var pillar := StaticBody3D.new()
	pillar.collision_layer = HULL_LAYER
	pillar.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = CHUNK
	var collider := CollisionShape3D.new()
	collider.shape = shape
	pillar.add_child(collider)
	add_child(pillar)
	pillar.global_position = at
	return pillar


## THE CASE THE WHOLE FEATURE EXISTS FOR. Seated on a face 1.2 m across, `_step` runs off an
## edge every few frames and turns EDGE_TURN_DEGREES to find a new heading, so the creature
## spends the rest of the run walking a square instead of going where it was sent.
func _verify_escape_from_a_surface_too_small_to_crawl() -> void:
	print("\nescaping a surface too small to crawl")
	var centre := Vector3(2000, 0, 0)
	_room(centre)
	_pillar(centre)
	var clinger := await _spawn_clinger(centre + Vector3(0, CHUNK.y * 0.5 + 0.11, 0), false)
	await _step(30)
	check(
		clinger.global_position.distance_to(centre) < 2.0,
		"it seated on the box rather than falling off it before the case began"
	)
	# Sent somewhere it cannot walk to, which is what makes it keep trying and keep turning.
	clinger.wake(centre + Vector3(0.0, 0.0, 7.0))
	var escaped := false
	for _frame: int in ESCAPE_FRAMES:
		await get_tree().physics_frame
		if clinger.global_position.distance_to(centre) > ESCAPE_DISTANCE:
			escaped = true
			break
	var state := clinger.debug_state()
	var stuck: Dictionary = state["stuck"]
	check(escaped, "it got clear of the box within %d frames" % ESCAPE_FRAMES)
	check(int(stuck["trips"]) > 0, "the stuck detector is what noticed, not luck")
	check(_escapes > 0, "it left by leaping rather than by sliding off")
	await _step(60)
	check(
		absf(_depth_in(clinger.global_position, centre) - clinger.debug_state()["lift"]) < 0.2,
		"it landed on a wall and gripped it rather than drifting"
	)
	clinger.queue_free()
	await _step(2)


## THE NEGATIVE, AND IT IS THE ONE THAT FAILS SILENTLY. A detector that fires on a healthy
## crawl sends the creature across the room for no reason -- which in a playtest is
## indistinguishable from the feature working, because a clinger leaping somewhere is
## exactly what this looks like when it is right.
func _verify_a_healthy_crawl_is_left_alone() -> void:
	print("\na healthy crawl is left alone")
	var centre := Vector3(2200, 0, 0)
	_room(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-7.0, 0.0, 0.0), false)
	await _step(30)
	clinger.wake(centre + Vector3(-7.0, 0.0, 6.0))
	await _step(600)
	var stuck: Dictionary = clinger.debug_state()["stuck"]
	check(int(stuck["trips"]) == 0, "ten seconds of ordinary crawling was never called stuck")
	check(_escapes == 0, "it stayed on the wall instead of leaping off a perfectly good one")
	clinger.queue_free()
	await _step(2)


func _on_state_changed(phase: ClingerState.Phase) -> void:
	if phase == ClingerState.Phase.LEAPING:
		_leaps += 1
	elif phase == ClingerState.Phase.SURFACE_LEAPING:
		_escapes += 1


func _on_attached(_victim: Node3D) -> void:
	_attaches += 1


func _on_shed(_victim: Node3D) -> void:
	_sheds += 1


func _on_died(_at: Vector3) -> void:
	_deaths += 1


func _on_world_noise(_at: Vector3, _loudness: float) -> void:
	_noises += 1


# ----- cases ----------------------------------------------------------------------------


func _verify_seating() -> void:
	print("\nseating")
	var centre := Vector3.ZERO
	_room(centre)
	# Dropped in mid-air with nothing under it: the fourteen-ray fan is the only thing that
	# can find it a wall, and without it a loosely placed clinger never grips anything.
	var clinger := await _spawn_clinger(centre + Vector3(0, 0, 3.0))
	await _step(120)
	var depth := _depth_in(clinger.global_position, centre)
	check(depth < 0.5, "reaches a wall from open space (%.2f m clear)" % depth)
	check(
		absf(depth - (clinger.debug_state()["lift"] as float)) < 0.08,
		(
			"rides its own lift off the rock (%.3f m against %.3f m)"
			% [depth, clinger.debug_state()["lift"]]
		)
	)
	check(
		clinger.global_transform.basis.determinant() > 0.0,
		"holds a right-handed pose, so the shell is not rendered inside out"
	)
	check(clinger.is_in_group(HazardDamage.NOISE_GROUP), "joins the world-noise group")
	check(clinger.debug_state()["phase"] == "DORMANT", "starts dormant when told to")
	clinger.queue_free()


func _verify_hearing() -> void:
	print("\nhearing")
	var centre := Vector3(200, 0, 0)
	_room(centre)
	var clinger := await _spawn_clinger(centre)
	# Added AFTER the clinger, which is the case that matters: a level spawns its player
	# well after a placed creature has readied, so the tree hook is the only thing that
	# binds them. Nothing here is type-checked -- the ears duck-type on the signal.
	var emitter := StandInEmitter.new()
	add_child(emitter)
	await _step(2)

	emitter.announce(_settings.clinger_wake_strength - 0.5, centre + Vector3(2, 0, 0))
	await _step(6)
	check(
		clinger.debug_state()["phase"] == "DORMANT",
		"a noise under clinger_wake_strength leaves it dormant"
	)

	emitter.announce(8.0, centre + Vector3(2, 0, 0))
	await _step(6)
	check(clinger.debug_state()["phase"] == "CRAWLING", "a loud noise wakes it")

	# Far enough that neither the noise's own radius nor the ear reaches it.
	var far_off := centre + Vector3(0, 0, 400)
	emitter.announce(8.0, far_off)
	await _step(6)
	check(
		(clinger.debug_state()["noise_at"] as Vector3).distance_to(far_off) > 1.0,
		"a noise past clinger_hearing_range is never chased"
	)
	clinger.queue_free()
	emitter.queue_free()


func _verify_crawl() -> void:
	print("\ncrawl")
	var centre := Vector3(400, 0, 0)
	_room(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-7.0, 0, 0), false)
	await _step(40)
	var goal := centre + Vector3(-7.0, 0, 6.0)
	clinger.wake(goal)
	var before := clinger.global_position.distance_to(goal)
	await _step(150)
	var after := clinger.global_position.distance_to(goal)
	check(after < before - 0.5, "closes on what it heard (%.2f m -> %.2f m)" % [before, after])
	var depth := _depth_in(clinger.global_position, centre)
	check(depth < 0.5, "stays on the rock the whole way (%.2f m clear)" % depth)
	# Nothing has made a noise for longer than clinger_forget_seconds by now.
	await _step(int(_settings.clinger_forget_seconds * 60.0) + 60)
	check(clinger.debug_state()["phase"] == "DORMANT", "goes quiet again once the noise is stale")
	clinger.queue_free()


func _verify_leap_and_grip() -> void:
	print("\nleap")
	var centre := Vector3(600, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-2.5, 0, 0), false)
	var latched: bool = await _latch(clinger, body)
	check(_leaps >= 1, "leaps at a suit inside clinger_jump_range")
	check(_attaches == 1, "one contact anywhere on the suit is one grip")
	check(_noises >= 1, "the leap is something the stalker could hear")
	check(latched, "and it stays on the face")
	check(clinger.collision_layer == 0, "goes off every layer, so the beam cannot reach it")

	var camera := HazardDamage.head_of(body).get_node("HeadCamera") as Camera3D
	var nearest := INF
	for child: Node in clinger.get_node("sm_clinger").get_children():
		var mesh := child as VisualInstance3D
		if mesh == null:
			continue
		check(
			mesh.layers == PlayerRenderLayers.own_tool_mask(),
			"%s is off the helmet lamp's shadow casters" % mesh.name
		)
		for corner: int in 8:
			var at: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
			nearest = minf(nearest, camera.global_position.distance_to(at))
	check(
		nearest > _settings.camera_near * 3.0,
		"clears the near plane with room (%.3f m against %.3f m)" % [nearest, _settings.camera_near]
	)
	var input := HazardDamage.input_of(body)
	check(input.struggle_listening, "puts the suit's input into struggle mode")
	check(input.enabled, "and leaves the player flying -- thrust still works while worn")
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


func _verify_struggle() -> void:
	print("\nstruggle")
	var centre := Vector3(800, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-2.5, 0, 0), false)
	if not await _latch(clinger, body):
		check(false, "the struggle case needs an attached clinger; it never latched")
		return
	var input := HazardDamage.input_of(body)

	for _press: int in _settings.clinger_interaction_count - 1:
		input.struggled.emit()
	await _step(4)
	check(_sheds == 0, "one press short of the count does not shed it")
	check(clinger.debug_state()["phase"] == "ATTACHED", "and it is still on the face")
	var peel: float = clinger.debug_state()["grip"]["wanted_peel"]
	check(peel > 0.5 and peel < 1.0, "the peel is part open, so the meter is the creature")

	input.struggled.emit()
	await _step(10)
	check(_sheds == 1, "the last press sheds it")
	check(clinger.debug_state()["phase"] == "ORBITING", "and it circles rather than leaving")
	check(clinger.collision_layer == Clinger.CREATURE_LAYER, "back on the creature layer")
	check(not input.struggle_listening, "and it hands the input back")
	check(
		clinger.debug_state()["cooldown_left"] > 0.0,
		"a shed clinger cannot re-attack until the cooldown clears"
	)
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


func _verify_drains() -> void:
	print("\ndrains")
	var centre := Vector3(1000, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-2.5, 0, 0), false)
	if not await _latch(clinger, body):
		check(false, "the drain case needs an attached clinger; it never latched")
		return
	var health := HazardDamage.health_of(body)
	var oxygen := HazardDamage.oxygen_of(body)
	var power := HazardDamage.power_of(body)
	var health_before := health.health
	var oxygen_before := oxygen.oxygen
	var power_before := power.fraction()
	await _step(60)
	check(health.health < health_before, "bills health")
	check(oxygen.oxygen < oxygen_before, "bills the tank")
	check(power.fraction() < power_before, "bills the battery")
	# About a second of ticks. Generous bounds on purpose: the point is that the rate is
	# the settings figure rather than some multiple of it.
	var spent := health_before - health.health
	check(
		(
			spent > _settings.clinger_health_drain_per_second * 0.5
			and spent < _settings.clinger_health_drain_per_second * 2.0
		),
		"at about clinger_health_drain_per_second (%.2f points)" % spent
	)
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


## Requirement nine: a shed clinger circles you until it can attack again. The circle is
## deliberately inside leap range, so "can attack again" is purely the cooldown.
func _verify_reattack() -> void:
	print("\nre-attack after a shed")
	var centre := Vector3(1600, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-2.5, 0, 0), false)
	if not await _latch(clinger, body):
		check(false, "the re-attack case needs an attached clinger; it never latched")
		return
	var input := HazardDamage.input_of(body)
	for _press: int in _settings.clinger_interaction_count:
		input.struggled.emit()
	await _step(4)
	var leaps_when_shed := _leaps
	check(clinger.debug_state()["phase"] == "ORBITING", "it circles once shed")

	# Half the cooldown: still circling, and that is the point of the cooldown.
	await _step(int(_settings.clinger_attack_cooldown * 30.0))
	check(_leaps == leaps_when_shed, "it does not re-attack while the cooldown is live")
	check(
		clinger.global_position.distance_to(body.global_position) < _settings.clinger_hearing_range,
		"and it stays with you rather than wandering off"
	)

	await _step(int(_settings.clinger_attack_cooldown * 60.0) + 90)
	check(_leaps > leaps_when_shed, "and attacks again once clinger_attack_cooldown clears")
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


## Requirement four's other half: a leap can miss, and a miss ends on whatever it hit.
func _verify_a_leap_that_misses() -> void:
	print("\na leap that misses")
	var centre := Vector3(1800, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-3.5, 0, 0), false)
	clinger.wake(body.global_position)
	var launched := false
	for _frame: int in 180:
		await get_tree().physics_frame
		if clinger.debug_state()["phase"] == "LEAPING":
			launched = true
			break
	check(launched, "it launches")
	# Out of the way mid-flight. The leap is ballistic and committed, so it flies past and
	# into the far wall -- which is where it has to end up gripping.
	body.global_position = centre + Vector3(0, 6.0, 0)
	await _step(120)
	check(clinger.debug_state()["phase"] != "LEAPING", "a leap that hits nothing still ends")
	check(clinger.debug_state()["phase"] != "ATTACHED", "and a miss is not a grip")
	var depth := _depth_in(clinger.global_position, centre)
	check(
		absf(depth - (clinger.debug_state()["lift"] as float)) < 0.15,
		"it grips the surface it hit instead (%.3f m clear)" % depth
	)
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


func _verify_release_on_death() -> void:
	print("\ndeath and respawn while worn")
	var centre := Vector3(1200, 0, 0)
	_room(centre)
	var body := await _spawn_player(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-2.5, 0, 0), false)
	if not await _latch(clinger, body):
		check(false, "the release case needs an attached clinger; it never latched")
		return
	var input := HazardDamage.input_of(body)
	(body.get_node("Life") as PlayerLife).die()
	await _step(6)
	check(not input.struggle_listening, "dying lets go of the suit's input")
	check(clinger.debug_state()["phase"] == "ORBITING", "and the creature stops riding it")
	# THE TRAP THIS CASE EXISTS FOR. PlayerInput.enabled's setter is `value and not locked`,
	# so anything still holding the suit when _revive() runs swallows the revive in silence
	# and the player spectates for the rest of the session.
	await _step(int(PlayerLife.RESPAWN_DELAY * 60.0) + 40)
	check(input.enabled, "and the revive is not swallowed")
	check(not input.locked, "with nothing left holding the suit locked")
	clinger.queue_free()
	body.get_parent().queue_free()
	await _step(2)


func _verify_mining_death() -> void:
	print("\nthe beam")
	var centre := Vector3(1400, 0, 0)
	_room(centre)
	var clinger := await _spawn_clinger(centre + Vector3(-7.0, 0, 0), false)
	await _step(30)
	var third := _settings.clinger_hp / 3.0

	# Spread over separate frames with gaps in between: it has to integrate what the beam
	# has landed, not treat one call as one hit and not reset between them.
	clinger.take_mining_damage(third, clinger.global_position, null)
	await _step(8)
	check(_deaths == 0, "a third of its hit points does not kill it")
	clinger.take_mining_damage(third, clinger.global_position, null)
	await _step(8)
	check(_deaths == 0, "and neither does two thirds")
	check(clinger.debug_state()["phase"] != "DEAD", "it is still alive to be finished off")
	clinger.take_mining_damage(third + 0.01, clinger.global_position, null)
	await _step(4)
	check(_deaths == 1, "clinger_hp of beam kills it")
	check(clinger.debug_state()["phase"] == "DEAD", "and it reads as dead")
	check(clinger.collision_layer == 0, "a corpse is neither an obstacle nor a mining target")

	var was_at := clinger.global_position
	await _step(20)
	check(clinger.global_position.distance_to(was_at) > 0.01, "it lets go of the wall and drifts")
	await _step(int(_settings.clinger_death_despawn_time * 60.0) + 60)
	check(not is_instance_valid(clinger), "and despawns after clinger_death_despawn_time")


## Anything carrying `noise_emitted` drives the ears; nothing is type-checked, which is what
## lets this stand in for a whole player prefab.
class StandInEmitter:
	extends Node

	signal noise_emitted(strength: float, at: Vector3, source: PlayerNoise.Source)

	func announce(strength: float, at: Vector3) -> void:
		noise_emitted.emit(strength, at, PlayerNoise.Source.THRUST)
