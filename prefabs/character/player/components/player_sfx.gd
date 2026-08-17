class_name PlayerSfx
extends Node3D

## What the suit sounds like, minus its thrusters — those are eight positioned
## emitters of their own and live in PlayerThrusterSfx.
##
## The children are one player per channel rather than one per sound: sounds that
## must overlap get their own channel, and sounds that should cut each other off
## share one.

## How far down a glancing impact is mixed relative to one at reference speed.
const IMPACT_QUIETEST_DB := -18.0

@export_group("Impacts")
@export var suit_impact_wall: AudioStream
@export var death_impact: AudioStream

## Closing speed at which an impact plays at the channel's full volume. Mirrors
## PlayerSettings.impact_reference_speed, which prices the noise the same way.
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var impact_reference_speed: float = 8.0

## Below this the suit is scraping along a wall rather than hitting it.
@export_range(0.0, 5.0, 0.1, "suffix:m/s") var impact_min_speed: float = 0.8

@export_group("Helmet")
@export var helmet_failure: AudioStream
@export var status_downgrade: AudioStream

var _last_status: int = HudState.Status.NOMINAL
var _impact_base_db := 0.0

@onready var power: PlayerPowerClient = %PowerClient
@onready var grab: PlayerGrab = %Grab
@onready var collision: PlayerCollisionResponse = %CollisionResponse
@onready var life: PlayerLife = %Life
@onready var visibility: PlayerVisibility = %Visibility
@onready var state: HudState = %HudState
@onready var impact_player: AudioStreamPlayer3D = $Impact
@onready var helmet_player: AudioStreamPlayer = $Helmet


func _ready() -> void:
	_impact_base_db = impact_player.volume_db
	grab.took_hold.connect(_on_took_hold)
	collision.impacted.connect(_on_impacted)
	life.died.connect(_on_died)
	# The helmet cues play inside your own head, and HudState still emits on a
	# remote peer's copy — PlayerUi frees their HUD but not their state, and a
	# disabled process_mode does not stop signals.
	if not visibility.is_local_player:
		return
	_last_status = state.status
	power.power_lost.connect(_on_power_lost)
	state.status_changed.connect(_on_status_changed)


## Impacts arrive with a negative closing speed — the signal is only emitted when
## the suit is moving into the surface. Anything gentler than a knock is the
## scrape the collision response already handles silently.
func _on_impacted(closing_speed: float, _at: Vector3) -> void:
	var speed := absf(closing_speed)
	if speed < impact_min_speed:
		return
	var hardness := clampf(inverse_lerp(impact_min_speed, impact_reference_speed, speed), 0.0, 1.0)
	impact_player.volume_db = _impact_base_db + lerpf(IMPACT_QUIETEST_DB, 0.0, hardness)
	impact_player.stream = suit_impact_wall
	impact_player.play(0.0)


## Death shares the impact channel and takes it back to full volume: it should cut
## off whatever the suit was scraping against on the way in.
func _on_died() -> void:
	impact_player.volume_db = _impact_base_db
	impact_player.stream = death_impact
	impact_player.play(0.0)


func _on_power_lost() -> void:
	helmet_player.stream = helmet_failure
	helmet_player.play(0.0)


## Downgrades only. Status is ordered NOMINAL, STRAINED, CRITICAL, so worse is
## larger, and the comparison also absorbs the unconditional re-emission
## HudState.announce_all() makes every time a HUD binds.
func _on_status_changed(status: int) -> void:
	if status > _last_status and not _helmet_failure_sounding():
		helmet_player.stream = status_downgrade
		helmet_player.play(0.0)
	_last_status = status


## An empty suit fires both cues in the same frame — power_lost, then the status
## the same drop pushed to CRITICAL — and they share a channel. The failure is the
## one worth hearing, so it is not interrupted by the downgrade that follows it.
func _helmet_failure_sounding() -> bool:
	return helmet_player.playing and helmet_player.stream == helmet_failure


## The sound belongs to the thing picked up, not to the hands, so it is asked for
## rather than played here — same duck-typed check PowerClient makes on the box.
func _on_took_hold(object: RigidBody3D) -> void:
	if object != null and object.has_method("play_grab_sfx"):
		object.call("play_grab_sfx")
