class_name HudState
extends Node

signal power_changed(fraction: float)
signal oxygen_changed(fraction: float)
signal tether_changed(attached: bool, metres: float)
signal contacts_changed(contacts: PackedVector3Array)
signal objective_changed(shown: bool, at: Vector2)
signal status_changed(status: int)

enum Status { NOMINAL, STRAINED, CRITICAL }

const CHANGE_EPSILON := 0.001

const STRAINED_BELOW := 0.55
const CRITICAL_BELOW := 0.25

var power := 1.0:
	set(value):
		power = clampf(value, 0.0, 1.0)
		if absf(power - _announced_power) < CHANGE_EPSILON:
			return
		_announced_power = power
		power_changed.emit(power)

var oxygen := 1.0:
	set(value):
		oxygen = clampf(value, 0.0, 1.0)
		if absf(oxygen - _announced_oxygen) < CHANGE_EPSILON:
			return
		_announced_oxygen = oxygen
		oxygen_changed.emit(oxygen)

var tether_metres := 0.0:
	set(value):
		tether_metres = maxf(value, 0.0)
		_announce_tether()

var tether_attached := false:
	set(value):
		tether_attached = value
		_announce_tether()

var contacts := PackedVector3Array():
	set(value):
		contacts = value
		contacts_changed.emit(contacts)

var objective_shown := false
var objective_at := Vector2.ZERO

var status: Status = Status.NOMINAL:
	set(value):
		if value == status:
			return
		status = value
		status_changed.emit(status)

var _announced_power := -1.0
var _announced_oxygen := -1.0
var _announced_metres := -1
var _announced_attached := false


func announce_all() -> void:
	power_changed.emit(power)
	oxygen_changed.emit(oxygen)
	tether_changed.emit(tether_attached, tether_metres)
	contacts_changed.emit(contacts)
	objective_changed.emit(objective_shown, objective_at)
	status_changed.emit(status)


static func status_for(fraction: float) -> Status:
	if fraction < CRITICAL_BELOW:
		return Status.CRITICAL
	if fraction < STRAINED_BELOW:
		return Status.STRAINED
	return Status.NOMINAL


func set_objective(shown: bool, at: Vector2) -> void:
	if shown == objective_shown and at.is_equal_approx(objective_at):
		return
	objective_shown = shown
	objective_at = at
	objective_changed.emit(objective_shown, objective_at)


func _announce_tether() -> void:
	var whole := roundi(tether_metres)
	if whole == _announced_metres and tether_attached == _announced_attached:
		return
	_announced_metres = whole
	_announced_attached = tether_attached
	tether_changed.emit(tether_attached, tether_metres)
