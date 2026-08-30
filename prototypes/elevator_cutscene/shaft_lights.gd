class_name ShaftLights
extends Node3D

## Emissive bars streaming upward past the car's wall slot. The thing that
## actually sells "already descending".
##
## No lights and no colliders - these are a texture of motion seen through a
## slot, not a lighting rig. Twelve Vector3 writes a frame is the entire cost,
## which matters on a web build where a shadow-casting light would not be
## affordable.
##
## PURE PRESENTATION, WITH NO END STATE TO GET WRONG. The whole animation is one
## wrapped float, so seeking, skipping and replaying are all non-questions: there
## is nothing here for a skip to leave stale. Whether the column is *running* is
## state, and that belongs to the effects list rather than to a keyframe - see
## elevator_effects.gd.

const MATERIAL: StandardMaterial3D = preload(
	"res://prototypes/elevator_cutscene/materials/shaft_light_material.tres"
)

var _bars: Array[MeshInstance3D] = []
var _spacing := ElevatorIntroKnobs.SHAFT_LIGHT_SPACING
var _speed := ElevatorIntroKnobs.SHAFT_LIGHT_SPEED
var _bottom := 0.0
var _offset := 0.0
var _running := false


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = ElevatorIntroKnobs.SHAFT_LIGHT_SIZE
	for index in ElevatorIntroKnobs.SHAFT_LIGHT_COUNT:
		var bar := MeshInstance3D.new()
		bar.name = "Bar%02d" % index
		bar.mesh = mesh
		bar.material_override = MATERIAL
		# One shared material and one shared mesh across all twelve. Nothing
		# animates them per-bar, unlike the miners' visors.
		add_child(bar)
		_bars.append(bar)
	_layout()


func set_running(running: bool) -> void:
	_running = running


func set_stream(speed: float, spacing: float) -> void:
	_speed = speed
	# Guarded: fposmod by zero returns NaN, which would put every bar at NaN and
	# make the column vanish with no error. Reachable from the slider's own
	# minimum if it were ever set to 0.
	_spacing = maxf(spacing, 0.01)
	_layout()


func _process(delta: float) -> void:
	if not _running:
		return
	# One wrapped float is the whole state. The bars are interchangeable, so
	# wrapping the offset is the same as recycling the bar that left the top -
	# without a queue, an index, or anything that could get out of step.
	_offset = fposmod(_offset + _speed * delta, _spacing)
	for index in _bars.size():
		_bars[index].position.y = _bottom + _offset + index * _spacing


func _layout() -> void:
	# Centred on the node, so the visible stretch is in the middle of the column
	# and the ends never come into view through the slot.
	_bottom = -_spacing * _bars.size() * 0.5
	for index in _bars.size():
		_bars[index].position = Vector3(0.0, _bottom + _offset + index * _spacing, 0.0)
