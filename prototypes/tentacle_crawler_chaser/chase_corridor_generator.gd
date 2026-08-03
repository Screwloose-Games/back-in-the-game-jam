class_name ChaseCorridorGenerator
extends Node3D

## Carves the corridor network out of solid hull with CSG, and drops the module
## into it.
##
## Every span contributes two brushes: a solid box the size of the hull, and a
## smaller box that hollows the tunnel out of it. All the hull brushes union
## first, then all the tunnel brushes subtract from the result. The tunnel brush
## is always strictly narrower than its own hull brush, so a span can never carve
## through to the outside whatever angle it sits at - which is what makes
## multi-way junctions safe here. There are no seams to line up, only overlapping
## volumes.
##
## The technique is lifted from prototypes/navigation/corridor_generator.gd.
## Copied rather than shared: that one is wired to PrototypeKnobs by hard-coded
## class name and carries a spike and debris field this prototype does not want,
## and prototypes here are explicitly not expected to grow reusable components.
##
## Nothing about the geometry is described to the navmesh baker. It floods the
## open space with physics queries and finds whatever is actually here, so a
## corridor added, moved or bent below needs no corresponding change over there.

const HULL_MATERIAL := preload("res://prototypes/object_carrying/materials/hull_material.tres")
const CARRY_OBJECT_MATERIAL := preload(
	"res://prototypes/object_carrying/materials/carry_object_material.tres"
)

const HULL_LAYER := 1
const CARRYABLE_LAYER := 8
const PLAYER_LAYER := 2

## The render layer the module's mesh is given, to itself, so the module's own
## lamp can be told to ignore it.
const MODULE_RENDER_LAYER := 2
const ALL_RENDER_LAYERS := 0xFFFFFFFF

var _spans: Array[Dictionary] = []
var _carry_object: RigidBody3D
## How far a hull brush runs past each end of its span, so hulls of adjoining
## spans always overlap through a junction.
var _hull_overrun: float
## How far a tunnel brush runs past each end. Below _hull_overrun or the tunnel
## breaches its own hull; positive so adjoining tunnels actually meet.
var _tunnel_overrun: float


func _ready() -> void:
	_hull_overrun = ChaseKnobs.CORRIDOR_WIDTH * 0.5 + ChaseKnobs.WALL_THICKNESS
	_tunnel_overrun = ChaseKnobs.CORRIDOR_WIDTH * 0.5
	_collect_spans()
	_assemble_combiner()
	_spawn_carry_object()


## The volume the network occupies, padded by a corridor's width.
##
## The navmesh flood fill uses this as a fence. Without one, a single hole in the
## hull would let the fill escape into the infinite void outside and only stop
## when it hit its cell budget.
func bounds() -> AABB:
	var box := AABB(_waypoints()[0], Vector3.ZERO)
	for point: Vector3 in _waypoints():
		box = box.expand(point)
	return box.grow(ChaseKnobs.CORRIDOR_WIDTH)


## Total metres of corridor, for the HUD.
func corridor_length() -> float:
	var total := 0.0
	for span: Dictionary in _spans:
		total += span["length"]
	return total


func get_carry_object() -> RigidBody3D:
	return _carry_object


## Returns the module to its spawn pose, fully at rest. Paired with the player's
## own respawn so one key resets the whole experiment.
func reset_carry_object() -> void:
	if _carry_object == null:
		return
	_carry_object.linear_velocity = Vector3.ZERO
	_carry_object.angular_velocity = Vector3.ZERO
	_carry_object.global_transform = Transform3D(Basis.IDENTITY, ChaseKnobs.MODULE_SPAWN)


# --- Layout ----------------------------------------------------------------


func _waypoints() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for path: Array in ChaseKnobs.CORRIDOR_PATHS:
		for point: Vector3 in path:
			points.append(point)
	return points


func _collect_spans() -> void:
	for path: Array in ChaseKnobs.CORRIDOR_PATHS:
		if path.size() < 2:
			push_warning("Corridor path needs at least two waypoints; skipped.")
			continue
		for index: int in path.size() - 1:
			var span_start: Vector3 = path[index]
			var span_end: Vector3 = path[index + 1]
			if span_start.is_equal_approx(span_end):
				push_warning("Corridor span has zero length at %v; skipped." % span_start)
				continue
			var span := {
				"start": span_start,
				"end": span_end,
				"length": span_start.distance_to(span_end),
				"transform": _make_span_transform(span_start, span_end),
			}
			_spans.append(span)


## Order matters: hulls union into one solid, then tunnels subtract from it.
func _assemble_combiner() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = true
	combiner.collision_layer = HULL_LAYER
	combiner.collision_mask = 0
	combiner.material_override = HULL_MATERIAL
	add_child(combiner)

	var hull_side := ChaseKnobs.CORRIDOR_WIDTH + ChaseKnobs.WALL_THICKNESS * 2.0
	for span: Dictionary in _spans:
		combiner.add_child(
			_make_brush(
				span["transform"],
				Vector3(hull_side, hull_side, span["length"] + _hull_overrun * 2.0),
				CSGShape3D.OPERATION_UNION
			)
		)
	for span: Dictionary in _spans:
		combiner.add_child(
			_make_brush(
				span["transform"],
				Vector3(
					ChaseKnobs.CORRIDOR_WIDTH,
					ChaseKnobs.CORRIDOR_WIDTH,
					span["length"] + _tunnel_overrun * 2.0
				),
				CSGShape3D.OPERATION_SUBTRACTION
			)
		)


func _make_brush(
	brush_transform: Transform3D, brush_size: Vector3, operation: CSGShape3D.Operation
) -> CSGBox3D:
	var brush := CSGBox3D.new()
	brush.size = brush_size
	brush.operation = operation
	brush.transform = brush_transform
	return brush


## Builds a basis whose local Z runs along the span, centred on its midpoint.
func _make_span_transform(span_start: Vector3, span_end: Vector3) -> Transform3D:
	var direction := (span_end - span_start).normalized()
	return Transform3D(
		Basis.looking_at(direction, _pick_reference_up(direction)), (span_start + span_end) * 0.5
	)


## Basis.looking_at fails when its up vector is parallel to the direction, and
## this network has a thirty metre vertical shaft in it.
func _pick_reference_up(direction: Vector3) -> Vector3:
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


# --- Carryable -------------------------------------------------------------


## The module, unchanged from the object carrying prototype apart from where it
## starts. Same mass, same damping, same lamp: the load is the control in this
## experiment and hauling it should feel exactly as it does over there.
func _spawn_carry_object() -> void:
	var object_size := Vector3.ONE * CarryKnobs.CARRY_OBJECT_SIZE

	_carry_object = RigidBody3D.new()
	_carry_object.name = "CarryObject"
	_carry_object.mass = CarryKnobs.CARRY_OBJECT_MASS
	# Zero-g: nothing falls, it only goes where something pushed it.
	_carry_object.gravity_scale = 0.0
	_carry_object.linear_damp = CarryKnobs.CARRY_OBJECT_LINEAR_DAMP
	_carry_object.angular_damp = CarryKnobs.CARRY_OBJECT_ANGULAR_DAMP
	# A sleeping body ignores the first frames of grip force, which reads as the
	# grab having failed.
	_carry_object.can_sleep = false
	_carry_object.collision_layer = CARRYABLE_LAYER
	_carry_object.collision_mask = HULL_LAYER | PLAYER_LAYER | CARRYABLE_LAYER
	_carry_object.position = ChaseKnobs.MODULE_SPAWN

	var object_mesh := BoxMesh.new()
	object_mesh.size = object_size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = object_mesh
	mesh_instance.material_override = _make_glowing_material()
	mesh_instance.layers = MODULE_RENDER_LAYER
	_carry_object.add_child(mesh_instance)

	_carry_object.add_child(_make_module_lamp())

	var object_shape := BoxShape3D.new()
	object_shape.size = object_size
	var collider := CollisionShape3D.new()
	collider.shape = object_shape
	_carry_object.add_child(collider)

	add_child(_carry_object)


## A lamp shut inside a solid box lights nothing at all - the shadow map is
## rendered from in there, so the six faces enclosing it put the whole corridor in
## shadow. Dropping the module's own mesh from this lamp's shadow casters is what
## opens it up.
func _make_module_lamp() -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.name = "ModuleLamp"
	lamp.light_color = CarryKnobs.CARRY_OBJECT_LIGHT_COLOR
	lamp.light_energy = CarryKnobs.CARRY_OBJECT_LIGHT_ENERGY
	lamp.omni_range = CarryKnobs.CARRY_OBJECT_LIGHT_RANGE
	lamp.omni_attenuation = CarryKnobs.CARRY_OBJECT_LIGHT_ATTENUATION
	lamp.shadow_enabled = CarryKnobs.CARRY_OBJECT_LIGHT_SHADOWS
	lamp.shadow_caster_mask = ALL_RENDER_LAYERS & ~MODULE_RENDER_LAYER
	return lamp


func _make_glowing_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = CARRY_OBJECT_MATERIAL.duplicate()
	material.emission_enabled = true
	material.emission = CarryKnobs.CARRY_OBJECT_LIGHT_COLOR
	material.emission_energy_multiplier = CarryKnobs.CARRY_OBJECT_GLOW
	return material
