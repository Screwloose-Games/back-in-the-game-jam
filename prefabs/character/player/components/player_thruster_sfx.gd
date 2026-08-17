class_name PlayerThrusterSfx
extends Node3D

## The suit's eight thrusters, each heard from where it is bolted rather than
## from the middle of you.
##
## A thruster sits opposite the push it makes: the one that shoves you up is
## underneath you, and the one that shoves you right is on your left. That is what
## makes swapping direction audible — right becomes left and the sound crosses the
## helmet — which a single shared emitter could never say.

## Indices into THRUSTERS, and the order its entries are written in.
enum Thruster { FORWARD, BACK, LEFT, RIGHT, UP, DOWN, ROLL_LEFT, ROLL_RIGHT }

## Node name stem, mount point in body-local metres, and a fixed detune.
##
## The mount is the reaction side: negate it and you have the direction that
## thruster pushes. The two roll pairs are the exception the physics does not
## dictate — a couple could be mounted several ways — so they sit just above the
## opposite ear, where a roll is easiest to place by hearing.
##
## The detune matters more than it looks. All eight play the same Thruster_Loop,
## and identical loops from different points comb-filter into one flat tone the
## moment two fire together; a few percent apart they stay separate sources.
const THRUSTERS: Array = [
	{"name": "Forward", "at": Vector3(0.0, 0.0, 0.45), "pitch": 0.97},
	{"name": "Back", "at": Vector3(0.0, 0.0, -0.45), "pitch": 1.03},
	{"name": "Left", "at": Vector3(0.45, 0.0, 0.0), "pitch": 0.99},
	{"name": "Right", "at": Vector3(-0.45, 0.0, 0.0), "pitch": 1.01},
	{"name": "Up", "at": Vector3(0.0, -0.45, 0.0), "pitch": 0.95},
	{"name": "Down", "at": Vector3(0.0, 0.45, 0.0), "pitch": 1.05},
	{"name": "RollLeft", "at": Vector3(0.22, 0.16, 0.0), "pitch": 1.06},
	{"name": "RollRight", "at": Vector3(-0.22, 0.16, 0.0), "pitch": 0.94},
]

## Below this a thruster is not firing. The thrust actions already carry a 0.2
## deadzone, so this only rejects float dust.
const FIRE_EPSILON := 0.01

## Quietest a firing thruster is mixed, as a linear gain. Thrust is clamped to a
## unit sphere, so holding three axes at once leaves each one well under 1.0 —
## without a floor a diagonal burn would be inaudible.
const QUIETEST_GAIN := 0.35

@export var thruster_on: AudioStream
@export var thruster_loop: AudioStream
@export var thruster_off: AudioStream

## Scales every mount point away from the body. The hull is a 0.4 m sphere, so
## much below 1.0 puts the thrusters inside you and the panning collapses.
@export_range(0.25, 3.0, 0.05) var mount_scale: float = 1.0

## A network driver pushes this copy's controls while true, because a remote
## player's %Input is disabled and reads zero. See apply_network_controls().
var externally_driven := false

var _network_thrust := Vector3.ZERO
var _network_roll := 0.0
var _firing: Array[bool] = []
var _loops: Array[AudioStreamPlayer3D] = []
var _edges: Array[AudioStreamPlayer3D] = []
var _loop_base_db: Array[float] = []

@onready var input: PlayerInput = %Input


func _ready() -> void:
	for entry: Dictionary in THRUSTERS:
		var stem: String = entry["name"]
		var loop := get_node(NodePath(stem + "Loop")) as AudioStreamPlayer3D
		var edge := get_node(NodePath(stem + "Edge")) as AudioStreamPlayer3D
		var at: Vector3 = entry["at"] * mount_scale
		var pitch: float = entry["pitch"]
		loop.position = at
		edge.position = at
		loop.pitch_scale = pitch
		edge.pitch_scale = pitch
		loop.stream = thruster_loop
		_loops.append(loop)
		_edges.append(edge)
		_loop_base_db.append(loop.volume_db)
		_firing.append(false)


func _physics_process(_delta: float) -> void:
	var thrust := _thrust()
	var roll := _roll()
	# Each control splits into the two thrusters that could serve it, and only the
	# one being asked for gets a positive magnitude.
	_drive(Thruster.FORWARD, maxf(-thrust.z, 0.0))
	_drive(Thruster.BACK, maxf(thrust.z, 0.0))
	_drive(Thruster.LEFT, maxf(-thrust.x, 0.0))
	_drive(Thruster.RIGHT, maxf(thrust.x, 0.0))
	_drive(Thruster.UP, maxf(thrust.y, 0.0))
	_drive(Thruster.DOWN, maxf(-thrust.y, 0.0))
	_drive(Thruster.ROLL_LEFT, maxf(-roll, 0.0))
	_drive(Thruster.ROLL_RIGHT, maxf(roll, 0.0))


## Applies replicated controls for a copy this machine does not drive.
func apply_network_controls(thrust: Vector3, roll: float) -> void:
	_network_thrust = thrust if thrust.is_finite() else Vector3.ZERO
	_network_roll = clampf(roll, -1.0, 1.0) if is_finite(roll) else 0.0


## Whether a given thruster is currently firing. For tests and for anything that
## wants to hang an exhaust plume off the same edges.
func is_firing(thruster: Thruster) -> bool:
	return _firing[thruster]


func _thrust() -> Vector3:
	return _network_thrust if externally_driven else input.thrust


func _roll() -> float:
	return _network_roll if externally_driven else input.roll


## One thruster's whole story: how hard it is pushing, and the two edges either
## side of that. Volume tracks the magnitude every frame so an analogue stick
## reads as a softer burn rather than an on-off switch.
func _drive(thruster: Thruster, magnitude: float) -> void:
	var firing := magnitude > FIRE_EPSILON
	if firing:
		var gain := clampf(magnitude, QUIETEST_GAIN, 1.0)
		_loops[thruster].volume_db = _loop_base_db[thruster] + linear_to_db(gain)
	if firing == _firing[thruster]:
		return
	_firing[thruster] = firing
	if firing:
		_play_edge(thruster, thruster_on)
		_loops[thruster].play(0.0)
	else:
		_loops[thruster].stop()
		_play_edge(thruster, thruster_off)


func _play_edge(thruster: Thruster, stream: AudioStream) -> void:
	_edges[thruster].stream = stream
	_edges[thruster].play(0.0)
