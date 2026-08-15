class_name PlayerNoiseEmitter
extends Node

## Publishes everything the player does that the creature can hear. It reports
## the loudest current source rather than a sum, because the creature is steered
## by the strongest thing it hears; `AlienPerception` is still a stub, so this
## also puts itself in a group the perception layer can find it by.

## The loudest thing the player is currently doing, in noise units.
signal noise_emitted(strength: float, at: Vector3, source: PlayerNoise.Source)

## Anything listening for player noise finds emitters through this group.
const EMITTER_GROUP := &"noise_emitter"

## How far the strength must move before it is re-announced.
const CHANGE_EPSILON := 0.05

@export var settings: PlayerSettings

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
	var thrust_noise := PlayerNoise.thrust_strength(
		input.thrust_fraction(), settings.thrust_noise_strength
	)
	var mining_noise := settings.mining_noise_strength if mining_tool.is_firing() else 0.0

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
func to_stimulus() -> AlienStimulus:
	if _strength <= 0.0:
		return null
	return AlienStimulus.create(AlienPerception.StimulusType.SOUND, body.global_position, _strength)


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
