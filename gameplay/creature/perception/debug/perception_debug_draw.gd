class_name PerceptionDebugDraw
extends Node3D

## Draws what the alien is SENSING, independently of what it believes
## (perception.md section 30).
##
## The point of drawing perception separately is to tell four different failures
## apart (section 29):
##
##     the alien didn't hear me
##     the alien heard me and didn't care
##     the alien was suspicious and chose another hotspot
##     the alien wanted to reach me and remembered the geometry wrongly
##
## Only the first is visible here. If the ping appears and nothing happens, the bug
## is in Suspicion, and you have just saved yourself an afternoon in the wrong file.
##
## THE FADE BUFFER LIVES HERE, NOT IN PERCEPTION. Keeping a list of recent evidence
## on CreaturePerception would give it memory, which section 28 forbids -- so this
## node subscribes to the signals and ages its own copy. That is also why the buffer
## is capped: an overlay is not allowed to grow without bound either.
##
## Everything is lines. On the GL Compatibility renderer this project targets,
## transparent surfaces sort per-object rather than per-fragment, so overlapping
## translucent cones and spheres pop and reorder as the camera moves -- which reads
## as a bug in perception rather than in the renderer.

## Segments per great circle. 24 reads as round without turning a handful of
## observations into thousands of vertices.
const CIRCLE_SEGMENTS: int = 24
## Rays drawn along the surface of the vision cone.
const CONE_RAYS: int = 16
## Hard caps, so a noisy scene cannot grow the overlay without bound.
##
## TWO BUFFERS, NOT ONE, and that is not tidiness. With a single ring buffer a
## routine passive geometry scan pushes hundreds of cells in one frame and evicts
## every piece of evidence in it -- so the hearing ping you are actually trying to
## debug vanishes from the screen a frame after it appears, while the log line for
## it is still sitting in the panel. Geometry is background; evidence is the thing.
const MAX_EVIDENCE_TRACES: int = 48
const MAX_GEOMETRY_TRACES: int = 256

const COLOR_CONE_BLIND := Color(0.45, 0.45, 0.50, 1.0)
const COLOR_CONE_SEARCHING := Color(0.95, 0.70, 0.20, 1.0)
const COLOR_CONE_SEEING := Color(0.30, 0.95, 0.45, 1.0)
const COLOR_EVIDENCE := Color(0.95, 0.35, 0.35, 1.0)
const COLOR_DISCONFIRMATION := Color(0.35, 0.75, 0.95, 1.0)
const COLOR_ACTIVITY_REGION := Color(0.95, 0.55, 0.85, 1.0)
const COLOR_GEOMETRY_REGION := Color(0.55, 0.85, 0.95, 1.0)
const COLOR_FREE := Color(0.30, 0.80, 0.40, 1.0)
const COLOR_SOLID := Color(0.85, 0.40, 0.25, 1.0)
const COLOR_CLEARANCE := Color(0.90, 0.85, 0.30, 1.0)

@export var perception: CreaturePerception = null
## How long an observation stays on screen. A rendering decision, which is exactly
## why it is a property of this node.
@export_range(0.1, 30.0, 0.1, "suffix:s") var trace_lifetime: float = 3.0
@export var draw_geometry_cells: bool = true

var _mesh: ImmediateMesh = null
var _view: MeshInstance3D = null
## Each entry is [kind, position, radius, born_at_seconds, extra].
var _evidence_traces: Array[Array] = []
var _geometry_traces: Array[Array] = []
var _elapsed: float = 0.0


func _ready() -> void:
	top_level = true

	_mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# NOT INFERRED BY GODOT, and the failure is silent: without it every colour
	# encoding below renders flat white and the overlay looks like one undifferentiated
	# tangle. verify_perception_static.gd asserts this line exists.
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	# Half of what you want to know is where a ping landed while it is behind a wall.
	material.no_depth_test = true
	material.render_priority = 1

	_view = MeshInstance3D.new()
	_view.mesh = _mesh
	_view.material_override = material
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The overlay's AABB is derived from whatever it drew last frame, so an overlay
	# that is briefly tiny and then huge pops in and out of the frustum.
	_view.extra_cull_margin = 4096.0
	add_child(_view)

	if perception != null:
		perception.evidence_observed.connect(_on_evidence)
		perception.disconfirmation_observed.connect(_on_disconfirmation)
		perception.geometry_observed.connect(_on_geometry)


func _process(delta: float) -> void:
	_elapsed += delta
	_expire()
	if not visible or perception == null:
		return
	_mesh.clear_surfaces()
	# surface_begin/surface_end with no vertices in between is an error, so the whole
	# frame is built into one list and skipped when it is empty.
	var lines: Array[Array] = []
	_build_vision(lines)
	_build_scans(lines)
	_build_traces(lines)
	if lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line: Array in lines:
		_mesh.surface_set_color(line[2] as Color)
		_mesh.surface_add_vertex(line[0] as Vector3)
		_mesh.surface_set_color(line[2] as Color)
		_mesh.surface_add_vertex(line[1] as Vector3)
	_mesh.surface_end()


func clear_traces() -> void:
	_evidence_traces.clear()
	_geometry_traces.clear()


func trace_counts() -> Vector2i:
	return Vector2i(_evidence_traces.size(), _geometry_traces.size())


# ----- capture (section 30's "generated observations") -----


func _on_evidence(evidence: SuspicionEvidence) -> void:
	_remember(
		_evidence_traces,
		MAX_EVIDENCE_TRACES,
		["evidence", evidence.position, maxf(evidence.uncertainty_radius, 0.1), evidence.strength]
	)


func _on_disconfirmation(observation: DisconfirmationObservation) -> void:
	_remember(
		_evidence_traces,
		MAX_EVIDENCE_TRACES,
		[
			"disconfirmation",
			observation.position,
			maxf(observation.radius, 0.1),
			observation.strength
		]
	)


func _on_geometry(observations: Array) -> void:
	if not draw_geometry_cells:
		return
	for observation: Variant in observations:
		var geometry := observation as GeometryObservation
		_remember(
			_geometry_traces,
			MAX_GEOMETRY_TRACES,
			["geometry", geometry.region.get_center(), 0.0, float(geometry.type), geometry.region]
		)


func _remember(buffer: Array[Array], cap: int, entry: Array) -> void:
	entry.insert(3, _elapsed)
	buffer.append(entry)
	if buffer.size() > cap:
		buffer.remove_at(0)


func _expire() -> void:
	_evidence_traces = _still_alive(_evidence_traces)
	_geometry_traces = _still_alive(_geometry_traces)


func _still_alive(buffer: Array[Array]) -> Array[Array]:
	var alive: Array[Array] = []
	for trace: Array in buffer:
		if _elapsed - float(trace[3]) < trace_lifetime:
			alive.append(trace)
	return alive


# ----- geometry of the overlay itself -----


func _build_vision(lines: Array[Array]) -> void:
	var config: PerceptionConfig = perception.config
	if config == null:
		return
	var eye: Transform3D = perception.eye_transform()
	var seeing: bool = false
	var candidates: Array[Node3D] = perception.candidate_targets()
	for target: Node3D in candidates:
		if target == null or not target.is_inside_tree():
			continue
		var to_target: Vector3 = target.global_position - eye.origin
		var visible_now: float = CreatureVision.visibility(
			to_target.length(),
			CreatureVision.cone_alignment(-eye.basis.z, to_target),
			true,
			perception.light_level,
			config
		)
		seeing = seeing or visible_now >= config.vision_min_visibility
		lines.append(
			[
				eye.origin,
				target.global_position,
				COLOR_CONE_SEEING if visible_now > 0.0 else COLOR_CONE_SEARCHING
			]
		)

	var color: Color = COLOR_CONE_BLIND
	if config.vision_gate(perception.get_alertness()) and perception.vision.enabled:
		color = COLOR_CONE_SEEING if seeing else COLOR_CONE_SEARCHING
	_build_cone(lines, eye, config.vision_range, config.vision_angle, color)


func _build_cone(
	lines: Array[Array], eye: Transform3D, range_m: float, angle: float, color: Color
) -> void:
	var half: float = angle * 0.5
	var forward: Vector3 = -eye.basis.z
	var rim: Array[Vector3] = []
	for i: int in CONE_RAYS:
		var spin: float = TAU * float(i) / float(CONE_RAYS)
		var direction: Vector3 = forward.rotated(eye.basis.x.normalized(), half).rotated(
			forward.normalized(), spin
		)
		var point: Vector3 = eye.origin + direction.normalized() * range_m
		rim.append(point)
		lines.append([eye.origin, point, color])
	for i: int in rim.size():
		lines.append([rim[i], rim[(i + 1) % rim.size()], color])


func _build_scans(lines: Array[Array]) -> void:
	var state: Dictionary = perception.debug_state()
	if bool(state["activity_scan_active"]):
		_build_box(lines, state["activity_scan_region"] as AABB, COLOR_ACTIVITY_REGION)
	if bool(state["geometry_scan_active"]):
		_build_box(lines, state["geometry_scan_region"] as AABB, COLOR_GEOMETRY_REGION)


func _build_traces(lines: Array[Array]) -> void:
	# Geometry first, so evidence spheres draw over the cells rather than under them.
	for trace: Array in _geometry_traces + _evidence_traces:
		var age: float = (_elapsed - float(trace[3])) / trace_lifetime
		var kind: String = trace[0] as String
		if kind == "geometry":
			var type: int = int(trace[4])
			var cell_color: Color = COLOR_FREE
			if type == GeometryObservation.ObservationType.SOLID:
				cell_color = COLOR_SOLID
			elif type == GeometryObservation.ObservationType.CLEARANCE:
				cell_color = COLOR_CLEARANCE
			_build_box(lines, trace[5] as AABB, _faded(cell_color, age))
			continue
		# Evidence draws solid, disconfirmation dashed, so "I found something here"
		# and "I checked here and found nothing" are never the same picture.
		var base: Color = COLOR_EVIDENCE if kind == "evidence" else COLOR_DISCONFIRMATION
		_build_sphere(
			lines,
			trace[1] as Vector3,
			trace[2] as float,
			_faded(base, age),
			kind == "disconfirmation"
		)


func _faded(color: Color, age: float) -> Color:
	# The renderer sorts transparency per object, so fading is done in BRIGHTNESS
	# rather than in alpha. An alpha fade would make the overlay flicker as the
	# camera moved, which reads as a perception bug.
	return color.lerp(Color.BLACK, clampf(age, 0.0, 1.0) * 0.75)


## Three great circles. Dashed drops every other segment, which stays legible at any
## radius -- unlike a thinner line, since GL Compatibility ignores line width.
func _build_sphere(
	lines: Array[Array], centre: Vector3, radius: float, color: Color, dashed: bool
) -> void:
	var planes: Array[Array] = [
		[Vector3.RIGHT, Vector3.UP], [Vector3.UP, Vector3.BACK], [Vector3.BACK, Vector3.RIGHT]
	]
	for plane: Array in planes:
		for i: int in CIRCLE_SEGMENTS:
			if dashed and i % 2 == 1:
				continue
			var a: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
			var b: float = TAU * float(i + 1) / float(CIRCLE_SEGMENTS)
			var axis_x: Vector3 = plane[0] as Vector3
			var axis_y: Vector3 = plane[1] as Vector3
			lines.append(
				[
					centre + (axis_x * cos(a) + axis_y * sin(a)) * radius,
					centre + (axis_x * cos(b) + axis_y * sin(b)) * radius,
					color
				]
			)


func _build_box(lines: Array[Array], box: AABB, color: Color) -> void:
	if box.size.length_squared() <= 0.0:
		return
	var corners: Array[Vector3] = []
	for i: int in 8:
		corners.append(box.get_endpoint(i))
	# get_endpoint indexes corners as a bit pattern over (x, y, z); an edge is any
	# pair differing in exactly one bit.
	for a: int in 8:
		for b: int in range(a + 1, 8):
			var difference: int = a ^ b
			if difference == 1 or difference == 2 or difference == 4:
				lines.append([corners[a], corners[b], color])
