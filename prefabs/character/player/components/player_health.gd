class_name PlayerHealth
extends Node

## This player's damage pool. Hazards bill it, it seals itself once nothing has hit
## you for a while, and at zero it hands off to PlayerLife rather than dying itself.
##
## IT NEVER NAMES PlayerLife. `depleted` is the whole interface, which is what keeps
## the two components' @onready lookups from pointing at each other.

## The pool moved, however it moved. Epsilon-gated, so a slow drain does not redraw
## the HUD every frame.
signal health_changed(fraction: float)

## One hit landed. `amount` is what was actually taken, which is less than what was
## asked for when the hit is the one that empties the pool.
signal damaged(amount: float, source: int)

## The suit is sealing itself. Not emitted by refill(), which is not recovery.
signal healed(amount: float)

## The pool reached zero. Edge-gated, and PlayerLife is what listens.
signal depleted

## An arc has hold of you. Refreshed by the hazard every frame it bills and lapsing on
## its own, so nothing has to remember to switch it off -- including a hazard that is
## freed, or a player who dies inside one.
signal electrified_changed(active: bool)

## What billed the last hit, for a cue or a readout that wants to say why.
enum Source { UNKNOWN, IMPACT, SUFFOCATION, GAS_POD, ARC }

## Matches HudState's gate, the same way Oxygen's does.
const CHANGE_EPSILON := 0.001

## After CollisionResponse, which owns move_and_slide at 100. An impact billed this
## step has to land inside this step's recovery decision, or recovery restarts a
## frame early.
const PHYSICS_PRIORITY := 110

## How long one electrify() call holds. Several frames, so a hazard billing every
## frame keeps it lit and one that stops lets it drop inside a blink.
const ELECTRIFIED_HOLD := 0.25

@export var settings: PlayerSettings

## A network driver stands this down, exactly as it does Life: nobody dies online,
## so nobody bleeds online.
var externally_driven := false

## The pool in points. Only ratios reach the HUD.
var health := 0.0

var _announced_fraction := -1.0
var _seconds_since_damage := INF
var _electrified_left := 0.0
var _was_depleted := false

@onready var oxygen: PlayerOxygen = %Oxygen
@onready var collision: PlayerCollisionResponse = %CollisionResponse


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerHealth has no settings; running on PlayerSettings defaults.")
	health = settings.max_health * clampf(settings.health_start_fraction, 0.0, 1.0)
	collision.impacted.connect(_on_impacted)
	_announce()


func _physics_process(delta: float) -> void:
	if externally_driven:
		return
	authority_step(delta)


## Advances authoritative suffocation and recovery.
func authority_step(delta: float) -> void:
	_seconds_since_damage += delta
	# Ahead of the suffocation branch, which returns early: an arc that lets go while
	# you are out of air still has to stop crackling.
	if _electrified_left > 0.0:
		_electrified_left = maxf(_electrified_left - delta, 0.0)
		if _electrified_left <= 0.0:
			electrified_changed.emit(false)
	# is_empty() rather than the emptied signal: `emptied` is an EDGE and suffocation
	# is a STATE. A player who runs out, gets air back and runs out again has to bleed
	# both times, and one whose air returns has to stop.
	if oxygen.is_empty():
		take_damage(settings.suffocation_damage_per_second * delta, Source.SUFFOCATION)
		return
	var regen := PlayerHealthModel.regen_rate(
		_seconds_since_damage, settings.health_regen_delay, settings.health_regen_per_second
	)
	if regen > 0.0:
		heal(regen * delta)


## Takes what it can and returns what was actually taken, the same way
## PlayerPowerClient.spend() does -- a caller that assumed it got what it asked for
## would report a killing blow that never landed.
func take_damage(amount: float, source := Source.UNKNOWN) -> float:
	var dealt := minf(maxf(amount, 0.0), health)
	if dealt <= 0.0:
		return 0.0
	health = PlayerHealthModel.step(health, settings.max_health, -dealt)
	_seconds_since_damage = 0.0
	_announce()
	damaged.emit(dealt, source)
	if health <= 0.0 and not _was_depleted:
		_was_depleted = true
		depleted.emit()
	return dealt


## Puts back what it can and returns what was accepted.
func heal(amount: float) -> float:
	if _was_depleted:
		return 0.0
	var restored := minf(maxf(amount, 0.0), maxf(settings.max_health - health, 0.0))
	if restored <= 0.0:
		return 0.0
	health = PlayerHealthModel.step(health, settings.max_health, restored)
	_announce()
	healed.emit(restored)
	return restored


func fraction() -> float:
	return PlayerHealthModel.fraction(health, settings.max_health)


func is_depleted() -> bool:
	return health <= 0.0


## Says an arc currently has hold of this suit. Called every frame the arc bills, so
## it refreshes rather than accumulates.
func electrify(seconds: float = ELECTRIFIED_HOLD) -> void:
	var was_live := _electrified_left > 0.0
	_electrified_left = maxf(_electrified_left, seconds)
	if not was_live:
		electrified_changed.emit(true)


func is_electrified() -> bool:
	return _electrified_left > 0.0


## Seconds until the suit starts sealing itself, or zero while it already is.
func seconds_until_regen() -> float:
	return maxf(settings.health_regen_delay - _seconds_since_damage, 0.0)


## Back to full, for a revive. Deliberately silent on `healed`, which means the suit
## is recovering -- a respawn is not recovery.
func refill() -> void:
	health = settings.max_health
	_was_depleted = false
	_seconds_since_damage = INF
	if _electrified_left > 0.0:
		_electrified_left = 0.0
		electrified_changed.emit(false)
	_announce()


## Applies a replicated ratio and updates presentation, but deliberately skips the
## authority-only depleted event, exactly as Oxygen and PowerClient do.
func apply_network_fraction(value: float) -> void:
	var safe_value := clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	health = maxf(settings.max_health, 0.0) * safe_value
	_was_depleted = health <= 0.0
	_announce()


func _on_impacted(closing_speed: float, _at: Vector3) -> void:
	take_damage(settings.impact_damage_for(closing_speed), Source.IMPACT)


func _announce() -> void:
	var current := fraction()
	if absf(current - _announced_fraction) < CHANGE_EPSILON:
		return
	_announced_fraction = current
	health_changed.emit(current)
