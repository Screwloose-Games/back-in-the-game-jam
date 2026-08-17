class_name AlienSfx
extends Node3D

## Everything the creature sounds like, as three channels rather than four
## sounds: a strike is its voice and its tentacles at once, so those cannot share
## a player.
##
## alert() and attack() are the whole interface, and nothing calls them yet — the
## creature is a navigation agent with no perception or attack today. When that
## layer lands it calls these; the movement loop already runs off the agent.

## Body speed below which the creature counts as still. Well under its slowest
## deliberate crawl, so it only rejects steering jitter.
const MOVE_EPSILON := 0.05

@export var movement_near_loop: AudioStream
@export var voice_alerted: AudioStream
@export var voice_attack: AudioStream
@export var tentacle_attack: AudioStream

var _moving := false

@onready var agent: AlienNavAgent = %AlienNavAgent
@onready var movement_player: AudioStreamPlayer3D = $MovementLoop
@onready var voice_player: AudioStreamPlayer3D = $Voice
@onready var attack_player: AudioStreamPlayer3D = $Attack


func _ready() -> void:
	movement_player.stream = movement_near_loop


## "Near" is the channel's max_distance rather than a radius test here: the loop
## runs whenever the creature is under way, and distance decides who can hear it.
func _physics_process(_delta: float) -> void:
	var moving := agent.actual_speed() > MOVE_EPSILON
	if moving == _moving:
		return
	_moving = moving
	if moving:
		movement_player.play(0.0)
	else:
		movement_player.stop()


## The creature has noticed something. One per acquisition, not per frame.
func alert() -> void:
	voice_player.stream = voice_alerted
	voice_player.play(0.0)


## A strike: the voice and the tentacles land together, on separate channels so
## neither cuts the other off.
func attack() -> void:
	voice_player.stream = voice_attack
	voice_player.play(0.0)
	attack_player.stream = tentacle_attack
	attack_player.play(0.0)
