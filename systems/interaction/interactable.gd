class_name Interactable
extends Area3D

## Anything a player can address: a console, a hatch, a crank. Hang one under the thing,
## say what the prompt reads and whether it answers a tap or a hold, and connect the
## signal. Found and never finding -- it monitors nothing and masks nothing.

## An interactor took focus, or gave it up. This pair is the only sanctioned way to drive
## a prompt; listening to area_entered instead lights every overlap at once.
signal focus_gained(interactor: Node3D)
signal focus_lost(interactor: Node3D)

## A tap landed. At most once per press.
signal interacted(interactor: Node3D)

signal hold_started(interactor: Node3D)
signal hold_progressed(fraction: float)
signal hold_completed(interactor: Node3D)

## The key came up, the thing went away, or it was disabled, before the bar filled.
signal hold_cancelled

## Whether this can be addressed at all, for a prompt or a shader that wants to grey out.
signal availability_changed(available: bool)

## What holding does here.
enum HoldMode {
	## Nothing. There is no hold verb, so the tap fires on PRESS rather than on release --
	## nothing with one verb should pay for telling two apart.
	NONE,
	## Fills over hold_seconds and then fires hold_completed. A hatch being winched.
	TIMED,
	## Is the verb, for as long as it lasts. Nothing completes. A crank.
	LATCHED,
}

## Layer 9, `interactable` in project.godot. Bits 1-8 are all spoken for, and an
## interactable must not share a bit with anything a hull or a ray already masks.
const LAYER := 1 << 8

## How anything hunting interactables finds them without a NodePath out of a prefab.
const GROUP := &"interactable"

## What the primary prompt reads. A verb rather than a noun: "Grab", "Crank", "Open".
@export var prompt: String = "Use"

## Which input action the primary prompt uses. The displayed key comes from the current
## binding rather than being baked into the scene text.
@export var prompt_action: StringName = &"interact"

## What the hold line says for the primary action. Empty falls back to `prompt`.
@export var hold_prompt: String = ""

## Extra actions this interactable wants the focused prompt to advertise, in parallel
## with `extra_prompts`. They are prompt-only: another component may own the action.
@export var extra_prompt_actions: PackedStringArray = PackedStringArray()

## Text paired with `extra_prompt_actions`, one entry per action.
@export var extra_prompts: PackedStringArray = PackedStringArray()

## False takes it out of contention immediately, mid-hold included.
@export var enabled: bool = true:
	set = set_enabled

## Whether it is spent after one successful interaction.
@export var one_shot: bool = false

@export_flags_3d_physics var interactable_layers: int = LAYER

@export_group("Hold")

@export var hold_mode: HoldMode = HoldMode.NONE

## Seconds of holding TIMED needs, on top of the threshold. Ignored by the others.
@export_range(0.05, 10.0, 0.05, "suffix:s") var hold_seconds: float = 1.2

## Whether a tap does anything. False on a crank, where only the hold is a verb.
@export var tap_enabled: bool = true

## Half-extents of the box built when the scene author left no CollisionShape3D child.
@export var fallback_extents := Vector3(0.5, 0.5, 0.5)

var _focused_by: Node3D
var _hold_fraction := 0.0
var _holding := false
var _used := false


func _ready() -> void:
	collision_layer = interactable_layers
	# Found, never finding. `monitorable` is the half that lets an interactor see this;
	# `monitoring` off and an empty mask mean it never runs a query of its own.
	collision_mask = 0
	monitorable = enabled
	monitoring = false
	add_to_group(GROUP)
	if _authored_shape() == null:
		_build_fallback_shape()


func is_available() -> bool:
	return enabled and not (one_shot and _used)


func is_focused() -> bool:
	return _focused_by != null


func focused_by() -> Node3D:
	return _focused_by


func prompt_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if tap_enabled and not prompt.is_empty():
		lines.append(_format_prompt_line(prompt_action, prompt))
	if supports_hold():
		var hold_text := hold_prompt if not hold_prompt.is_empty() else prompt
		if not hold_text.is_empty():
			lines.append(_format_hold_line(prompt_action, hold_text))
	var count := mini(extra_prompt_actions.size(), extra_prompts.size())
	for index in range(count):
		var extra_prompt := extra_prompts[index].strip_edges()
		if extra_prompt.is_empty():
			continue
		lines.append(_format_prompt_line(StringName(extra_prompt_actions[index]), extra_prompt))
	return lines


func prompt_text() -> String:
	return "\n".join(prompt_lines())


func hold_fraction() -> float:
	return _hold_fraction


## Whether a hold is running. A LATCHED consumer that has had enough -- a tank that
## filled up -- ends it by calling cancel_hold, and an interactor watching this stops
## driving it without treating the release as the player's.
func is_holding() -> bool:
	return _holding


func supports_hold() -> bool:
	return hold_mode != HoldMode.NONE


## Seconds of holding this needs, or 0.0 for a latch that never completes.
func hold_duration() -> float:
	return hold_seconds if hold_mode == HoldMode.TIMED else 0.0


## Takes this in or out of contention, cancelling anything in progress.
func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	monitorable = value
	# The setter runs during scene load, long before _ready; there is nothing to cancel
	# and nobody listening yet.
	if not is_inside_tree():
		return
	if not value:
		cancel_hold()
	availability_changed.emit(is_available())


func focus(interactor: Node3D) -> void:
	if _focused_by == interactor:
		return
	_focused_by = interactor
	focus_gained.emit(interactor)


func unfocus(interactor: Node3D) -> void:
	if _focused_by != interactor:
		return
	_focused_by = null
	cancel_hold()
	focus_lost.emit(interactor)


## Runs a tap, and reports whether it was taken so a caller can fall through when not.
func interact(interactor: Node3D) -> bool:
	if not is_available() or not tap_enabled:
		return false
	_spend()
	interacted.emit(interactor)
	return true


func begin_hold(interactor: Node3D) -> bool:
	if not is_available() or not supports_hold():
		return false
	_holding = true
	_hold_fraction = 0.0
	hold_started.emit(interactor)
	return true


func report_hold(fraction: float) -> void:
	if not _holding:
		return
	_hold_fraction = clampf(fraction, 0.0, 1.0)
	hold_progressed.emit(_hold_fraction)


func complete_hold(interactor: Node3D) -> bool:
	if not _holding or not is_available():
		return false
	_holding = false
	_hold_fraction = 1.0
	_spend()
	hold_completed.emit(interactor)
	return true


## Safe to call when nothing is held; it only says so once.
func cancel_hold() -> void:
	if not _holding:
		return
	_holding = false
	_hold_fraction = 0.0
	hold_cancelled.emit()


func _spend() -> void:
	if not one_shot:
		return
	_used = true
	monitorable = false
	availability_changed.emit(false)


func _format_prompt_line(action: StringName, verb: String) -> String:
	var binding := _binding_text(action)
	return ("%s - %s" % [binding, verb]) if not binding.is_empty() else verb


func _format_hold_line(action: StringName, verb: String) -> String:
	var binding := _binding_text(action)
	return ("HOLD %s - %s" % [binding, verb]) if not binding.is_empty() else ("Hold %s" % verb)


func _binding_text(action: StringName) -> String:
	if action == StringName():
		return ""
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return String(action)
	return events[0].as_text().replace(" - Physical", "")


func _authored_shape() -> CollisionShape3D:
	for child: Node in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			return shape
	return null


## Built only as a fallback, so a bare node is never silently non-functional.
##
## An interactable's volume is authored geometry -- a console face, a doorway -- not a
## radius, so unlike RadarDetectable it takes a shape from the scene when there is one.
## The rule that matters is not "build" or "author" but never to expose a size knob that
## rewrites a shape: fallback_extents is read once, here, and never again.
func _build_fallback_shape() -> void:
	var box := BoxShape3D.new()
	box.size = fallback_extents * 2.0
	var collider := CollisionShape3D.new()
	collider.shape = box
	add_child(collider)
