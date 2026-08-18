class_name SuspicionDebugDraw
extends Node3D

## Draws what the alien BELIEVES, as opposed to what it just sensed.
##
## Perception's overlay and this one exist to tell four different failures apart:
##
##     the alien didn't hear me                              perception overlay
##     the alien heard me and didn't care                    THIS ONE
##     the alien was suspicious and chose another hotspot    THIS ONE
##     the alien wanted to reach me and remembered wrongly   spatial memory
##
## If a perception ping appears and no hotspot forms here, the bug is in ingestion. If
## a hotspot forms in the wrong place, the bug is in clustering. If the sample cloud
## never moves as the creature searches, disconfirmation is not reaching the model.
## Each of those looks identical from outside the creature.
##
## IT KEEPS NO BUFFER OF ITS OWN, and that is the one real difference from
## PerceptionDebugDraw. Perception is forbidden to remember anything, so its overlay
## has to age its own copy of the signals. Suspicion's whole job IS remembering, so
## this reads the live model every frame and cannot drift from it.
##
## Everything is lines. On the GL Compatibility renderer this project targets,
## transparent surfaces sort per-object rather than per-fragment, so overlapping
## translucent spheres pop and reorder as the camera moves -- which reads as a bug in
## the belief model rather than in the renderer.

## Segments per great circle. 24 reads as round without turning six hotspots into
## thousands of vertices.
const CIRCLE_SEGMENTS: int = 24
## Arm length of a sample cross, in metres.
const SAMPLE_ARM: float = 0.22
## Sample crosses are only drawn for the strongest hotspot. Drawing every hotspot's
## cloud at once is an unreadable haze, and the strongest is the one Behavior is about
## to act on.
const CALM := Color(0.35, 0.55, 0.95, 1.0)
const ALARMED := Color(0.98, 0.30, 0.25, 1.0)
const COLOR_SEARCHED := Color(0.35, 0.80, 0.95, 1.0)
const COLOR_EVIDENCE := Color(0.95, 0.85, 0.35, 1.0)
const COLOR_BEST := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SOURCE := Color(0.95, 0.45, 0.90, 1.0)

@export var suspicion: CreatureSuspicion = null
@export var draw_samples: bool = true
@export var draw_evidence: bool = true
## Height of the vertical spike over the best unresolved location. It is the single
## most useful mark on the overlay -- it is where Behavior is about to send the
## creature -- so it is drawn tall enough to find without hunting.
@export_range(0.5, 20.0, 0.5, "suffix:m") var marker_height: float = 4.0

var _mesh: ImmediateMesh = null
var _view: MeshInstance3D = null


func _ready() -> void:
	top_level = true

	_mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# NOT INFERRED BY GODOT, and the failure is silent: without it every colour encoding
	# below renders flat white, and a hotspot the creature is certain about looks exactly
	# like one it has already searched. verify_suspicion_static.gd asserts this line.
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	# Half of what you want to know is where the creature believes you are while it is
	# behind a wall.
	material.no_depth_test = true
	material.render_priority = 1

	_view = MeshInstance3D.new()
	_view.mesh = _mesh
	_view.material_override = material
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The overlay's AABB comes from whatever it drew last frame, so an overlay that is
	# briefly tiny and then huge pops in and out of the frustum.
	_view.extra_cull_margin = 4096.0
	add_child(_view)


func _process(_delta: float) -> void:
	if not visible or suspicion == null:
		return
	_mesh.clear_surfaces()
	# surface_begin/surface_end with nothing in between is an error, so the frame is
	# built into one list and skipped when it is empty.
	var lines: Array[Array] = []
	_build_hotspots(lines)
	_build_searches(lines)
	_build_evidence(lines)
	if lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line: Array in lines:
		_mesh.surface_set_color(line[2] as Color)
		_mesh.surface_add_vertex(line[0] as Vector3)
		_mesh.surface_set_color(line[2] as Color)
		_mesh.surface_add_vertex(line[1] as Vector3)
	_mesh.surface_end()


## Blue through red by suspicion. The colour and the SIZE carry different information
## and both matter: a big pale sphere is "something happened vaguely over there", a
## small red one is "I am fairly sure it was right here".
static func suspicion_color(value: float) -> Color:
	return CALM.lerp(ALARMED, clampf(value, 0.0, 1.0))


func _build_hotspots(lines: Array[Array]) -> void:
	var strongest: SuspicionHotspot = suspicion.get_strongest_hotspot()
	for hotspot: SuspicionHotspot in suspicion.get_hotspots():
		var color: Color = suspicion_color(hotspot.suspicion)
		_add_sphere(lines, hotspot.position, hotspot.radius, color)
		if hotspot.likely_source != null and is_instance_valid(hotspot.likely_source):
			var target := hotspot.likely_source as Node3D
			if target != null and target.is_inside_tree():
				# Whom the creature blames, drawn as a literal line of accusation.
				lines.append([hotspot.position, target.global_position, COLOR_SOURCE])
		if hotspot == strongest:
			_build_samples(lines, hotspot)


## The spec's sample-cloud diagram, live. Each cross is one place inside the hotspot,
## coloured by how much unresolved belief is still there -- so a searched half visibly
## goes cold while the unsearched half stays hot.
func _build_samples(lines: Array[Array], hotspot: SuspicionHotspot) -> void:
	if not draw_samples:
		return
	var now: float = suspicion.clock
	var peak: float = 0.0
	var points: PackedVector3Array = suspicion.hotspot_field.sample_points(hotspot)
	var values := PackedFloat32Array()
	for point: Vector3 in points:
		var value: float = suspicion.memory.unresolved_at(point, now)
		values.append(value)
		peak = maxf(peak, value)
	if peak <= 0.0:
		return
	for index: int in points.size():
		_add_cross(lines, points[index], suspicion_color(values[index] / peak))

	# Where Behavior is about to be sent. Drawn last and drawn white, because picking it
	# out of two dozen crosses by shade alone is exactly the kind of thing an overlay is
	# supposed to save you from.
	var best: Vector3 = suspicion.get_best_unresolved_location(hotspot.id)
	lines.append([best, best + Vector3.UP * marker_height, COLOR_BEST])


## Everywhere the creature has recently looked. These SHRINK as they go stale, which is
## the visible form of "a searched area becomes worth reconsidering".
func _build_searches(lines: Array[Array]) -> void:
	var now: float = suspicion.clock
	for search: SuspicionDisconfirmation in suspicion.memory.disconfirmations:
		var remaining: float = search.effective_strength(now) / maxf(search.strength, 0.0001)
		var color: Color = COLOR_SEARCHED
		color.a = 1.0
		_add_sphere(lines, search.position, search.radius * clampf(remaining, 0.1, 1.0), color)


## The individual records, so a hotspot in a surprising place can be traced back to the
## observations that put it there.
func _build_evidence(lines: Array[Array]) -> void:
	if not draw_evidence:
		return
	for record: SuspicionEvidenceRecord in suspicion.memory.records:
		_add_cross(lines, record.position, COLOR_EVIDENCE)


func _add_cross(lines: Array[Array], at: Vector3, color: Color) -> void:
	lines.append([at - Vector3.RIGHT * SAMPLE_ARM, at + Vector3.RIGHT * SAMPLE_ARM, color])
	lines.append([at - Vector3.UP * SAMPLE_ARM, at + Vector3.UP * SAMPLE_ARM, color])
	lines.append([at - Vector3.BACK * SAMPLE_ARM, at + Vector3.BACK * SAMPLE_ARM, color])


## Three great circles. A full wireframe sphere is unreadable once two of them overlap.
func _add_sphere(lines: Array[Array], centre: Vector3, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	_add_circle(lines, centre, radius, Vector3.RIGHT, Vector3.BACK, color)
	_add_circle(lines, centre, radius, Vector3.RIGHT, Vector3.UP, color)
	_add_circle(lines, centre, radius, Vector3.BACK, Vector3.UP, color)


func _add_circle(
	lines: Array[Array], centre: Vector3, radius: float, u: Vector3, v: Vector3, color: Color
) -> void:
	var previous: Vector3 = centre + u * radius
	for step: int in CIRCLE_SEGMENTS:
		var angle: float = TAU * float(step + 1) / float(CIRCLE_SEGMENTS)
		var point: Vector3 = centre + (u * cos(angle) + v * sin(angle)) * radius
		lines.append([previous, point, color])
		previous = point
