class_name PlayerInput
extends Node

## Owns this player's input device and mouse capture, and publishes every
## control as a plain property. No other player component reads `Input`, which
## is what lets a second player exist without rewriting any of them.

## Edge events. Continuous controls are properties, read once per physics frame.
##
## interact publishes BOTH edges, and is the only action here that does. Telling a tap
## from a hold is a question about how long the key was down, which one toggle signal
## cannot answer; PlayerInteractor times the gap between these two.
signal interact_pressed
signal interact_released
signal tether_toggled
signal lamp_toggled
signal reset_requested

## One press of anything at all, while something has hold of the suit.
##
## Emitted from _input() ABOVE the `enabled` guard, and that placement is the whole
## point: whatever took the suit away also made every branch below unreachable, and
## mashing has to stay readable precisely when nothing else is.
signal struggled

## Actions that keep their own meaning while the suit is held, so mashing cannot
## trigger them and they cannot be spent as a struggle. Pause above all: a creature
## that can trap a player in a session they cannot leave is a bug, not a threat.
const STRUGGLE_EXCLUDED: Array[StringName] = [
	&"pause",
	&"toggle_mouse_capture",
	&"cutscene_skip",
	&"toggle_debug",
	&"voice_push_to_talk",
]

## Which device drives this player. Only `_action_strength` and `_action_pressed`
## know about it, so per-device routing for local co-op replaces those two and
## nothing else.
@export var device_id: int = 0

## Cleared and stops polling while false. This is the cutscene and pause seam.
##
## GUARDED BY `locked`. Three components write this - PlayerUi on unpause,
## PlayerLife on revive, and whatever cutscene is running - and the first two do
## it unconditionally. Without the guard, pausing mid-cutscene hands control back
## to a player whose collision is off and whose camera has been taken.
@export var enabled: bool = true:
	set(value):
		enabled = value and not locked
		if not enabled:
			clear()

## While true, `enabled` cannot be set true. Owned by whatever took control away;
## clearing it is that owner's job and nobody else's.
@export var locked: bool = false:
	set(value):
		locked = value
		if locked:
			enabled = false

## Whether this player grabs the mouse on spawn. Off on the instances that
## represent other peers; the spawner sets it alongside is_local_player.
@export var captures_mouse: bool = true

## While true, a press of any bound action outside STRUGGLE_EXCLUDED emits
## `struggled`. Owned by whatever has hold of the suit; clearing it is that owner's
## job and nobody else's, the same contract `locked` has.
@export var struggle_listening: bool = false

## Whether this input source may publish edge-triggered gameplay requests.
## A network driver can leave this on only for the locally controlled copy and
## forward the signals to authority. Held intent such as mine_held is still
## sampled below so the driver can include it in its own command stream.
@export var gameplay_actions_enabled: bool = true

## Body-local thrust, clamped to a unit sphere.
var thrust := Vector3.ZERO
## Look motion in raw device pixels since the last physics frame.
var look := Vector2.ZERO
## Roll axis, -1 to 1.
var roll := 0.0
var stabilize_held := false
var sprint_held := false
var mine_held := false
var interact_held := false

var _accumulated_mouse_motion := Vector2.ZERO
var _is_mouse_captured := false


func _ready() -> void:
	# Input must publish before anything reads it; the components are siblings,
	# so tree order alone is too fragile to rely on.
	process_physics_priority = -100
	if captures_mouse:
		capture_mouse()


# Read here rather than in _unhandled_input: while the mouse is captured the
# cursor sits at screen centre, so a Control there would eat the motion first.
func _input(event: InputEvent) -> void:
	# Above the `enabled` guard on purpose -- see the signal's docstring.
	if struggle_listening and _is_struggle_press(event):
		struggled.emit()
		return
	# Disabled remote copies must not react to this machine's mouse or hotkeys.
	if not enabled:
		return
	if event is InputEventMouseMotion:
		if _is_mouse_captured:
			# screen_relative is the raw device delta; relative is divided by the
			# stretch scale, which would tie look sensitivity to window size.
			_accumulated_mouse_motion += event.screen_relative
		return
	if event.is_action_pressed("toggle_mouse_capture"):
		toggle_mouse_capture()
		return
	if not gameplay_actions_enabled:
		return
	if event.is_action_pressed("reset_player"):
		reset_requested.emit()
	elif event.is_action_pressed("interact"):
		interact_pressed.emit()
	elif event.is_action_released("interact"):
		interact_released.emit()
	elif event.is_action_pressed("toggle_tether"):
		tether_toggled.emit()
	elif event.is_action_pressed("toggle_lamp"):
		lamp_toggled.emit()


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	thrust = PlayerFlight.thrust_from_axes(
		_action_axis("thrust_left", "thrust_right"),
		_action_axis("thrust_down", "thrust_up"),
		_action_axis("thrust_forward", "thrust_back")
	)
	roll = _action_axis("roll_left", "roll_right")
	stabilize_held = _action_pressed("stabilize")
	sprint_held = _action_pressed("sprint")
	mine_held = _action_pressed("mine")
	interact_held = _action_pressed("interact")
	look = _accumulated_mouse_motion
	_accumulated_mouse_motion = Vector2.ZERO


## How hard the thrusters are firing, 0 to 1. Oxygen and noise are priced off
## this rather than off speed, because coasting is free and thrusting is not.
func thrust_fraction() -> float:
	return minf(thrust.length(), 1.0)


## Drops every held control. Called when input is disabled so a key held at the
## moment a cutscene starts does not stay held for its duration.
func clear() -> void:
	thrust = Vector3.ZERO
	look = Vector2.ZERO
	roll = 0.0
	stabilize_held = false
	sprint_held = false
	mine_held = false
	interact_held = false
	_accumulated_mouse_motion = Vector2.ZERO


func capture_mouse() -> void:
	_set_mouse_captured(true)


## The other half of capture_mouse, for a cutscene that wants the pointer back.
##
## Writing Input.mouse_mode directly instead leaves _is_mouse_captured stale, and
## the next toggle_mouse_capture() then goes the wrong way.
func release_mouse() -> void:
	_set_mouse_captured(false)


func toggle_mouse_capture() -> void:
	_set_mouse_captured(not _is_mouse_captured)


func is_mouse_captured() -> bool:
	return _is_mouse_captured


func _set_mouse_captured(should_capture: bool) -> void:
	_is_mouse_captured = should_capture
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE)


## The one place an action's value is read. Per-device routing for local co-op
## replaces this and `_action_pressed`, and no component notices.
func _action_axis(negative: StringName, positive: StringName) -> float:
	return Input.get_axis(negative, positive)


func _action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)


## Whether this event is a fresh press of anything a player could be mashing.
##
## The whole map rather than a list, so a binding added later counts without anyone
## remembering to come back here. One press per EVENT and never one per matching
## action: two actions can share a key, and a chord would otherwise count twice.
func _is_struggle_press(event: InputEvent) -> bool:
	if event.is_echo() or event is InputEventMouseMotion:
		return false
	for action: StringName in InputMap.get_actions():
		if STRUGGLE_EXCLUDED.has(action):
			continue
		if event.is_action_pressed(action):
			return true
	return false
