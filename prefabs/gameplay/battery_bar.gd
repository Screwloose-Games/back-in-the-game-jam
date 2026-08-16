class_name BatteryBar
extends Node3D

## The life support cube's charge readout: five segments on the top face and five
## on the bottom, green while there is room to spare, yellow once there is not,
## and one red segment blinking when there nearly is not.
##
## The rules live here as static functions rather than in the shader, so the
## thing that encodes the spec is the thing a test can call.

## Segments in the bar. Each is a fifth of the box, which is what makes the gauge
## worth reading: a segment gone is twenty per cent gone.
const SEGMENTS := 5

## Lit segments at or below which the bar alarms.
const CRITICAL_SEGMENTS := 1

## Lit segments at or below which the bar reads as a warning.
const WARN_SEGMENTS := 3

@export_group("Colors")

## The full end of the bar. Same green as the cube's lamp, so the two readouts
## agree about what a healthy box looks like. Held separately rather than read
## off the cube because the bar and the lamp are tuned against different
## backgrounds and should be able to move apart.
@export var full_color := Color(0.35, 1.0, 0.45)

@export var warn_color := Color(1.0, 0.78, 0.2)

## Same red as the cube's lamp at empty. See full_color.
@export var critical_color := Color(1.0, 0.2, 0.12)

## A segment that is present but not charged. Dark enough to read as off, light
## enough that you can still count how many are missing.
@export var unlit_color := Color(0.1, 0.12, 0.15)

@export var backing_color := Color(0.03, 0.04, 0.05)

var _material: ShaderMaterial

# The two quad transforms are written out in the scene rather than derived,
# because Basis.looking_at is degenerate for an up/down normal - which is why the
# prototype gauge only ever did the four vertical faces. Two traps live in those
# literals, and neither can be documented where they are, because Godot drops
# comments from a .tscn the first time the editor saves it:
#
# A QuadMesh faces its own +Z, so basis.z must be the outward normal - but the
# .tscn Transform3D literal is ROW-major, so basis.z is the third number of each
# triple, not the third triple. Read down the last column: Top is (0, 1, 0),
# Bottom is (0, -1, 0). Reversed, the quad faces into the cube, and cull_disabled
# then hides the mistake from you.
#
# Bottom is Top rotated 180 degrees through the cube rather than mirrored across
# it, so turning the box over shows you the same bar rather than its reflection.
@onready var top: MeshInstance3D = $Top
@onready var bottom: MeshInstance3D = $Bottom


func _ready() -> void:
	# Both faces already point at the one material, which the scene marks
	# resource_local_to_scene - so one set_shader_parameter run drives the whole
	# gauge, the two faces cannot disagree, and two boxes in a level cannot
	# overwrite each other's reading.
	_material = top.material_override as ShaderMaterial
	if _material == null:
		push_warning("BatteryBar has no ShaderMaterial on Top; the gauge will not move.")
		return
	if bottom.material_override != _material:
		push_warning("BatteryBar's faces are on different materials; they will disagree.")
	show_fraction(0.0)


## How many segments read as charged at this fraction, 0 to SEGMENTS.
static func lit_segments(fraction: float) -> int:
	var level := clampf(fraction, 0.0, 1.0)
	if level <= 0.0:
		return 0
	# A box with anything at all left in it keeps one segment showing: an empty
	# gauge and a nearly empty one have to look different, because one of them is
	# still worth swimming back to.
	return maxi(int(ceil(level * float(SEGMENTS))), 1)


static func band_color(lit: int, full: Color, warn: Color, critical: Color) -> Color:
	if lit <= CRITICAL_SEGMENTS:
		return critical
	if lit <= WARN_SEGMENTS:
		return warn
	return full


static func blinks(lit: int) -> bool:
	return lit == CRITICAL_SEGMENTS


## Sets what the gauge reads, 0 to 1. Connected to the cube's charge the same way
## its lamp is - see LifeSupportCube._apply_bar.
func show_fraction(fraction: float) -> void:
	if _material == null:
		return
	var lit := lit_segments(fraction)
	_material.set_shader_parameter("lit_segments", float(lit))
	_material.set_shader_parameter(
		"lit_color", band_color(lit, full_color, warn_color, critical_color)
	)
	_material.set_shader_parameter("unlit_color", unlit_color)
	_material.set_shader_parameter("backing_color", backing_color)
	_material.set_shader_parameter("blink", 1.0 if blinks(lit) else 0.0)
