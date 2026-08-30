extends Node

## End-to-end check that health and the three hazard prefabs survive a real scene
## instantiation and actually bill the player.
##
##     godot --headless --path . res://tests/verify_hazards.tscn
##
## Not an McpTestSuite and deliberately outside `test_*`: every case here has to await
## physics frames, and the runner calls tests synchronously. Same split as
## verify_player_sfx.gd.

const PLAYER_SCENE := preload("res://prefabs/character/player/prefab_player.tscn")
const GAS_POD_SCENE := preload("res://prefabs/environment/hazards/prefab_gas_pod.tscn")
const ARC_SCENE := preload("res://prefabs/environment/hazards/prefab_arc_hazard.tscn")
const BLOCKAGE_SCENE := preload("res://prefabs/environment/hazards/prefab_blockage.tscn")

## Comfortably over the deadband and at the reference speed, so the figure is exact.
const REFERENCE_IMPACT := -8.0

var _failures: PackedStringArray = []


func _ready() -> void:
	await _verify_health()
	await _verify_gas_pod()
	await _verify_gas_pod_proximity()
	await _verify_gas_pod_contact()
	await _verify_arc()
	await _verify_blockage()
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	if _failures.is_empty():
		print("\nverify_hazards: all checks passed")
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(passed: bool, what: String) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures.append(what)


## A player parked far from anything, with its own physics ticking.
func _spawn_player(at: Vector3) -> Node3D:
	var player := PLAYER_SCENE.instantiate() as Node3D
	add_child(player)
	var body := player.get_node("PlayerBody") as Node3D
	body.global_position = at
	await get_tree().physics_frame
	await get_tree().physics_frame
	return player


func _verify_health() -> void:
	var player := await _spawn_player(Vector3(0.0, 0.0, 0.0))
	var body := player.get_node("PlayerBody")
	var health: PlayerHealth = body.get_node("Health")
	var life: PlayerLife = body.get_node("Life")
	var oxygen: PlayerOxygen = body.get_node("Oxygen")
	var collision: PlayerCollisionResponse = body.get_node("CollisionResponse")
	var state: HudState = body.get_node("UI/HudBinding/HudState")

	check(health.settings != null, "Health resolves its settings from the prefab")
	check(health.health == health.settings.max_health, "the suit starts intact")
	check(is_equal_approx(state.health, 1.0), "and the HUD was told so")

	# The wiring, not the arithmetic: the model is unit-tested in test_player_health.gd.
	collision.impacted.emit(REFERENCE_IMPACT, body.global_position)
	var expected := health.settings.max_health - health.settings.impact_damage_at_reference_speed
	check(is_equal_approx(health.health, expected), "a reference impact bills the pool")
	check(state.health < 1.0, "and the HUD followed it down")

	var flashed := [false]
	state.damaged.connect(func(_severity: float) -> void: flashed[0] = true)
	collision.impacted.emit(REFERENCE_IMPACT, body.global_position)
	check(flashed[0], "a blow reaches HudState.damaged, which is what flashes the overlay")

	# A scrape is not a hit.
	var before := health.health
	collision.impacted.emit(-0.5, body.global_position)
	check(health.health == before, "a scrape under the deadband costs nothing")

	# Suffocation drains rather than killing outright, which is the whole point of §1.
	var died := [false]
	life.died.connect(func() -> void: died[0] = true)
	oxygen.oxygen = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not died[0], "an empty tank does not kill on the frame it empties")
	check(health.health < before, "it bleeds instead")

	health.take_damage(health.settings.max_health, PlayerHealth.Source.UNKNOWN)
	await get_tree().physics_frame
	check(died[0], "an empty pool is still what kills you")

	player.queue_free()
	await get_tree().physics_frame


func _verify_gas_pod() -> void:
	var player := await _spawn_player(Vector3(200.0, 0.0, 0.0))
	var body := player.get_node("PlayerBody") as CharacterBody3D
	var health: PlayerHealth = body.get_node("Health")

	var pod := GAS_POD_SCENE.instantiate() as GasPod
	add_child(pod)
	# Well outside the proximity ring, so the cut is what sets this one off.
	pod.global_position = body.global_position + Vector3(0.0, 0.0, 3.0)
	pod.cut_fuse_seconds = 0.0
	await get_tree().physics_frame

	# The group is how AsteroidLevel._wire_hazard_noise finds it; without it the pod
	# still detonates and the creature simply never hears a thing.
	check(pod.is_in_group(HazardDamage.NOISE_GROUP), "a pod joins the world-noise group")
	check(not pod.any_trigger_in_proximity, "and it is quiet with nobody near it")

	var heard := [Vector3.ZERO, 0.0]
	pod.world_noise.connect(
		func(at: Vector3, loudness: float) -> void:
			heard[0] = at
			heard[1] = loudness
	)
	var before := health.health
	var speed := body.velocity

	pod.take_mining_damage(pod.pod_health, pod.global_position, null)
	await get_tree().physics_frame
	await get_tree().physics_frame

	check(health.health < before, "a cut pod bills anyone standing next to it")
	check(heard[1] > 1.0, "and it is louder than the beam that lit it")
	check(heard[0].is_equal_approx(pod.global_position), "from where the pod was, not the player")
	check(body.velocity != speed, "and it shoves you")

	player.queue_free()
	await get_tree().physics_frame


## A bare body on the player layer and in the player group. Enough to drive an Area3D,
## and far cheaper than a second whole suit when what is under test is the bookkeeping.
func _make_probe_body(at: Vector3) -> CharacterBody3D:
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 0
	probe.add_to_group(HazardDamage.PLAYER_GROUP)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	probe.add_child(shape)
	add_child(probe)
	probe.global_position = at
	return probe


func _verify_gas_pod_proximity() -> void:
	var pod := GAS_POD_SCENE.instantiate() as GasPod
	add_child(pod)
	pod.global_position = Vector3(600.0, 0.0, 0.0)
	pod.proximity_fuse_seconds = 2.0
	await get_tree().physics_frame

	var gone := [false]
	pod.detonated.connect(func(_at: Vector3) -> void: gone[0] = true)

	# Standing off, well outside the ring.
	var first := _make_probe_body(pod.global_position + Vector3(0.0, 0.0, 4.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not pod.any_trigger_in_proximity, "standing off leaves the pod alone")

	# Step inside it.
	first.global_position = pod.global_position + Vector3(0.0, 0.0, 1.05)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(pod.any_trigger_in_proximity, "getting too close starts the countdown")
	await get_tree().create_timer(0.5).timeout
	check(not gone[0], "which is a warning, not an ambush")
	check(pod.arming_progress() > 0.0, "and it is visibly winding up")

	# A second suit arrives, then the first one backs off. THE POD MUST STAY ARMED.
	var second := _make_probe_body(pod.global_position + Vector3(0.0, 0.0, 1.05))
	await get_tree().physics_frame
	await get_tree().physics_frame
	first.global_position = pod.global_position + Vector3(0.0, 0.0, 6.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(pod.any_trigger_in_proximity, "one of two leaving does not call the all-clear")

	# Now the second one leaves too.
	second.global_position = pod.global_position + Vector3(0.0, 0.0, 6.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not pod.any_trigger_in_proximity, "the last one leaving does")
	check(pod.arming_progress() == 0.0, "and the countdown goes back to the start")

	# Stay put and it goes.
	second.global_position = pod.global_position + Vector3(0.0, 0.0, 1.05)
	await get_tree().physics_frame
	await get_tree().create_timer(pod.proximity_fuse_seconds + 0.3).timeout
	check(gone[0], "lingering past the fuse sets it off")

	first.queue_free()
	second.queue_free()
	await get_tree().physics_frame


func _verify_gas_pod_contact() -> void:
	var pod := GAS_POD_SCENE.instantiate() as GasPod
	add_child(pod)
	pod.global_position = Vector3(800.0, 0.0, 0.0)
	await get_tree().physics_frame

	var gone := [false]
	pod.detonated.connect(func(_at: Vector3) -> void: gone[0] = true)

	# Straight onto it, with no time spent in the ring first.
	var probe := _make_probe_body(pod.global_position + Vector3(0.0, 0.0, 0.1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(gone[0], "touching one sets it off with no countdown at all")

	probe.queue_free()
	await get_tree().physics_frame


func _verify_arc() -> void:
	var player := await _spawn_player(Vector3(400.0, 0.0, 0.0))
	var body := player.get_node("PlayerBody") as Node3D
	var power: PlayerPowerClient = body.get_node("PowerClient")
	var state: HudState = body.get_node("UI/HudBinding/HudState")

	var arc := ARC_SCENE.instantiate() as ArcHazard
	add_child(arc)
	arc.global_position = body.global_position
	await get_tree().physics_frame

	var charge_before := power.charge
	await get_tree().process_frame
	await get_tree().process_frame
	check(power.charge < charge_before, "standing in an arc drains the suit")
	# The damage is small on purpose, so this is the only thing that tells the player
	# an arc has them. Without it the arc is silent and invisible from the inside.
	check(state.electrified, "and the helmet is told it is being held")

	# Well outside field_radius: the arc costs nothing when nobody is in it.
	body.global_position += Vector3(0.0, 0.0, 50.0)
	await get_tree().process_frame
	var charge_away := power.charge
	await get_tree().process_frame
	await get_tree().process_frame
	var drained_away := charge_away - power.charge
	# PowerClient's own idle drain keeps running, so this is a comparison, not a zero.
	check(drained_away < (charge_before - power.charge) * 0.5, "and stops once you leave it")
	# Past PlayerHealth.ELECTRIFIED_HOLD, so the latch has had time to lapse.
	await get_tree().create_timer(0.4).timeout
	check(not state.electrified, "and the crackle lets go with it")

	player.queue_free()
	await get_tree().physics_frame


func _verify_blockage() -> void:
	var blockage := BLOCKAGE_SCENE.instantiate() as Blockage
	add_child(blockage)
	await get_tree().physics_frame

	var opened := [false]
	var heard := [0.0]
	blockage.cleared.connect(func() -> void: opened[0] = true)
	blockage.world_noise.connect(func(_at: Vector3, loudness: float) -> void: heard[0] = loudness)

	blockage.take_mining_damage(blockage.blockage_health * 0.5, Vector3.ZERO, null)
	await get_tree().physics_frame
	check(not opened[0], "half a plug is still a plug")
	check(is_equal_approx(blockage.progress(), 0.5), "and it says how far through you are")

	blockage.take_mining_damage(blockage.blockage_health, Vector3.ZERO, null)
	await get_tree().physics_frame
	check(opened[0], "a finished cut opens the route")
	check(heard[0] > 1.0, "and the collapse is loud")
