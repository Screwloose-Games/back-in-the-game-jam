class_name BtCooldown
extends BtDecorator

## FAILURE until `seconds` have elapsed since its child last SUCCEEDED.
##
## Times from success, not from the attempt, so a child that fails or is still RUNNING is
## re-offered immediately. A cooldown that started on the attempt would lock out a branch
## for failing, which is the opposite of what a fallback selector needs.
##
## AVAILABLE ON THE FIRST TICK. `-INF` rather than zero, because a clock injected from
## delta starts at 0.0 and a naive `now - 0.0 < seconds` would mute the child for the
## creature's first few seconds of life -- an alien that ignores the first noise it ever
## hears, once per session, which nobody reproduces.

## Reads `ctx.clock` duck-typed: the framework stays domain-free and never learns what a
## BehaviorContext is.
var seconds: float = 0.0

var _last_success_at: float = -INF


func _init(p_name: StringName, p_seconds: float, p_child: BtNode) -> void:
	super(p_name, p_child)
	seconds = p_seconds


## Forgets the cooldown, so re-entering a state does not inherit the last visit's timer.
func abort(ctx) -> void:
	super(ctx)
	_last_success_at = -INF


func ready_at() -> float:
	return _last_success_at + seconds


func _run(ctx) -> Status:
	if child == null:
		return Status.FAILURE
	var now: float = ctx.clock
	if now - _last_success_at < seconds:
		return Status.FAILURE
	var status: Status = child.tick(ctx)
	if status == Status.SUCCESS:
		_last_success_at = now
	return status
