extends SceneTree

## Headless checks for the transport-independent part of client prediction.
##
## Run from the Godot project root with:
##
##     godot --headless --path . \
##       --script res://test/network/run_client_prediction_history_tests.gd
##
## This deliberately loads no scene, multiplayer peer, physics body, or
## renderer. It pins the history contract that reconciliation relies on while
## leaving browser/WebRTC behavior to the multiplayer smoke demos.

const HistoryScript := preload("res://common/network/prediction/client_prediction_history_3d.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reset_starts_the_next_sequence_after_the_acknowledgement()
	_test_commands_and_resulting_states_share_a_sequence()
	_test_acknowledgement_prunes_inclusively_and_keeps_replay_order()
	_test_returned_command_arrays_do_not_own_the_history()
	_test_capacity_is_bounded_and_evicts_matching_states()
	_test_epoch_reset_discards_every_old_prediction()
	_test_same_epoch_recovery_preserves_sequence_numbers()

	if _failures == 0:
		print("PASS [client-prediction-history] %d checks" % _checks)
	else:
		print("FAIL [client-prediction-history] %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _test_reset_starts_the_next_sequence_after_the_acknowledgement() -> void:
	var history := HistoryScript.new()
	history.reset(7, 40)

	_expect_equal(history.epoch(), 7, "reset stores the authoritative epoch")
	_expect_equal(history.latest_sequence(), 40, "reset stores the acknowledged sequence")
	_expect_equal(history.pending_count(), 0, "reset starts with no pending commands")

	var first: Dictionary = (
		history
		. create_command(
			Vector3(0.25, -0.5, 0.75),
			Quaternion.IDENTITY,
			3,
		)
	)
	var second: Dictionary = (
		history
		. create_command(
			Vector3.ZERO,
			Quaternion(Vector3.UP, 0.25),
			0,
		)
	)
	_expect_equal(first["sequence"], 41, "the first new command follows the acknowledgement")
	_expect_equal(second["sequence"], 42, "command sequences increase monotonically")
	_expect_equal(first["epoch"], 7, "commands carry the current epoch")
	_expect_equal(first["thrust"], Vector3(0.25, -0.5, 0.75), "commands retain bounded input")
	_expect_equal(first["flags"], 3, "commands retain discrete input flags")


func _test_commands_and_resulting_states_share_a_sequence() -> void:
	var history := HistoryScript.new()
	history.reset(2)
	var command: Dictionary = (
		history
		. create_command(
			Vector3.FORWARD,
			Quaternion.IDENTITY,
			0,
		)
	)
	var sequence := int(command["sequence"])
	var body_transform := Transform3D(Basis.IDENTITY, Vector3(2.0, 3.0, 4.0))
	var velocity := Vector3(-1.0, 0.5, 2.0)
	history.record_state(sequence, body_transform, velocity)

	var state: Dictionary = history.state_for(sequence)
	_expect_equal(state["transform"], body_transform, "a command finds its resulting transform")
	_expect_equal(state["velocity"], velocity, "a command finds its resulting velocity")
	_expect(
		history.state_for(sequence + 1).is_empty(), "an unknown sequence has no predicted state"
	)


func _test_acknowledgement_prunes_inclusively_and_keeps_replay_order() -> void:
	var history := HistoryScript.new()
	for index: int in range(1, 6):
		var command: Dictionary = (
			history
			. create_command(
				Vector3(float(index), 0.0, 0.0),
				Quaternion.IDENTITY,
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
			)
		)

	# Reconciliation reads the state at the acknowledged sequence before it
	# removes that sequence and asks for the still-unprocessed replay tail.
	_expect(
		not history.state_for(3).is_empty(),
		"the acknowledged predicted state is available before pruning",
	)
	var replay_tail: Array = history.acknowledge(3)
	_expect_equal(_command_sequences(replay_tail), [4, 5], "only newer commands remain to replay")
	_expect(history.state_for(1).is_empty(), "states older than the acknowledgement are pruned")
	_expect(history.state_for(3).is_empty(), "the acknowledged state itself is pruned")
	_expect(not history.state_for(4).is_empty(), "a pending command keeps its predicted state")

	var after_stale_ack: Array = history.acknowledge(2)
	_expect_equal(
		_command_sequences(after_stale_ack),
		[4, 5],
		"a stale acknowledgement is idempotent",
	)


func _test_returned_command_arrays_do_not_own_the_history() -> void:
	var history := HistoryScript.new()
	history.create_command(Vector3.LEFT, Quaternion.IDENTITY, 0)
	history.create_command(Vector3.RIGHT, Quaternion.IDENTITY, 0)

	var snapshot: Array = history.pending_commands()
	snapshot.clear()
	_expect_equal(history.pending_count(), 2, "clearing a pending snapshot does not clear history")

	var replay_tail: Array = history.acknowledge(1)
	replay_tail.clear()
	_expect_equal(history.pending_count(), 1, "clearing a replay tail does not clear history")


func _test_capacity_is_bounded_and_evicts_matching_states() -> void:
	var history := HistoryScript.new()
	var extra_commands := 9
	var total_commands: int = HistoryScript.MAX_COMMANDS + extra_commands
	for index: int in range(1, total_commands + 1):
		var command: Dictionary = (
			history
			. create_command(
				Vector3.ZERO,
				Quaternion.IDENTITY,
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
	_expect_equal(
		history.pending_count(), HistoryScript.MAX_COMMANDS, "history has a hard capacity"
	)
	_expect_equal(
		int((pending.front() as Dictionary)["sequence"]),
		extra_commands + 1,
		"capacity trimming evicts the oldest commands first",
	)
	_expect_equal(
		int((pending.back() as Dictionary)["sequence"]),
		total_commands,
		"capacity trimming retains the newest command",
	)
	_expect(
		history.state_for(extra_commands).is_empty(),
		"evicting a command also evicts its resulting state",
	)
	_expect(
		not history.state_for(extra_commands + 1).is_empty(),
		"the oldest retained command still has its resulting state",
	)


func _test_epoch_reset_discards_every_old_prediction() -> void:
	var history := HistoryScript.new()
	var old_command: Dictionary = (
		history
		. create_command(
			Vector3.UP,
			Quaternion.IDENTITY,
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
		)
	)

	history.reset(8, 12)
	_expect_equal(history.epoch(), 8, "reset changes to the new authoritative epoch")
	_expect_equal(history.pending_count(), 0, "epoch reset discards old commands")
	_expect(history.state_for(old_sequence).is_empty(), "epoch reset discards old predicted states")

	var next_command: Dictionary = (
		history
		. create_command(
			Vector3.DOWN,
			Quaternion.IDENTITY,
			0,
		)
	)
	_expect_equal(next_command["epoch"], 8, "new commands carry the reset epoch")
	_expect_equal(next_command["sequence"], 13, "new commands follow the reset acknowledgement")


func _test_same_epoch_recovery_preserves_sequence_numbers() -> void:
	var history := HistoryScript.new()
	history.reset(4, 20)
	for _index: int in range(5):
		history.create_command(Vector3.FORWARD, Quaternion.IDENTITY, 0)

	history.clear_pending_keep_sequence(22)
	_expect_equal(history.epoch(), 4, "same-epoch recovery retains the epoch")
	_expect_equal(history.pending_count(), 0, "same-epoch recovery clears pending history")
	_expect_equal(history.latest_sequence(), 25, "same-epoch recovery retains the highest sequence")

	var next_command: Dictionary = history.create_command(Vector3.BACK, Quaternion.IDENTITY, 0)
	_expect_equal(
		next_command["sequence"],
		26,
		"same-epoch recovery never reuses a sequence the host may have seen",
	)


func _command_sequences(commands: Array) -> Array:
	var sequences: Array = []
	for raw_command in commands:
		var command: Dictionary = raw_command
		sequences.append(int(command["sequence"]))
	return sequences


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [client-prediction-history] %s" % description)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [description, expected, actual])
