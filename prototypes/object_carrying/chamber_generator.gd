class_name ChamberGenerator
extends Node3D

## Carves one open room out of solid hull with CSG and drops the carryable
## object into it.
##
## Deliberately plain compared to the navigation prototype's corridor network.
## The only geometry here is what a load can be tested against: pillars to swing
## the object into, and a single wall with an opening wide enough that missing
## it is a matter of carrying too much momentum rather than of clearance.
##
## Brush order is what makes the CSG work: the room is hollowed out of the hull
## first, then the pillars and the divider are added back into the empty space,
## and only then is the doorway cut through the divider.

const HULL_MATERIAL := preload("res://prototypes/object_carrying/materials/hull_material.tres")
const CARRY_OBJECT_MATERIAL := preload(
	"res://prototypes/object_carrying/materials/carry_object_material.tres"
)

const HULL_LAYER := 1
const PLAYER_LAYER := 2
const CARRYABLE_LAYER := 8

## The render layer the module's mesh is given, to itself, so the module's own
## lamp can be told to ignore it. Nothing else uses render layers, and every
## camera draws all of them, so this changes nothing about how it is drawn.
const MODULE_RENDER_LAYER := 2
const ALL_RENDER_LAYERS := 0xFFFFFFFF

var _carry_object: RigidBody3D


func _ready() -> void:
	_assemble_combiner()
	_spawn_carry_object()


## The object the prototype exists to test. Null only if generation failed.
func get_carry_object() -> RigidBody3D:
	return _carry_object


## Returns the object to its spawn pose, fully at rest. Paired with the
## player's own respawn so one key resets the whole experiment.
func reset_carry_object() -> void:
	if _carry_object == null:
		return
	_carry_object.linear_velocity = Vector3.ZERO
	_carry_object.angular_velocity = Vector3.ZERO
	_carry_object.global_transform = Transform3D(Basis.IDENTITY, CarryKnobs.CARRY_OBJECT_SPAWN)


# --- Geometry --------------------------------------------------------------


func _assemble_combiner() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = true
	combiner.collision_layer = HULL_LAYER
	combiner.collision_mask = 0
	combiner.material_override = HULL_MATERIAL
	add_child(combiner)

	var wall_padding := Vector3.ONE * CarryKnobs.WALL_THICKNESS * 2.0
	combiner.add_child(
		_make_brush(
			Vector3.ZERO, CarryKnobs.CHAMBER_SIZE + wall_padding, CSGShape3D.OPERATION_UNION
		)
	)
	combiner.add_child(
		_make_brush(Vector3.ZERO, CarryKnobs.CHAMBER_SIZE, CSGShape3D.OPERATION_SUBTRACTION)
	)

	for pillar: Dictionary in CarryKnobs.PILLARS:
		var pillar_center: Vector3 = pillar["center"]
		var pillar_size: Vector3 = pillar["size"]
		combiner.add_child(
			_make_brush(pillar_center, pillar_size, CSGShape3D.OPERATION_UNION)
		)

	for pillar: Dictionary in CarryKnobs.ROUND_PILLARS:
		var pillar_center: Vector3 = pillar["center"]
		var pillar_radius: float = pillar["radius"]
		combiner.add_child(_make_round_brush(pillar_center, pillar_radius))

	_add_divider(combiner)


## A wall across the room with one opening cut through it. The opening brush
## runs well past both faces of the wall, because a subtraction that ends flush
## with the surface it is cutting leaves coplanar faces that flicker.
func _add_divider(combiner: CSGCombiner3D) -> void:
	var divider_center := Vector3(0.0, 0.0, CarryKnobs.DIVIDER_DEPTH)
	combiner.add_child(
		_make_brush(
			divider_center,
			Vector3(
				CarryKnobs.CHAMBER_SIZE.x,
				CarryKnobs.CHAMBER_SIZE.y,
				CarryKnobs.DIVIDER_THICKNESS
			),
			CSGShape3D.OPERATION_UNION
		)
	)
	combiner.add_child(
		_make_brush(
			divider_center,
			Vector3(
				CarryKnobs.DIVIDER_GAP.x,
				CarryKnobs.DIVIDER_GAP.y,
				CarryKnobs.DIVIDER_THICKNESS * 3.0
			),
			CSGShape3D.OPERATION_SUBTRACTION
		)
	)


## A round pillar running the full height of the room. Its collision comes from
## the same faces it is drawn with, so ROUND_PILLAR_SIDES decides how round it
## is to a rope as well as to the eye.
func _make_round_brush(brush_center: Vector3, brush_radius: float) -> CSGCylinder3D:
	var brush := CSGCylinder3D.new()
	brush.radius = brush_radius
	brush.height = CarryKnobs.CHAMBER_SIZE.y
	brush.sides = CarryKnobs.ROUND_PILLAR_SIDES
	brush.smooth_faces = true
	brush.operation = CSGShape3D.OPERATION_UNION
	brush.position = brush_center
	return brush


func _make_brush(
	brush_center: Vector3, brush_size: Vector3, operation: CSGShape3D.Operation
) -> CSGBox3D:
	var brush := CSGBox3D.new()
	brush.size = brush_size
	brush.operation = operation
	brush.position = brush_center
	return brush


# --- Carryable -------------------------------------------------------------


func _spawn_carry_object() -> void:
	var object_size := Vector3.ONE * CarryKnobs.CARRY_OBJECT_SIZE

	_carry_object = RigidBody3D.new()
	_carry_object.name = "CarryObject"
	_carry_object.mass = CarryKnobs.CARRY_OBJECT_MASS
	# Zero-g: nothing falls, it only goes where something pushed it.
	_carry_object.gravity_scale = 0.0
	_carry_object.linear_damp = CarryKnobs.CARRY_OBJECT_LINEAR_DAMP
	_carry_object.angular_damp = CarryKnobs.CARRY_OBJECT_ANGULAR_DAMP
	# A sleeping body ignores the first frames of grip force, which reads as
	# the grab having failed. It is the only carryable in the scene, so there
	# is nothing to gain by letting it sleep.
	_carry_object.can_sleep = false
	_carry_object.collision_layer = CARRYABLE_LAYER
	_carry_object.collision_mask = HULL_LAYER | PLAYER_LAYER | CARRYABLE_LAYER
	_carry_object.position = CarryKnobs.CARRY_OBJECT_SPAWN

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


## The module's lamp, sitting at its centre.
##
## Which means the module is wrapped right around its own light, and a lamp shut
## inside a solid box lights nothing at all: the shadow map is rendered from in
## there, so the six faces enclosing it put the entire room in shadow. Dropping
## the module's mesh from this lamp's shadow casters is what opens it up, and it
## is better than the alternatives - the mesh still casts a proper shadow under
## the helmet lamp and anything else in the scene, and the lamp still shows you
## every pillar between you and the walls.
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


## The module's surface, glowing in the same colour its lamp throws.
##
## Taken from a copy rather than set on the shared material, because the colour
## and the strength of the glow belong with the lamp's own values in
## carry_knobs.gd: a module that glows a different colour to the light coming
## off it reads as lit by something else in the room.
func _make_glowing_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = CARRY_OBJECT_MATERIAL.duplicate()
	material.emission_enabled = true
	material.emission = CarryKnobs.CARRY_OBJECT_LIGHT_COLOR
	material.emission_energy_multiplier = CarryKnobs.CARRY_OBJECT_GLOW
	return material
