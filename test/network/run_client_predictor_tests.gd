extends SceneTree

## Headless checks for the configured host-side prediction boundary.
##
##     godot --headless --path . \
##       --script res://test/network/run_client_predictor_tests.gd \
##       --log-file /tmp/client-predictor-tests.log

const PredictorScript := preload("res://common/network/prediction/client_predictor_3d.gd")

var _checks := 0
var _failures := 0
var _simulated_command: Dictionary = {}
var _live_auxiliary_state := {"angular_velocity": Vector3(1.0, 2.0, 3.0)}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := CharacterBody3D.new()
	var presentation := Node3D.new()
	var prediction := PredictorScript.new()
	var state_sync := MultiplayerSynchronizer.new()
	presentation.name = "Presentation"
	prediction.name = "Prediction"
	state_sync.name = "StateSync"
	body.add_child(presentation)
	body.add_child(prediction)
	body.add_child(state_sync)
	(
		prediction
		. configure(
			PredictorScript.HOST_PEER_ID,
			presentation,
			Callable(self, "_simulate_command"),
			true,
			Callable(self, "_capture_auxiliary_state"),
			Callable(self, "_restore_auxiliary_state"),
			Callable(self, "_auxiliary_states_match"),
		)
	)
	root.add_child(body)

	(
		prediction
		. physics_step(
			1.0 / 60.0,
			Vector3(2.0, 0.0, 0.0),
			Vector2(PredictorScript.MAX_LOOK_DELTA * 2.0, 0.0),
			2.0,
			7,
		)
	)

	_expect_equal(_simulated_command["thrust"], Vector3.RIGHT, "host bounds thrust")
	_expect_equal(
		_simulated_command["look_delta"],
		Vector2(PredictorScript.MAX_LOOK_DELTA, 0.0),
		"host bounds look motion",
	)
	_expect_equal(_simulated_command["roll"], 1.0, "host bounds roll")
	_expect_equal(
		_simulated_command["flags"],
		PredictorScript.ALLOWED_FLAGS,
		"host masks unsupported flags",
	)
	_expect_equal(
		_simulated_command["context"],
		PredictorScript.SimulationContext.AUTHORITY,
		"the server invokes the authority context",
	)
	_expect_equal(
		prediction.authoritative_auxiliary_state["angular_velocity"],
		Vector3(1.0, 2.0, 3.0),
		"the server publishes adapter-owned state",
	)

	_live_auxiliary_state["angular_velocity"] = Vector3.ZERO
	_expect_equal(
		prediction.authoritative_auxiliary_state["angular_velocity"],
		Vector3(1.0, 2.0, 3.0),
		"the published auxiliary state owns a deep copy",
	)

	var state_to_restore := {"angular_velocity": Vector3(4.0, 5.0, 6.0)}
	prediction.call("_restore_current_auxiliary_state", state_to_restore)
	state_to_restore["angular_velocity"] = Vector3.ZERO
	_expect_equal(
		_live_auxiliary_state["angular_velocity"],
		Vector3(4.0, 5.0, 6.0),
		"restore receives an owned auxiliary snapshot",
	)
	_expect(
		bool(
			(
				prediction
				. call(
					"_do_auxiliary_states_match",
					{"angular_velocity": Vector3.ONE},
					{"angular_velocity": Vector3.ONE},
				)
			)
		),
		"the configured auxiliary comparison callback is used",
	)
	_test_remote_look_delta_is_consumed_once()

	body.queue_free()
	if _failures == 0:
		print("PASS [client-predictor] %d checks" % _checks)
	else:
		print("FAIL [client-predictor] %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _test_remote_look_delta_is_consumed_once() -> void:
	var body := CharacterBody3D.new()
	var presentation := Node3D.new()
	var prediction := PredictorScript.new()
	var state_sync := MultiplayerSynchronizer.new()
	presentation.name = "Presentation"
	prediction.name = "Prediction"
	state_sync.name = "StateSync"
	body.add_child(presentation)
	body.add_child(prediction)
	body.add_child(state_sync)
	(
		prediction
		. configure(
			2,
			presentation,
			Callable(self, "_simulate_command"),
		)
	)
	root.add_child(body)

	(
		prediction
		. call(
			"_store_remote_command",
			1,
			1,
			Vector3.FORWARD,
			Vector2(3.0, 4.0),
			0.5,
			PredictorScript.FLAG_SPRINTING,
		)
	)
	(
		prediction
		. call(
			"_store_remote_command",
			1,
			2,
			Vector3.RIGHT,
			Vector2(5.0, 6.0),
			-0.5,
			PredictorScript.FLAG_STABILIZING,
		)
	)
	prediction.call("_simulate_latest_remote_command")
	_expect_equal(
		_simulated_command["look_delta"],
		Vector2(8.0, 10.0),
		"remote look deltas accumulate until one host tick",
	)
	_expect_equal(
		_simulated_command["thrust"],
		Vector3.RIGHT,
		"remote held intent keeps only its newest value",
	)
	prediction.call("_simulate_latest_remote_command")
	_expect_equal(
		_simulated_command["look_delta"],
		Vector2.ZERO,
		"the host consumes remote look motion only once",
	)

	body.queue_free()


func _simulate_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
	_delta: float,
	context: int,
) -> void:
	_simulated_command = {
		"thrust": thrust,
		"look_delta": look_delta,
		"roll": roll,
		"flags": flags,
		"context": context,
	}


func _capture_auxiliary_state() -> Dictionary:
	return _live_auxiliary_state


func _restore_auxiliary_state(state: Dictionary) -> void:
	_live_auxiliary_state = state


func _auxiliary_states_match(predicted: Dictionary, authoritative: Dictionary) -> bool:
	return predicted == authoritative


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [client-predictor] %s" % description)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [description, expected, actual])
