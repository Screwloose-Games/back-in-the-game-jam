class_name HudState
extends Node

signal power_changed(fraction: float)
signal oxygen_changed(fraction: float)
signal tether_changed(attached: bool, metres: float)
signal contacts_changed(contacts: PackedVector3Array)
signal objective_changed(shown: bool, at: Vector2)
signal status_changed(status: int)
signal voice_changed(live: bool, transmitting: bool, loudness: float)
signal mineral_score_changed(score: int)

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

var mineral_score: int = 0:
	set(value):
		if value == mineral_score:
			return
		mineral_score = value
		mineral_score_changed.emit(mineral_score)

## Whether the microphone is open at all. A voice-activated gate means an enabled
## microphone is a hot one, so this has to be visible whenever it is true.
var voice_live := false:
	set(value):
		voice_live = value
		_announce_voice()

var voice_transmitting := false:
	set(value):
		voice_transmitting = value
		_announce_voice()

var voice_loudness := 0.0:
	set(value):
		voice_loudness = clampf(value, 0.0, 1.0)
		_announce_voice()

var _announced_power := -1.0
var _announced_oxygen := -1.0
var _announced_metres := -1
var _announced_attached := false
var _announced_voice_live := false
var _announced_voice_transmitting := false
var _announced_voice_loudness := -1.0


func announce_all() -> void:
	power_changed.emit(power)
	oxygen_changed.emit(oxygen)
	tether_changed.emit(tether_attached, tether_metres)
	contacts_changed.emit(contacts)
	objective_changed.emit(objective_shown, objective_at)
	status_changed.emit(status)
	voice_changed.emit(voice_live, voice_transmitting, voice_loudness)
	mineral_score_changed.emit(mineral_score)


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


func _announce_voice() -> void:
	if (
		voice_live == _announced_voice_live
		and voice_transmitting == _announced_voice_transmitting
		and absf(voice_loudness - _announced_voice_loudness) < CHANGE_EPSILON
	):
		return
	_announced_voice_live = voice_live
	_announced_voice_transmitting = voice_transmitting
	_announced_voice_loudness = voice_loudness
	voice_changed.emit(voice_live, voice_transmitting, voice_loudness)


func _announce_tether() -> void:
	var whole := roundi(tether_metres)
	if whole == _announced_metres and tether_attached == _announced_attached:
		return
	_announced_metres = whole
	_announced_attached = tether_attached
	tether_changed.emit(tether_attached, tether_metres)
