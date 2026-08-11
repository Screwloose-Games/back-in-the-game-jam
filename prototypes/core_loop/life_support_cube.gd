class_name LifeSupportCube
extends RigidBody3D

## The thing you have to bring with you.
##
## A battery you can pick up, tether to and crank. It carries the charge your suit
## lives off, so every metre you go from it is a metre you have to come back, and
## moving it is the only way to work anywhere new.
##
## Built in code rather than authored as a scene for one reason: the glowing
## material has to be DUPLICATED per instance. Its emission is driven by the charge
## curve, and a shared material would mean the cube's own dimming reached into
## every other thing that used the same .tres.
##
## The power rules are not here. This node owns a PowerStore and knows how full it
## is; CoreLoopPowerSystem owns every question about where charge goes. That split
## is what lets the same PowerStore serve a 100-unit suit battery that leaks
## constantly and this 600-unit one that never does.

const CUBE_MATERIAL := preload(
	"res://prototypes/object_carrying/materials/carry_object_material.tres"
)

## Every render layer there is, for the shadow caster mask below.
const ALL_RENDER_LAYERS := 0xFFFFFFFF

var _spawn_position := Vector3.ZERO
var _glow_curve: Curve

@onready var _store: PowerStore = $CubePower
@onready var _gauge: CubePowerGauge = $PowerGauge
@onready var _lamp: OmniLight3D = $CubeLamp
@onready var _mesh: MeshInstance3D = $CubeMesh


func _init() -> void:
	mass = CoreLoopKnobs.CUBE_MASS
	# There is no down here. Damping stands in for the air the cube is not moving
	# through, so a nudge dies out instead of leaving it drifting forever.
	gravity_scale = 0.0
	linear_damp = CoreLoopKnobs.CUBE_LINEAR_DAMP
	angular_damp = CoreLoopKnobs.CUBE_ANGULAR_DAMP
	# A sleeping cube ignores the tether, which reads as the rope having come
	# undone.
	can_sleep = false
	collision_layer = CoreLoopKnobs.CARRYABLE_LAYER
	collision_mask = (
		CoreLoopKnobs.HULL_LAYER | CoreLoopKnobs.PLAYER_LAYER | CoreLoopKnobs.CARRYABLE_LAYER
	)
	_build()


func _ready() -> void:
	_spawn_position = global_position
	_store.configure(
		CoreLoopKnobs.CUBE_CAPACITY,
		CoreLoopKnobs.CUBE_START_FRACTION,
		CoreLoopKnobs.CUBE_IDLE_DRAIN_PER_SECOND
	)
	_gauge.build(CoreLoopKnobs.CUBE_SIZE)
	_glow_curve = LampPowerResponse.build_curve(CoreLoopKnobs.CUBE_GLOW_POINTS, 1.0)

	_store.charge_changed.connect(_on_charge_changed)
	_on_charge_changed(_store.get_fraction())


## The battery inside. CoreLoopPowerSystem takes it from here rather than being
## handed one, so there is no way to bind the wrong store to the wrong cube.
func get_store() -> PowerStore:
	return _store


## The cube's lamp, for whatever is dimming it with the charge.
func get_lamp() -> OmniLight3D:
	return _lamp


## Back to the spawn pose, fully at rest. Paired with the suit's own respawn so
## one key restarts the whole run rather than leaving the cube wherever the last
## attempt abandoned it.
func respawn() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, _spawn_position)
	_store.set_fraction(CoreLoopKnobs.CUBE_START_FRACTION)


func _build() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CoreLoopKnobs.CUBE_SIZE

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CubeMesh"
	mesh_instance.mesh = box
	# Duplicated, not shared - see the class docstring.
	mesh_instance.material_override = CUBE_MATERIAL.duplicate()
	mesh_instance.layers = CoreLoopKnobs.CUBE_RENDER_LAYER
	add_child(mesh_instance)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * CoreLoopKnobs.CUBE_SIZE
	shape.shape = box_shape
	add_child(shape)

	var lamp := OmniLight3D.new()
	lamp.name = "CubeLamp"
	lamp.light_color = CoreLoopKnobs.CUBE_LIGHT_COLOR
	lamp.light_energy = CoreLoopKnobs.CUBE_LIGHT_ENERGY
	lamp.omni_range = CoreLoopKnobs.CUBE_LIGHT_RANGE
	lamp.omni_attenuation = CoreLoopKnobs.CUBE_LIGHT_ATTENUATION
	lamp.shadow_enabled = CoreLoopKnobs.CUBE_LIGHT_SHADOWS
	# The lamp is inside the box. Without excluding the cube's own render layer it
	# casts the box's shadow over everything, and the room goes black.
	lamp.shadow_caster_mask = ALL_RENDER_LAYERS & ~CoreLoopKnobs.CUBE_RENDER_LAYER
	add_child(lamp)

	var store := PowerStore.new()
	store.name = "CubePower"
	add_child(store)

	var gauge := CubePowerGauge.new()
	gauge.name = "PowerGauge"
	add_child(gauge)


## The faces sag ahead of the lamp, so the cube announces its own trouble before
## the light it casts does.
func _on_charge_changed(fraction: float) -> void:
	_gauge.show_fraction(fraction)
	var glow := _glow_curve.sample(fraction)
	var material := _mesh.material_override as StandardMaterial3D
	if material != null:
		material.emission_energy_multiplier = CoreLoopKnobs.CUBE_GLOW * glow
