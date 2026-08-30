class_name PlayerHudBinding
extends Node

## Instances this player's HUD and keeps its HudState fed. The HUD hangs off the
## player rather than the level so a remote peer's copy can simply be switched
## off with the rest of their prefab.

## Swap layouts by pointing this at a different prefab_hud_*.tscn. Leave it null
## for a headless player, or for one whose HUD the level owns.
@export var hud_scene: PackedScene = preload("res://prefabs/ui/hud/prefab_hud_04.tscn")

## The HUD is hidden for a player who is not looking through their own camera.
@export var hud_visible: bool = true

## Smallest share of the pool that flashes the damage overlay.
##
## Continuous sources -- suffocation, a live arc -- bill a sliver per physics frame,
## and a flash per sliver is a solid red screen. The overlay is for blows; the visor
## carries everything slower than one.
@export_range(0.0, 0.5, 0.005) var flash_min_severity: float = 0.03

var _hud: HudVariant

@onready var state: HudState = %HudState
@onready var oxygen: PlayerOxygen = %Oxygen
@onready var power: PlayerPowerClient = %PowerClient
@onready var tether: PlayerTether = %Tether
@onready var radar: PlayerRadarDetector = %Radar
@onready var health: PlayerHealth = %Health


func _ready() -> void:
	_instance_hud()
	oxygen.oxygen_changed.connect(_on_oxygen_changed)
	power.charge_changed.connect(_on_power_changed)
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_health_damaged)
	health.electrified_changed.connect(_on_electrified_changed)
	tether.clipped.connect(_on_tether_changed.unbind(1))
	tether.unclipped.connect(_on_tether_changed.unbind(1))
	radar.pulse_started.connect(state.begin_radar_sweep)
	radar.detected_detectable.connect(_on_radar_detected)
	VoiceService.microphone_state_changed.connect(_on_microphone_state_changed)
	VoiceService.local_level_changed.connect(_on_local_level_changed)
	_push_all()


func _process(_delta: float) -> void:
	# Only the tether length changes continuously; the rest arrive on signals.
	if tether.is_attached():
		state.tether_metres = tether.distance()


## The instanced HUD, or null when hud_scene was left empty.
func hud() -> HudVariant:
	return _hud


func _instance_hud() -> void:
	if hud_scene == null:
		return
	_hud = hud_scene.instantiate() as HudVariant
	if _hud == null:
		push_warning("PlayerHudBinding.hud_scene is not a HudVariant; nothing was instanced.")
		return
	add_child(_hud)
	_hud.visible = hud_visible
	_hud.bind(state)


## Feeds the level's quota terminals the same state the HUD reads.
##
func _push_all() -> void:
	state.oxygen = oxygen.fraction()
	state.power = power.fraction()
	state.electrified = health.is_electrified()
	_push_health()
	_on_tether_changed()
	_on_microphone_state_changed(VoiceService.is_microphone_live(), VoiceService.is_transmitting())
	_update_status()


func _on_microphone_state_changed(live: bool, transmitting: bool) -> void:
	state.voice_live = live
	state.voice_transmitting = transmitting
	if not live:
		state.voice_loudness = 0.0


func _on_local_level_changed(level: float) -> void:
	state.voice_loudness = level


## The transform belongs here rather than in the widget, which knows nothing about 3D,
## or in HudState, which is a mailbox.
func _on_radar_detected(detectable: RadarDetectable) -> void:
	state.report_radar_contact(radar.local_offset(detectable.global_position))


func _on_oxygen_changed(fraction: float) -> void:
	state.oxygen = fraction
	_update_status()


func _on_power_changed(fraction: float) -> void:
	state.power = fraction
	_update_status()


func _on_health_changed(_fraction: float) -> void:
	_push_health()


func _on_health_damaged(amount: float, _source: int) -> void:
	var severity := amount / maxf(health.settings.max_health, 0.001)
	if severity >= flash_min_severity:
		state.report_damage(severity)


func _on_electrified_changed(active: bool) -> void:
	state.electrified = active


func _push_health() -> void:
	state.health = health.fraction()
	state.health_points = health.health


func _on_tether_changed() -> void:
	state.tether_attached = tether.is_attached()
	state.tether_metres = tether.distance()


## Status reads off whichever of the two resources is in worse shape, because
## either one running out kills you and the face should say so.
##
## HEALTH IS DELIBERATELY NOT IN HERE. PlayerSfx plays its helmet downgrade cue on
## every status downgrade, so folding health in would turn a rare 'you are in
## trouble' sound into a hit confirm on every bump. The visor carries injury.
func _update_status() -> void:
	state.status = HudState.status_for(minf(state.oxygen, state.power))
