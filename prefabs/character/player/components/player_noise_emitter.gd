class_name PlayerNoiseEmitter
extends Node

## Publishes everything the player does that the creature can hear AT THE PLAYER'S
## BODY. It reports the loudest current source rather than a sum, because the
## creature is steered by the strongest thing it hears, and it puts itself in a
## group the perception layer finds it by.
##
## Mining is the one source that does not happen here: the cut is out at the end of
## the beam, so PlayerBeamNoiseEmitter reports it at full strength from there and
## this node keeps only `mining_muzzle_noise_fraction` of it for the gun in your
## hands. Both are bound by PlayerNoiseRelay, which holds a channel per emitter.

## The loudest thing the player is currently doing, in noise units.
signal noise_emitted(strength: float, at: Vector3, source: PlayerNoise.Source)

## Anything listening for player noise finds emitters through this group.
const EMITTER_GROUP := &"noise_emitter"

## How far the strength must move before it is re-announced.
const CHANGE_EPSILON := 0.05

@export var settings: PlayerSettings

## A network driver supplies accepted authority intent while true.
var externally_driven := false

var _strength := 0.0
var _source: PlayerNoise.Source = PlayerNoise.Source.THRUST
var _impact_strength := 0.0
var _announced_strength := -1.0

@onready var body: CharacterBody3D = get_parent()
@onready var input: PlayerInput = %Input
@onready var mining_tool: PlayerMiningTool = %MiningTool
@onready var collision: PlayerCollisionResponse = %CollisionResponse


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerNoiseEmitter has no settings; running on PlayerSettings defaults.")
	add_to_group(EMITTER_GROUP)
	collision.impacted.connect(_on_impacted)


func _physics_process(delta: float) -> void:
	if externally_driven:
		return
	authority_step(delta, input.thrust_fraction(), mining_tool.is_firing())


## Advances authoritative noise from accepted gameplay intent.
func authority_step(delta: float, thrust_fraction: float, mining_active: bool) -> void:
	var safe_thrust := clampf(thrust_fraction, 0.0, 1.0) if is_finite(thrust_fraction) else 0.0
	var thrust_noise := PlayerNoise.thrust_strength(safe_thrust, settings.thrust_noise_strength)
	# Only the quieter half. The cut happens at the far end of the beam and
	# PlayerBeamNoiseEmitter reports that, at full strength, from out there.
	var mining_noise := (
		settings.mining_noise_strength * settings.mining_muzzle_noise_fraction
		if mining_active
		else 0.0
	)

	# An impact is an instant, so it decays rather than persisting like the
	# other two, which are held for as long as the player holds the control.
	_impact_strength = maxf(_impact_strength - settings.impact_noise_strength * delta, 0.0)

	_strength = PlayerNoise.loudest(
		PackedFloat32Array([thrust_noise, mining_noise, _impact_strength])
	)
	_source = _loudest_source(thrust_noise, mining_noise)
	_announce()


## The loudest noise the player is making right now.
func strength() -> float:
	return _strength


## How far that noise carries, in metres.
func audible_radius() -> float:
	return PlayerNoise.audible_radius(_strength, settings.noise_metres_per_unit)


func source() -> PlayerNoise.Source:
	return _source


## Builds the stimulus the creature's perception layer consumes. Returns null
## while the player is making no noise at all.
# func to_stimulus() -> AlienStimulus:
# 	if _strength <= 0.0:
# 		return null
# 	return AlienStimulus.create(AlienPerception.StimulusType.SOUND, body.global_position, _strength)


func _on_impacted(closing_speed: float, _at: Vector3) -> void:
	_impact_strength = maxf(
		_impact_strength,
		PlayerNoise.impact_strength(
			closing_speed, settings.impact_reference_speed, settings.impact_noise_strength
		)
	)


func _loudest_source(thrust_noise: float, mining_noise: float) -> PlayerNoise.Source:
	if mining_noise >= thrust_noise and mining_noise >= _impact_strength:
		return PlayerNoise.Source.MINING
	if _impact_strength >= thrust_noise:
		return PlayerNoise.Source.IMPACT
	return PlayerNoise.Source.THRUST


func _announce() -> void:
	if absf(_strength - _announced_strength) < CHANGE_EPSILON:
		return
	_announced_strength = _strength
	noise_emitted.emit(_strength, body.global_position, _source)
