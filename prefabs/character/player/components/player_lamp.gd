class_name PlayerLamp
extends Node

## Drives the helmet lamp from available power. The beam dims and shortens as
## the suit runs down and flickers near the bottom, so the light going wrong is
## the warning that power is going — light is a resource in this game.

signal lamp_toggled(lit: bool)

@export var settings: PlayerSettings

## A network driver sets this before the node enters the tree, forwards toggle
## requests to authority, and applies replicated presentation explicitly.
var externally_driven := false

var _lit := true
var _flicker_until := 0.0
var _next_flicker := 0.0
var _random := RandomNumberGenerator.new()

@onready var lamp: SpotLight3D = %HelmetLamp
@onready var input: PlayerInput = %Input
@onready var power: PlayerPowerClient = %PowerClient
@onready var hands: PlayerHands = %Hands
@onready var visibility: PlayerVisibility = %Visibility


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerLamp has no settings; running on PlayerSettings defaults.")
	_random.randomize()
	_apply_static_settings()
	_lit = settings.lamp_starts_on
	if not externally_driven:
		input.lamp_toggled.connect(toggle)


func _process(delta: float) -> void:
	if externally_driven:
		return
	authority_step(delta)


## Advances authoritative lamp state, including its power cost.
func authority_step(delta: float) -> void:
	if _lit:
		# An unlit lamp costs nothing, which is what makes flying blind a real
		# way to buy digging time.
		power.spend(settings.lamp_power_per_second * delta)
	_update_beam(delta)


func is_lit() -> bool:
	return _lit and power.has_power()


## The switch position independent of whether the battery can light the beam.
func requested_lit() -> bool:
	return _lit


func toggle() -> void:
	set_lit(not _lit)


func set_lit(lit: bool) -> void:
	if lit == _lit:
		return
	_lit = lit
	lamp_toggled.emit(_lit)


## Applies transport-owned state without spending power or producing gameplay.
func apply_network_presentation(
	requested: bool,
	effective: bool,
	charge_fraction: float,
) -> void:
	set_lit(requested)
	_apply_beam(effective, charge_fraction, 0.0, false)


func _apply_static_settings() -> void:
	lamp.light_color = settings.helmet_lamp_color
	lamp.shadow_enabled = settings.helmet_lamp_shadows
	lamp.spot_angle = settings.helmet_lamp_angle
	lamp.spot_angle_attenuation = settings.helmet_lamp_angle_attenuation
	lamp.spot_attenuation = settings.helmet_lamp_attenuation
	# A lamp inside a visor, a hand's width from a laser, casts shadows off both
	# and blacks out its own beam. Each lamp drops the suit it is mounted on and
	# keeps the other one, so an ally's light still throws your shadow.
	lamp.shadow_caster_mask = (
		PlayerRenderLayers.own_lamp_shadow_caster_mask()
		if visibility.is_local_player
		else PlayerRenderLayers.peer_lamp_shadow_caster_mask()
	)


## Brightness and reach both follow the charge, so a dying suit does not simply
## get dimmer — the dark closes in.
func _update_beam(delta: float) -> void:
	_apply_beam(is_lit(), power.fraction(), delta, true)


func _apply_beam(
	effective: bool,
	charge_fraction: float,
	delta: float,
	allow_flicker: bool,
) -> void:
	if not effective:
		lamp.visible = false
		return
	lamp.visible = true

	var charge := clampf(charge_fraction, 0.0, 1.0) if is_finite(charge_fraction) else 0.0
	var reach_floor := settings.helmet_lamp_min_range_fraction
	lamp.spot_range = settings.helmet_lamp_range * lerpf(reach_floor, 1.0, charge)
	var flicker := _flicker_scale(delta, charge) if allow_flicker else 1.0
	lamp.light_energy = settings.helmet_lamp_energy * charge * flicker


## Flickers get more frequent as the charge falls. Above the flicker depth the
## beam is steady, so a healthy suit never stutters.
func _flicker_scale(delta: float, charge: float) -> float:
	if settings.lamp_flicker_depth <= 0.0 or charge > settings.lamp_flicker_depth:
		return 1.0

	_next_flicker -= delta
	if _next_flicker <= 0.0:
		var rate := settings.lamp_flicker_rate_max * (1.0 - charge / settings.lamp_flicker_depth)
		_next_flicker = 1.0 / maxf(rate, 0.01)
		_flicker_until = settings.lamp_flicker_duration

	if _flicker_until > 0.0:
		_flicker_until -= delta
		return _random.randf_range(0.15, 0.6)
	return 1.0
