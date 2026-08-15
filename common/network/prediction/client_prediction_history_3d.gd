class_name ClientPredictionHistory3D
extends RefCounted

## Bounded, transport-agnostic history for one predicted 3D character.
##
## Commands and their resulting states share a monotonically increasing
## sequence number. An authoritative acknowledgement can therefore discard
## completed work and replay only commands the host has not processed yet.

const MAX_COMMANDS := 256

var _epoch := 1
var _next_sequence := 0
var _commands: Array = []
var _states: Dictionary = {}


func reset(epoch: int, acknowledged_sequence := 0) -> void:
	_epoch = maxi(epoch, 1)
	_next_sequence = maxi(acknowledged_sequence, 0)
	_commands.clear()
	_states.clear()


func clear_pending_keep_sequence(minimum_sequence := 0) -> void:
	# A same-epoch recovery must not reuse a number the host may have received.
	# Only a new authoritative epoch is allowed to restart command numbering.
	_next_sequence = maxi(_next_sequence, minimum_sequence)
	_commands.clear()
	_states.clear()


func create_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
) -> Dictionary:
	_next_sequence += 1
	var command := {
		"epoch": _epoch,
		"sequence": _next_sequence,
		"thrust": thrust,
		"look_delta": look_delta,
		"roll": roll,
		"flags": flags,
	}
	_commands.append(command)
	_trim_to_capacity()
	return command


func record_state(
	sequence: int,
	body_transform: Transform3D,
	velocity: Vector3,
	auxiliary_state: Dictionary = {},
) -> void:
	_states[sequence] = {
		"transform": body_transform,
		"velocity": velocity,
		# Movement adapters often have small pieces of state that affect the next
		# tick without living on CharacterBody3D, such as angular velocity or a
		# sprint cap. Own a deep copy so later simulation cannot rewrite history.
		"auxiliary_state": auxiliary_state.duplicate(true),
	}


func state_for(sequence: int) -> Dictionary:
	var raw_state: Variant = _states.get(sequence, {})
	return (raw_state as Dictionary).duplicate(true)


func acknowledge(sequence: int) -> Array:
	var remaining: Array = []
	for raw_command in _commands:
		var command: Dictionary = raw_command
		var command_sequence := int(command.get("sequence", 0))
		if command_sequence <= sequence:
			_states.erase(command_sequence)
		else:
			remaining.append(command)
	_commands = remaining
	return _commands.duplicate()


func pending_commands() -> Array:
	return _commands.duplicate()


func pending_count() -> int:
	return _commands.size()


func epoch() -> int:
	return _epoch


func latest_sequence() -> int:
	return _next_sequence


func _trim_to_capacity() -> void:
	while _commands.size() > MAX_COMMANDS:
		var removed: Dictionary = _commands.pop_front()
		_states.erase(int(removed.get("sequence", 0)))
