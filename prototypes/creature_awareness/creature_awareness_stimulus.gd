class_name CreatureAwarenessStimulus
extends Node3D

## The player, simulated. Press and hold to perform an activity somewhere on the map; the
## noise streams for as long as the button is down, and dragging moves it.
##
## THE FIRST REAL NOISE EMITTER IN THE PROJECT. Nothing outside sandboxes, tests and
## verifiers has ever constructed a `NoiseEvent` -- perception's own sandbox says as much
## where it emits one by keypress. The call shape is the one its README documents and does
## not change:
##
##     perception.receive_noise(NoiseEvent.make(position, loudness, category, source, player))
##
## HOLDING IS WHAT MAKES A STIMULUS CARRY, and the arithmetic is worth knowing before you
## wonder why a distant tap does nothing. A single pulse becomes a hotspot only if its
## received strength clears about 0.204, which at loudness 1.0 is roughly 22 m and at 0.25
## is under 4 m. Below that, hearing still emits evidence and suspicion still stores it --
## it simply decays before it can ever cross `resolved_hotspot_threshold`. Held pulses
## accumulate, which is `SuspicionConfig`'s own stated intent: one is ignored, five in a row
## become a lead.
##
## THE CATEGORY TAG IS INERT, AND SAYING SO HERE SAVES SOMEONE THE SEARCH. `NoiseEvent`
## declares it free-form with no enum, perception copies it into the evidence, suspicion
## copies it into its record, and no decision anywhere reads it -- there is no `match` on it
## in the whole module. Mining differs from thrust because it is LOUDER, not because it is
## called mining. The tag is for the readout.
##
## THIS NODE MUST NOT JOIN THE "perceivable" GROUP. `CreaturePerception.request_activity_scan`
## looks for group members inside the searched region, so a perceivable marker sitting where
## the alien comes to investigate would be FOUND -- emitting vision evidence at full strength
## and raising suspicion at the exact moment the search was supposed to resolve it. The
## hotspot would then never clear, and the bug reads as broken disconfirmation.

## Emitted whenever a pulse actually goes out, with the true world position it went out
## from. The HUD draws this against what the alien came to believe.
signal pulsed(at: Vector3)

enum Kind { THRUST, MINING }

const MARKER_RADIUS: float = 0.7
const LABEL_HEIGHT: float = 1.8

@export var perception: CreaturePerception = null
@export var settings: CreatureAwarenessSettings = null

var kind: Kind = Kind.MINING

var _camera: Camera3D = null
var _marker: MeshInstance3D = null
var _label: Label3D = null
var _probe: SphereShape3D = null
var _held: bool = false
var _at: Vector3 = Vector3.ZERO
var _until_next: float = 0.0


static func kind_name(value: Kind) -> String:
	if value == Kind.MINING:
		return "mining"
	return "EVA thrust"


## The tag handed to `NoiseEvent`. Inert as far as the AI is concerned -- see the class
## docstring -- but it is what the readout and any future weighting would key off.
static func kind_category(value: Kind) -> StringName:
	if value == Kind.MINING:
		return &"mining"
	return &"thrust"


func _ready() -> void:
	_probe = SphereShape3D.new()
	_probe.radius = CreatureAwarenessKnobs.PICK_PROBE_RADIUS
	_build_marker()
	set_active(false)


func is_active() -> bool:
	return _held


func position_of_stimulus() -> Vector3:
	return _at


## The camera the pick is cast from. Re-set on every camera change, because the resolve
## rule below depends on where the camera is standing.
func bind_camera(camera: Camera3D) -> void:
	_camera = camera


func set_kind(value: Kind) -> void:
	kind = value
	_refresh_marker()


func begin() -> void:
	if not _update_position():
		return
	_held = true
	# Fire on the frame the button goes down rather than one interval later, so a quick tap
	# is still one pulse and the thing feels connected to the click.
	_until_next = 0.0
	set_active(true)


func end() -> void:
	_held = false
	set_active(false)


func set_active(showing: bool) -> void:
	if _marker != null:
		_marker.visible = showing
	if _label != null:
		_label.visible = showing


func _process(delta: float) -> void:
	if not _held:
		return
	# Dragging moves the emitter, so a held thrust reads as a player crossing a cavern
	# rather than hovering in one spot.
	_update_position()
	_until_next -= delta
	if _until_next > 0.0:
		return
	_until_next += _interval()
	_emit_pulse()


func _emit_pulse() -> void:
	if perception == null:
		return
	# Source and player are left null on purpose. Hearing never attributes a player anyway
	# (it always leaves `source_player` unset), so passing this node would only invite
	# something downstream to read a transform it is not entitled to.
	perception.receive_noise(NoiseEvent.make(_at, _loudness(), kind_category(kind), null, null))
	pulsed.emit(_at)


func _loudness() -> float:
	if settings == null:
		return (
			CreatureAwarenessKnobs.MINING_LOUDNESS
			if kind == Kind.MINING
			else CreatureAwarenessKnobs.THRUST_LOUDNESS
		)
	return settings.stimulus_values(kind == Kind.MINING)[0]


func _interval() -> float:
	if settings == null:
		return (
			CreatureAwarenessKnobs.MINING_INTERVAL
			if kind == Kind.MINING
			else CreatureAwarenessKnobs.THRUST_INTERVAL
		)
	return maxf(settings.stimulus_values(kind == Kind.MINING)[1], 0.02)


func _update_position() -> bool:
	var found: Variant = _resolve_pick()
	if found == null:
		return false
	_at = found
	global_position = _at
	return true


## Resolves the cursor to a point in OPEN AIR, which is not the same thing as the first
## surface the ray hits.
##
## THIS IS THE TRAP THE ANT-FARM CAMERA SETS. That camera sits outside the rock entirely, so
## a plain `intersect_ray` returns the block's OUTER surface -- and a stimulus placed there
## is buried in stone metres from any cavern, inaudible to everything. The failure looks
## exactly like a broken perception chain, which is the wrong thing to go and debug.
##
## TWO CASES, BECAUSE THE TWO CAMERAS WANT OPPOSITE THINGS:
##
##   camera outside the map   march in and return the FIRST open sample -- clicking into the
##                            ant farm should land in the first chamber under the cursor
##   camera inside a chamber  return the LAST open sample before the first solid -- pointing
##                            at a wall from inside should land against that wall, not in
##                            whatever room happens to be behind it
##
## Marching with a small sphere rather than a ray is what makes "open" mean *open enough to
## be somewhere*, and the step is well under the narrowest bore so the march cannot skip
## straight through a passage without ever sampling inside it.
func _resolve_pick() -> Variant:
	if _camera == null:
		return null
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = _camera.project_ray_origin(mouse)
	var direction: Vector3 = _camera.project_ray_normal(mouse)
	var region: AABB = CreatureAwarenessMap.bounds()
	var inside_start: bool = region.has_point(from) and _is_open(from)

	var travelled: float = 0.0
	var entered: bool = false
	var last_open: Vector3 = from
	while travelled <= CreatureAwarenessKnobs.PICK_RANGE:
		var point: Vector3 = from + direction * travelled
		if region.has_point(point):
			entered = true
			var open: bool = _is_open(point)
			if inside_start:
				if not open:
					return last_open if travelled > 0.0 else null
				last_open = point
			elif open:
				return point
		elif entered:
			# Out the far side without ever finding air.
			break
		travelled += CreatureAwarenessKnobs.PICK_STEP
	if inside_start and travelled > 0.0:
		return last_open
	return null


func _is_open(point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = CreatureAwarenessMap.TERRAIN_LAYER
	return space.intersect_shape(query, 1).is_empty()


func _build_marker() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 8
	_marker = MeshInstance3D.new()
	_marker.mesh = sphere
	add_child(_marker)

	_label = Label3D.new()
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Visible through rock, because from the ant-farm camera most of the map is behind some.
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.outline_size = 10
	_label.font_size = 40
	add_child(_label)
	_refresh_marker()


func _refresh_marker() -> void:
	if _marker == null:
		return
	var tint: Color = (
		Color(1.0, 0.55, 0.15, 1.0) if kind == Kind.MINING else Color(0.4, 0.85, 1.0, 1.0)
	)
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The true position must read through rock, or the whole true-versus-believed comparison
	# is invisible from the only camera that can see both at once.
	material.no_depth_test = true
	_marker.material_override = material
	_label.text = kind_name(kind)
	_label.modulate = tint
