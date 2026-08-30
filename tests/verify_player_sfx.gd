extends Node

## End-to-end check that the audio wiring in prefab_player, prefab_alien and
## prefab_life_support_cube survives a real scene instantiation.
##
##     godot --headless --path . res://tests/verify_player_sfx.tscn
##
## Not an McpTestSuite and deliberately outside `test_*`: every case here has to
## await a physics frame, and the runner calls tests synchronously. It is the same
## split as the verify_*.tscn scenes in prototypes/.

## Comfortably past the failure cue, so the revive is what is being observed.
const REVIVE_GRACE := 0.2

## A knock hard enough to clear PlayerSfx.impact_min_speed several times over.
const HARD_KNOCK := -5.0

## Three distinct trims, so a value landing on the wrong channel is visible rather
## than coincidentally right.
const LOOP_TRIM := -6.0
const ON_TRIM := 3.0
const OFF_TRIM := -9.0

var _failures: PackedStringArray = []


func _ready() -> void:
	await _verify_player()
	await _verify_alien()
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	if _failures.is_empty():
		print("\nverify_player_sfx: all checks passed")
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(passed: bool, what: String) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures.append(what)


func _verify_player() -> void:
	var scene: PackedScene = load("res://prefabs/character/player/prefab_player.tscn")
	var player := scene.instantiate()
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var sfx: PlayerSfx = player.get_node("PlayerBody/Sfx")
	var thrusters: PlayerThrusterSfx = player.get_node("PlayerBody/Thrusters")
	var input: PlayerInput = player.get_node("PlayerBody/Input")
	var power: PlayerPowerClient = player.get_node("PlayerBody/PowerClient")
	var state: HudState = player.get_node("PlayerBody/UI/HudBinding/HudState")
	var life: PlayerLife = player.get_node("PlayerBody/Life")
	var collision: PlayerCollisionResponse = player.get_node("PlayerBody/CollisionResponse")
	var grab: PlayerGrab = player.get_node("PlayerBody/Grab")

	# Take the real device out of the loop so thrust can be driven by hand.
	input.enabled = false

	await _verify_thrusters(thrusters, input)
	await _verify_thruster_mix(thrusters, input)

	collision.impacted.emit(HARD_KNOCK, Vector3.ZERO)
	check(sfx.impact_player.stream == sfx.suit_impact_wall, "a hard knock plays the wall impact")
	var loud := sfx.impact_player.volume_db
	collision.impacted.emit(-1.0, Vector3.ZERO)
	check(sfx.impact_player.volume_db < loud, "a softer hit is mixed quieter")

	state.status = HudState.Status.STRAINED
	check(sfx.helmet_player.stream == sfx.status_downgrade, "green to yellow plays the downgrade")
	sfx.helmet_player.stream = null
	state.status = HudState.Status.NOMINAL
	check(sfx.helmet_player.stream == null, "recovering up the scale plays nothing")

	power.spend(power.settings.suit_capacity)
	check(sfx.helmet_player.stream == sfx.helmet_failure, "an empty suit plays the helmet failure")

	var cube_scene: PackedScene = load("res://prefabs/gameplay/prefab_life_support_cube.tscn")
	var cube: LifeSupportCube = cube_scene.instantiate()
	add_child(cube)
	await get_tree().physics_frame
	grab.took_hold.emit(cube)
	check(cube.grab_sfx.playing, "grabbing the cube sounds from the cube")

	life.die()
	check(sfx.impact_player.stream == sfx.death_impact, "dying plays the death impact")
	check(not life.is_alive(), "and the suit is dead")
	await get_tree().create_timer(PlayerLife.RESPAWN_DELAY + REVIVE_GRACE).timeout
	check(life.is_alive(), "and it revives on its own")

	cube.queue_free()
	player.queue_free()
	await get_tree().process_frame


## Each of the eight controls has to light its own emitter, and swapping between
## opposed pairs has to be audible as one stopping and another starting.
func _verify_thrusters(thrusters: PlayerThrusterSfx, input: PlayerInput) -> void:
	const CASES := [
		["thrust forward", "thrust", Vector3.FORWARD, PlayerThrusterSfx.Thruster.FORWARD],
		["thrust back", "thrust", Vector3.BACK, PlayerThrusterSfx.Thruster.BACK],
		["thrust left", "thrust", Vector3.LEFT, PlayerThrusterSfx.Thruster.LEFT],
		["thrust right", "thrust", Vector3.RIGHT, PlayerThrusterSfx.Thruster.RIGHT],
		["thrust up", "thrust", Vector3.UP, PlayerThrusterSfx.Thruster.UP],
		["thrust down", "thrust", Vector3.DOWN, PlayerThrusterSfx.Thruster.DOWN],
		["roll left", "roll", -1.0, PlayerThrusterSfx.Thruster.ROLL_LEFT],
		["roll right", "roll", 1.0, PlayerThrusterSfx.Thruster.ROLL_RIGHT],
	]
	for case: Array in CASES:
		var label: String = case[0]
		var thruster: int = case[3]
		input.thrust = Vector3.ZERO
		input.roll = 0.0
		input.set(case[1], case[2])
		await get_tree().physics_frame
		check(thrusters.is_firing(thruster), "%s lights its own thruster" % label)
		var lit := 0
		for other in PlayerThrusterSfx.THRUSTERS.size():
			if thrusters.is_firing(other):
				lit += 1
		check(lit == 1, "%s lights nothing else" % label)
		var loop := thrusters.get_node(
			NodePath("%sLoop" % PlayerThrusterSfx.THRUSTERS[thruster].name)
		)
		check(loop.playing, "%s sounds from its own emitter" % label)
		# The mount is the reaction side, so it sits opposite the push.
		if case[1] == "thrust":
			var push: Vector3 = case[2]
			check(loop.position.dot(push) < 0.0, "%s is mounted opposite the push" % label)

	input.thrust = Vector3.ZERO
	input.roll = 0.0
	await get_tree().physics_frame

	# The case the single shared emitter could not express at all.
	input.thrust = Vector3.RIGHT
	await get_tree().physics_frame
	var right_at: Vector3 = thrusters.get_node("RightLoop").position
	input.thrust = Vector3.LEFT
	await get_tree().physics_frame
	var left_at: Vector3 = thrusters.get_node("LeftLoop").position
	check(
		not thrusters.is_firing(PlayerThrusterSfx.Thruster.RIGHT),
		"swapping right for left stops the right thruster"
	)
	check(
		thrusters.is_firing(PlayerThrusterSfx.Thruster.LEFT),
		"and starts the left one, which is the sound of changing direction"
	)
	check(right_at.x < 0.0 and left_at.x > 0.0, "and the two are on opposite sides of the helmet")

	input.thrust = Vector3.ZERO
	await get_tree().physics_frame


## The three mix trims, and the latch that holds the thrusters lit while they are set.
func _verify_thruster_mix(thrusters: PlayerThrusterSfx, input: PlayerInput) -> void:
	var loop: AudioStreamPlayer3D = thrusters.get_node("UpLoop")
	var edge: AudioStreamPlayer3D = thrusters.get_node("UpEdge")

	input.thrust = Vector3.UP
	await get_tree().physics_frame
	var untrimmed_loop := loop.volume_db
	var untrimmed_on := edge.volume_db
	input.thrust = Vector3.ZERO
	await get_tree().physics_frame
	var untrimmed_off := edge.volume_db
	check(is_equal_approx(untrimmed_on, untrimmed_off), "untrimmed, on and off sit level")

	thrusters.loop_trim_db = LOOP_TRIM
	thrusters.on_trim_db = ON_TRIM
	thrusters.off_trim_db = OFF_TRIM
	input.thrust = Vector3.UP
	await get_tree().physics_frame
	check(
		is_equal_approx(loop.volume_db, untrimmed_loop + LOOP_TRIM),
		"the loop trim moves the loop, live and without a restart"
	)
	check(is_equal_approx(edge.volume_db, untrimmed_on + ON_TRIM), "the on trim moves the start")
	input.thrust = Vector3.ZERO
	await get_tree().physics_frame
	check(
		is_equal_approx(edge.volume_db, untrimmed_off + OFF_TRIM),
		"and the off trim moves the stop, which one shared channel volume could not"
	)

	thrusters.loop_trim_db = 0.0
	thrusters.on_trim_db = 0.0
	thrusters.off_trim_db = 0.0
	await _verify_latch(thrusters)


## The latch has to light all eight from no input at all, and only while debug is on.
func _verify_latch(thrusters: PlayerThrusterSfx) -> void:
	var debug: Node = thrusters.get_node_or_null(^"/root/DebugMode")
	if debug == null:
		check(false, "the DebugMode autoload is loaded")
		return

	debug.set_enabled(false)
	await _press_latch()
	check(
		not thrusters.is_firing(PlayerThrusterSfx.Thruster.UP), "the latch is inert with debug off"
	)

	debug.set_enabled(true)
	await _press_latch()
	var lit := 0
	for thruster in PlayerThrusterSfx.THRUSTERS.size():
		if thrusters.is_firing(thruster):
			lit += 1
	check(lit == PlayerThrusterSfx.THRUSTERS.size(), "the latch holds all eight lit on no input")

	await _press_latch()
	check(not thrusters.is_firing(PlayerThrusterSfx.Thruster.UP), "and pressing it again lets go")
	debug.set_enabled(false)


func _press_latch() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_K
		key.pressed = pressed
		get_tree().root.push_input(key)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _verify_alien() -> void:
	var scene: PackedScene = load("res://prefabs/character/alien/prefab_alien.tscn")
	var alien := scene.instantiate()
	add_child(alien)
	await get_tree().physics_frame

	var sfx: AlienSfx = alien.get_node("AlienBody/Sfx")
	check(sfx.movement_player.stream == sfx.movement_near_loop, "the movement channel is loaded")
	var wav := sfx.movement_near_loop as AudioStreamWAV
	check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "and it actually loops")

	sfx.alert()
	check(sfx.voice_player.stream == sfx.voice_alerted, "alert() plays the alerted voice")

	sfx.attack()
	check(sfx.voice_player.stream == sfx.voice_attack, "attack() plays the attack voice")
	check(
		sfx.attack_player.stream == sfx.tentacle_attack, "and the tentacles, on their own channel"
	)
	check(sfx.voice_player.playing and sfx.attack_player.playing, "both at once, neither cut off")

	alien.queue_free()
	await get_tree().process_frame
