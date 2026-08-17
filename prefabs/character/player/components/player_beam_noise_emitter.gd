class_name PlayerBeamNoiseEmitter
extends Node

## Publishes the noise the mining beam makes WHERE IT LANDS, which is not where the
## player is standing.
##
## THE SECOND EMITTER, and the reason PlayerNoiseRelay holds a channel per emitter
## rather than one slot. PlayerNoiseEmitter answers "what is the loudest thing
## happening at this body"; that question cannot describe a noise six metres away
## down the barrel, so this node answers a second one. Both wear the same signal and
## the same group, so the relay binds them identically and neither knows about the
## other.
##
## It reports the FULL mining strength. PlayerNoiseEmitter reports
## `mining_muzzle_noise_fraction` of it at the body, which is the 1/2 split: the cut
## is the loud half, the tool in your hands is the quiet half.

## Deliberately the same signature PlayerNoiseEmitter uses. PlayerNoiseRelay is
## duck-typed on it and type-checks nothing.
signal noise_emitted(strength: float, at: Vector3, source: PlayerNoise.Source)

## How far the strength must move before it is re-announced.
const CHANGE_EPSILON := 0.05

## How far the endpoint must move before it is re-announced, in metres.
##
## PlayerNoiseEmitter needs no such rule -- its position is the body's and the relay
## reads it fresh. This one's does not follow anything: the relay re-emits from the
## LAST ANNOUNCED position every emit_interval_s, so a player sweeping the beam
## across a wall would keep feeding the creature the first rock they pointed at.
const POSITION_EPSILON := 1.0

@export var settings: PlayerSettings

## A network driver supplies accepted authority intent while true.
var externally_driven := false

var _strength := 0.0
var _at := Vector3.ZERO
var _announced_strength := -1.0
var _announced_at := Vector3.ZERO

## Read by PlayerNoiseRelay._body_of, which is what attributes the noise to a player
## so Suspicion can build a candidate rather than only a hotspot.
@onready var body: CharacterBody3D = get_parent()
@onready var mining_tool: PlayerMiningTool = %MiningTool


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerBeamNoiseEmitter has no settings; running on PlayerSettings defaults.")
	add_to_group(PlayerNoiseEmitter.EMITTER_GROUP)


func _physics_process(_delta: float) -> void:
	if externally_driven:
		return
	authority_step(mining_tool.is_firing(), mining_tool.beam_endpoint())


## Advances authoritative beam noise from accepted gameplay intent.
##
## `at` is valid on a miss too -- PlayerMiningTool._endpoint_for_hit falls back to the
## far end of the beam -- so cutting vacuum still makes noise out where the beam ends.
func authority_step(firing: bool, at: Vector3) -> void:
	_strength = settings.mining_noise_strength if firing else 0.0
	if _strength > 0.0 and at.is_finite():
		_at = at
	_announce()


## The mining noise the beam is currently making at its endpoint.
func strength() -> float:
	return _strength


## Where that noise is happening, which is the cut and not the player.
func position_of_noise() -> Vector3:
	return _at


func _announce() -> void:
	var moved: bool = _strength > 0.0 and _at.distance_to(_announced_at) >= POSITION_EPSILON
	if absf(_strength - _announced_strength) < CHANGE_EPSILON and not moved:
		return
	_announced_strength = _strength
	_announced_at = _at
	noise_emitted.emit(_strength, _at, PlayerNoise.Source.MINING)
