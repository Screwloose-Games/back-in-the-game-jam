extends SceneTree

## Headless checks for the transport-independent prediction history.
##
## Run from the Godot project root with:
##
##     godot --headless --path . \
##       --script res://test/network/run_client_prediction_history_tests.gd \
##       --log-file /tmp/client-prediction-history-tests.log

const HistoryScript := preload("res://common/network/prediction/client_prediction_history_3d.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reset_starts_after_the_acknowledgement()
	_test_command_preserves_every_movement_field()
	_test_result_state_includes_owned_auxiliary_state()
	_test_acknowledgement_prunes_and_preserves_order()
	_test_capacity_evicts_matching_states()
	_test_epoch_reset_discards_old_prediction()
	_test_same_epoch_recovery_preserves_sequence_numbers()

	if _failures == 0:
		print("PASS [client-prediction-history] %d checks" % _checks)
	else:
		print("FAIL [client-prediction-history] %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _test_reset_starts_after_the_acknowledgement() -> void:
	var history := HistoryScript.new()
	history.reset(7, 40)

	_expect_equal(history.epoch(), 7, "reset stores the authoritative epoch")
	_expect_equal(history.latest_sequence(), 40, "reset stores the acknowledged sequence")
	_expect_equal(history.pending_count(), 0, "reset starts with no pending commands")

	var command: Dictionary = (
		history
		. create_command(
			Vector3(0.25, -0.5, 0.75),
			Vector2(12.0, -8.0),
			-0.5,
			3,
		)
	)
	_expect_equal(command["sequence"], 41, "the next command follows the acknowledgement")
	_expect_equal(command["epoch"], 7, "new commands carry the current epoch")


func _test_command_preserves_every_movement_field() -> void:
	var history := HistoryScript.new()
	var command: Dictionary = (
		history
		. create_command(
			Vector3(0.25, -0.5, 0.75),
			Vector2(14.0, -9.0),
			0.6,
			3,
		)
	)

	_expect_equal(command["thrust"], Vector3(0.25, -0.5, 0.75), "command stores thrust")
	_expect_equal(command["look_delta"], Vector2(14.0, -9.0), "command stores look delta")
	_expect_equal(command["roll"], 0.6, "command stores roll")
	_expect_equal(command["flags"], 3, "command stores movement flags")


func _test_result_state_includes_owned_auxiliary_state() -> void:
	var history := HistoryScript.new()
	var command: Dictionary = (
		history
		. create_command(
			Vector3.FORWARD,
			Vector2.ZERO,
			0.0,
			0,
		)
	)
	var sequence := int(command["sequence"])
	var body_transform := Transform3D(Basis.IDENTITY, Vector3(2.0, 3.0, 4.0))
	var velocity := Vector3(-1.0, 0.5, 2.0)
	var auxiliary := {
		"angular_velocity": Vector3(1.0, 2.0, 3.0),
		"speed_cap": 8.0,
		"contact": {"touching": true},
	}
	history.record_state(sequence, body_transform, velocity, auxiliary)

	# Neither the adapter's live state nor a caller's returned snapshot may own
	# the history's nested Dictionary.
	(auxiliary["contact"] as Dictionary)["touching"] = false
	var first_read: Dictionary = history.state_for(sequence)
	(first_read["auxiliary_state"] as Dictionary)["speed_cap"] = 99.0
	var second_read: Dictionary = history.state_for(sequence)
	var stored_auxiliary: Dictionary = second_read["auxiliary_state"]

	_expect_equal(second_read["transform"], body_transform, "state stores the resulting transform")
	_expect_equal(second_read["velocity"], velocity, "state stores the resulting velocity")
	_expect_equal(stored_auxiliary["speed_cap"], 8.0, "state owns a deep auxiliary copy")
	_expect_equal(
		(stored_auxiliary["contact"] as Dictionary)["touching"],
		true,
		"nested auxiliary state is isolated from later mutation",
	)
	_expect(history.state_for(sequence + 1).is_empty(), "an unknown sequence has no state")


func _test_acknowledgement_prunes_and_preserves_order() -> void:
	var history := HistoryScript.new()
	for index: int in range(1, 6):
		var command: Dictionary = (
			history
			. create_command(
				Vector3(float(index), 0.0, 0.0),
				Vector2.ZERO,
				0.0,
				0,
			)
		)
		var sequence := int(command["sequence"])
		(
			history
			. record_state(
				sequence,
				Transform3D(Basis.IDENTITY, Vector3(float(index), 0.0, 0.0)),
				Vector3(float(index), 0.0, 0.0),
				{"step": index},
			)
		)

	var replay_tail: Array = history.acknowledge(3)
	_expect_equal(_command_sequences(replay_tail), [4, 5], "only newer commands remain")
	_expect(history.state_for(3).is_empty(), "the acknowledged state is pruned")
	_expect(not history.state_for(4).is_empty(), "a pending command retains its state")
	_expect_equal(
		_command_sequences(history.acknowledge(2)),
		[4, 5],
		"a stale acknowledgement is idempotent",
	)


func _test_capacity_evicts_matching_states() -> void:
	var history := HistoryScript.new()
	var extra_commands := 9
	var total_commands: int = HistoryScript.MAX_COMMANDS + extra_commands
	for index: int in range(1, total_commands + 1):
		var command: Dictionary = (
			history
			. create_command(
				Vector3.ZERO,
				Vector2.ZERO,
				0.0,
				0,
			)
		)
		var sequence := int(command["sequence"])
		(
			history
			. record_state(
				sequence,
				Transform3D(Basis.IDENTITY, Vector3(float(index), 0.0, 0.0)),
				Vector3.ZERO,
			)
		)

	var pending: Array = history.pending_commands()
	_expect_equal(history.pending_count(), HistoryScript.MAX_COMMANDS, "history is bounded")
	_expect_equal(
		int((pending.front() as Dictionary)["sequence"]),
		extra_commands + 1,
		"capacity trimming removes oldest commands first",
	)
	_expect(history.state_for(extra_commands).is_empty(), "eviction removes the matching state")


func _test_epoch_reset_discards_old_prediction() -> void:
	var history := HistoryScript.new()
	var old_command: Dictionary = (
		history
		. create_command(
			Vector3.UP,
			Vector2.ZERO,
			0.0,
			0,
		)
	)
	var old_sequence := int(old_command["sequence"])
	(
		history
		. record_state(
			old_sequence,
			Transform3D(Basis.IDENTITY, Vector3.UP),
			Vector3.UP,
			{"angular_velocity": Vector3.ONE},
		)
	)

	history.reset(8, 12)
	_expect_equal(history.epoch(), 8, "reset changes epoch")
	_expect_equal(history.pending_count(), 0, "epoch reset discards commands")
	_expect(history.state_for(old_sequence).is_empty(), "epoch reset discards states")

	var next_command: Dictionary = (
		history
		. create_command(
			Vector3.DOWN,
			Vector2.ZERO,
			0.0,
			0,
		)
	)
	_expect_equal(next_command["sequence"], 13, "new commands follow the reset acknowledgement")


func _test_same_epoch_recovery_preserves_sequence_numbers() -> void:
	var history := HistoryScript.new()
	history.reset(4, 20)
	for _index: int in range(5):
		history.create_command(Vector3.FORWARD, Vector2.ZERO, 0.0, 0)

	history.clear_pending_keep_sequence(22)
	_expect_equal(history.epoch(), 4, "same-epoch recovery retains epoch")
	_expect_equal(history.pending_count(), 0, "same-epoch recovery clears history")
	_expect_equal(history.latest_sequence(), 25, "recovery retains the highest sequence")

	var next_command: Dictionary = (
		history
		. create_command(
			Vector3.BACK,
			Vector2.ZERO,
			0.0,
			0,
		)
	)
	_expect_equal(next_command["sequence"], 26, "recovery never reuses a sequence")


func _command_sequences(commands: Array) -> Array:
	var sequences: Array = []
	for raw_command in commands:
		var command: Dictionary = raw_command
		sequences.append(int(command.get("sequence", 0)))
	return sequences


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [client-prediction-history] %s" % description)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [description, expected, actual])
