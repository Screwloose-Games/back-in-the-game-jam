class_name CubePowerGauge
extends MultiMeshInstance3D

## The charge readout on the cube itself: a stack of segments repeated on all
## four of its vertical faces.
##
## On the cube rather than on the HUD, because the question is not "how much is
## left" - a number in the corner answers that - but whether you can tell from
## across the room, through fog, while your own lamp is failing. A HUD gauge
## would be legible in every one of those conditions and so would answer nothing.
##
## All four faces, because the cube tumbles freely in zero g and a gauge on one
## face would spend most of its time pointing at a wall.
##
## ONE MultiMesh, per-instance colour: four faces of segments for one draw call.
## Same trick tunnel_system_prototype.gd uses for its junction beacons, and it
## matters more here - this thing is redrawn every time the charge moves.

const GAUGE_MATERIAL := preload("res://prototypes/power_and_lighting/materials/power_gauge.tres")

## The render layer the cube's own mesh is on, which the cube's lamp already
## excludes from its shadow casters. The gauge has to join it: the lamp sits
## inside the box, so anything that casts a shadow from in there puts the entire
## room in darkness. See test_chamber_generator.gd's _make_module_lamp.
const MODULE_RENDER_LAYER := 2

## Outward normals of the four vertical faces of the cube.
const FACE_NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]

## How many segments are currently showing as charged. Held so a charge that
## moves without crossing a segment boundary costs nothing.
var _lit_segments := -1
var _fraction := 0.0


## Builds the gauge onto a cube of the given edge length, in metres.
func build(cube_size: float) -> void:
	var quad := QuadMesh.new()
	quad.size = PowerKnobs.GAUGE_SEGMENT_SIZE

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = FACE_NORMALS.size() * PowerKnobs.GAUGE_SEGMENTS

	material_override = GAUGE_MATERIAL
	layers = MODULE_RENDER_LAYER
	# The segments are flat quads standing a few millimetres off the faces, so
	# they would otherwise cast a shadow onto the face they are mounted on and
	# read as grime rather than as lights.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_place_segments(cube_size)
	_repaint(true)


## Sets what the gauge reads, 0 to 1. Connected straight to the cube store's
## charge_changed.
func show_fraction(fraction: float) -> void:
	_fraction = fraction
	_repaint(false)


## Lays one column of segments against each face, centred on it.
func _place_segments(cube_size: float) -> void:
	var pitch := PowerKnobs.GAUGE_SEGMENT_SIZE.y + PowerKnobs.GAUGE_SEGMENT_GAP
	var lowest := -0.5 * pitch * float(PowerKnobs.GAUGE_SEGMENTS - 1)
	var standoff := cube_size * 0.5 + PowerKnobs.GAUGE_SURFACE_OFFSET

	var slot := 0
	for normal: Vector3 in FACE_NORMALS:
		# QuadMesh faces its own +Z, and Basis.looking_at aims -Z at what it is
		# given - so it is handed the INWARD direction to leave the quad's face
		# pointing out of the cube. Aimed the other way every segment is
		# backface-culled and the gauge is invisible from every side at once.
		var facing := Basis.looking_at(-normal, Vector3.UP)
		for segment: int in PowerKnobs.GAUGE_SEGMENTS:
			var offset := normal * standoff + Vector3.UP * (lowest + pitch * float(segment))
			multimesh.set_instance_transform(slot, Transform3D(facing, offset))
			slot += 1


## Recolours the segments. `force` paints them all whatever the level is, for the
## first frame; otherwise nothing happens until the level crosses a boundary,
## since a gauge of eight segments cannot show anything finer.
func _repaint(force: bool) -> void:
	var lit := int(ceil(_fraction * float(PowerKnobs.GAUGE_SEGMENTS)))
	# A cube with anything at all left in it keeps one segment showing: an empty
	# gauge and a nearly empty one have to look different, because one of them is
	# still worth swimming back to.
	if _fraction > 0.0:
		lit = maxi(lit, 1)
	if lit == _lit_segments and not force:
		return
	_lit_segments = lit

	# The lit colour walks from green to red across the whole gauge rather than
	# per segment, so the colour is a second reading of the same number and the
	# bar does not turn into a rainbow that has to be interpreted.
	var lit_color := PowerKnobs.GAUGE_EMPTY_COLOR.lerp(PowerKnobs.GAUGE_FULL_COLOR, _fraction)

	var slot := 0
	for _face: int in FACE_NORMALS.size():
		for segment: int in PowerKnobs.GAUGE_SEGMENTS:
			var is_lit := segment < lit
			multimesh.set_instance_color(
				slot, lit_color if is_lit else PowerKnobs.GAUGE_UNLIT_COLOR
			)
			slot += 1
