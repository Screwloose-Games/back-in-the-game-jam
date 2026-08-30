extends Node

## End-to-end check that PlayerInteractor's focus and its tap-versus-hold machine survive
## a real prefab_player instantiation.
##
##     godot --headless --path . res://tests/verify_interaction.tscn
##
## Not an McpTestSuite and deliberately outside `test_*`: every case here has to await
## physics frames, and the runner calls tests synchronously. Same split as
## verify_player_sfx.tscn.

## Short enough that a hold completes in a handful of frames, and still inside the
## exported range so the settings resource stays valid.
const TEST_THRESHOLD := 0.05

const TEST_HOLD_SECONDS := 0.1

## Comfortably past TEST_THRESHOLD + TEST_HOLD_SECONDS at any sane physics rate.
const HOLD_FRAMES := 24

var _failures: PackedStringArray = []
var _input: PlayerInput
var _interactor: PlayerInteractor


func _ready() -> void:
	await _build_player()
	await _verify_focus_is_singular()
	await _verify_tap_fires_on_press_for_a_single_verb()
	await _verify_hold_completes_without_a_tap()
	await _verify_an_early_release_is_a_tap()
	await _verify_a_freed_target_cancels_the_hold()
	await _verify_a_disabled_target_cancels_and_hands_focus_on()
	await _verify_losing_input_cancels_and_clears_focus()
	await _verify_churn_leaves_the_candidate_list_honest()
	await _verify_the_cube_grabs_and_cranks()
	await _verify_the_elevator_answers_both_of_its_interactables()
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	if _failures.is_empty():
		print("\nverify_interaction: all checks passed")
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(passed: bool, what: String) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures.append(what)


func _build_player() -> void:
	var scene: PackedScene = load("res://prefabs/character/player/prefab_player.tscn")
	var player := scene.instantiate()
	add_child(player)
	await get_tree().physics_frame
	_input = player.get_node("PlayerBody/Input")
	_interactor = player.get_node("PlayerBody/Interactor")
	# The real device is taken out of the loop so interact_held can be driven by hand;
	# PlayerInput would otherwise resample it from an unpressed keyboard every frame.
	_input.set_physics_process(false)
	# Duplicated rather than mutated: settings is the shared player_settings.tres, and
	# retuning it here would retune the game.
	_interactor.settings = _interactor.settings.duplicate()
	_interactor.settings.interact_hold_threshold = TEST_THRESHOLD
	await get_tree().physics_frame


func _make_interactable(at: Vector3, mode: Interactable.HoldMode) -> Interactable:
	var node := Interactable.new()
	node.hold_mode = mode
	node.hold_seconds = TEST_HOLD_SECONDS
	node.position = at
	add_child(node)
	return node


func _press() -> void:
	_input.interact_held = true
	_input.interact_pressed.emit()


func _release() -> void:
	_input.interact_held = false
	_input.interact_released.emit()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## Two things overlapping you at once is the case the ported design got wrong: it lit
## every prompt in reach, because prompts hung off raw overlap rather than off focus.
func _verify_focus_is_singular() -> void:
	var ahead := _make_interactable(Vector3(0.0, 0.0, -1.2), Interactable.HoldMode.NONE)
	var abeam := _make_interactable(Vector3(1.2, 0.0, 0.0), Interactable.HoldMode.NONE)
	await _frames(3)
	check(_interactor.focused() == ahead, "the thing you are looking at takes focus")
	check(not abeam.is_focused(), "and the one beside you does not also light up")
	ahead.free()
	abeam.free()
	await _frames(2)


func _verify_tap_fires_on_press_for_a_single_verb() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.NONE)
	var taps := [0]
	target.interacted.connect(func(_who: Node3D) -> void: taps[0] += 1)
	await _frames(3)
	_press()
	await _frames(1)
	check(taps[0] == 1, "a target with one verb fires on the press, not on the release")
	_release()
	await _frames(2)
	check(taps[0] == 1, "and the release adds nothing")
	target.free()
	await _frames(2)


func _verify_hold_completes_without_a_tap() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.TIMED)
	var seen := {"tap": 0, "started": 0, "completed": 0, "progress": 0.0}
	target.interacted.connect(func(_who: Node3D) -> void: seen["tap"] += 1)
	target.hold_started.connect(func(_who: Node3D) -> void: seen["started"] += 1)
	target.hold_completed.connect(func(_who: Node3D) -> void: seen["completed"] += 1)
	target.hold_progressed.connect(func(f: float) -> void: seen["progress"] = f)
	await _frames(3)
	_press()
	await _frames(HOLD_FRAMES)
	check(seen["started"] == 1, "holding past the threshold starts a hold")
	check(seen["progress"] > 0.0, "and reports progress while it fills")
	check(seen["completed"] == 1, "and completes on its own when the bar is full")
	_release()
	await _frames(2)
	check(seen["tap"] == 0, "a completed hold never also fires the tap")
	target.free()
	await _frames(2)


func _verify_an_early_release_is_a_tap() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.TIMED)
	var seen := {"tap": 0, "started": 0}
	target.interacted.connect(func(_who: Node3D) -> void: seen["tap"] += 1)
	target.hold_started.connect(func(_who: Node3D) -> void: seen["started"] += 1)
	await _frames(3)
	_press()
	_release()
	await _frames(2)
	check(seen["tap"] == 1, "letting go before the threshold is a tap")
	check(seen["started"] == 0, "and never announces a hold it did not start")
	target.free()
	await _frames(2)


## The bar must always come back down, even when the thing it was drawn for is gone.
func _verify_a_freed_target_cancels_the_hold() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.TIMED)
	target.hold_seconds = 10.0
	var cancels := [0]
	_interactor.hold_cancelled.connect(func() -> void: cancels[0] += 1)
	await _frames(3)
	_press()
	await _frames(4)
	check(_interactor.is_hold_active(), "the hold is running before the target goes away")
	target.queue_free()
	await _frames(3)
	check(cancels[0] >= 1, "freeing the target mid-hold cancels rather than erroring")
	check(not _interactor.is_hold_active(), "and the gesture does not survive it")
	_release()
	await _frames(2)


func _verify_a_disabled_target_cancels_and_hands_focus_on() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.TIMED)
	target.hold_seconds = 10.0
	var spare := _make_interactable(Vector3(0.0, 0.0, -1.6), Interactable.HoldMode.NONE)
	await _frames(3)
	_press()
	await _frames(4)
	check(_interactor.is_hold_active(), "the hold is running before the target is disabled")
	target.set_enabled(false)
	await _frames(3)
	check(not _interactor.is_hold_active(), "disabling a target mid-hold cancels it")
	_release()
	await _frames(3)
	check(_interactor.focused() == spare, "and focus moves on to what is still available")
	target.free()
	spare.free()
	await _frames(2)


## The cutscene and pause seam: PlayerInput.clear() drops the key without ever sending a
## release, so the interactor cannot wait for one.
func _verify_losing_input_cancels_and_clears_focus() -> void:
	var target := _make_interactable(Vector3(0.0, 0.0, -1.0), Interactable.HoldMode.TIMED)
	target.hold_seconds = 10.0
	await _frames(3)
	_press()
	await _frames(4)
	check(_interactor.is_hold_active(), "the hold is running before control is taken")
	_input.enabled = false
	await _frames(3)
	check(not _interactor.is_hold_active(), "losing input cancels the hold")
	check(_interactor.focused() == null, "and nothing is left prompting over a cutscene")
	_input.enabled = true
	_input.set_physics_process(false)
	_input.interact_held = false
	target.free()
	await _frames(3)


## The regression for the defect this port exists to fix: the original filtered on the
## class going in and on a group nothing ever joined coming out, so nothing was removed.
func _verify_churn_leaves_the_candidate_list_honest() -> void:
	var near := Vector3(0.0, 0.0, -1.0)
	var far := Vector3(0.0, 0.0, -40.0)
	var target := _make_interactable(near, Interactable.HoldMode.NONE)
	for _i in 5:
		target.position = far
		await _frames(2)
		target.position = near
		await _frames(2)
	check(_interactor.focused() == target, "after repeated entries and exits it is focused")
	target.position = far
	await _frames(3)
	check(_interactor.focused() == null, "and walking away really does drop it")
	target.free()
	await _frames(2)


## Stage 4 end to end: the doorway and the call panel are two ways of asking the same
## question, and below quota the answer is a refusal rather than silence.
func _verify_the_elevator_answers_both_of_its_interactables() -> void:
	var scene: PackedScene = load("res://prefabs/environment/elevator/prefab_elevator_car.tscn")
	var car := scene.instantiate() as ElevatorCar
	add_child(car)
	await _frames(2)

	var exit_node := car.get_node("Exit") as ElevatorExit
	var ways_out := car.find_children("*", "Interactable", true, false)
	check(ways_out.size() == 2, "the car offers exactly two ways to ask: the door and the panel")

	var refusals := [0]
	var approvals := [0]
	exit_node.departure_refused.connect(func(_short: int) -> void: refusals[0] += 1)
	exit_node.departure_approved.connect(func() -> void: approvals[0] += 1)

	var screen := car.get_quota_screen()
	Score.score = 0
	screen.refresh()
	for way: Interactable in ways_out:
		way.interact(_interactor)
	await _frames(1)
	check(refusals[0] == 2, "below quota, both of them refuse")
	check(approvals[0] == 0, "and neither lets you leave")

	# Well past the target, so no rounding anywhere can make this a near miss.
	Score.score = Score.quota_target * 10
	screen.refresh()
	await _frames(1)
	check(screen.is_quota_met(), "the screen reads APPROVED once the ledger clears the target")
	ways_out[0].interact(_interactor)
	await _frames(1)
	check(approvals[0] == 1, "and then the door lets you go")

	car.queue_free()
	await _frames(2)


## Stage 3 end to end, in the exact geometry the level ships: asteroid_level parks the life
## support cube about a metre and a half in front of PlayerSpawn, so it is already inside
## the reach when the interactor starts monitoring. An overlap that began before monitoring
## did never raises area_entered, which is why the interactor seeds from its own overlaps.
func _verify_the_cube_grabs_and_cranks() -> void:
	var scene: PackedScene = load("res://prefabs/gameplay/prefab_life_support_cube.tscn")
	var cube := scene.instantiate() as LifeSupportCube
	# The prefab ships full, and there is nothing to wind on a full box.
	cube.start_fraction = 0.4
	cube.position = Vector3(0.0, 0.0, -1.6)
	add_child(cube)
	await _frames(4)

	var handle := cube.get_node("Handle") as Interactable
	check(_interactor.focused() == handle, "the cube you spawn beside is in reach immediately")

	_press()
	await _frames(1)
	_release()
	await _frames(2)
	check(_interactor.is_carrying(), "a tap picks it up")
	check(_interactor.focused() == handle, "and what is in your hands keeps the key")

	_press()
	await _frames(1)
	_release()
	await _frames(2)
	check(not _interactor.is_carrying(), "and a second tap puts it down")

	var before := cube.fraction()
	_press()
	await _frames(HOLD_FRAMES)
	check(cube.is_being_cranked(), "holding turns the crank")
	check(cube.fraction() > before, "and charge actually goes in")
	_release()
	await _frames(2)
	check(not cube.is_being_cranked(), "letting go stops it")
	check(not _interactor.is_carrying(), "and cranking never grabbed it by accident")

	cube.queue_free()
	await _frames(3)
