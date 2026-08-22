@tool
class_name ElevatorShaft
extends Node3D

## The hoist frame around the elevator car: four columns, beam rings at a chosen
## pitch, a ceiling collar, and the pad it all stands on.
##
## THE ART IS A PARTS SHEET AND THIS IS THE ASSEMBLY. sm_elevator_shaft.gltf holds
## one 0.60 m post tile, one cross member, one hood and one pad, each about its own
## origin. A shaft's height and its beam pitch are level-design knobs, so no
## assembled shaft can be baked into a mesh.
##
## EVERY PLACEMENT NUMBER IS MEASURED OFF THE MESHES, not copied from the recipe.
## The cross member is authored post-centre to post-centre, so its length IS the
## column spacing; the beams sit flush with the columns' outer faces, so the ring
## radius falls out of the two cross-sections. A re-export that resizes a flange
## moves the frame with it instead of leaving a gap, which is the same reasoning
## behind ElevatorCar._assert_door_invariant.
##
## The origin is the pad's top face - the plane the car rests on - so a shaft and
## a car placed at the same transform line up with no offset to remember.
##
## PREFAB_ELEVATOR_SHAFT.TSCN IS EMPTY, AND HAS TO STAY EMPTY. Every column, beam,
## fitting and collider below is generated from the knobs and adopted without an
## owner, so none of it is serialised and a rebuild frees all of it. A child added
## to that scene by hand disappears the first time a knob moves. This note lives
## here rather than in the .tscn because Godot rewrites a scene file on import and
## drops its comments.

const MODEL := preload("res://assets/art/environment/elevator_shaft/sm_elevator_shaft.tscn")

const POST_MESH := "shaft_post"
const BEAM_MESH := "shaft_beam"
const HOOD_MESH := "shaft_hood"
const BASE_MESH := "shaft_base"

## Layer 1, `hull` - what the player and the creature both mask against. Masks
## nothing itself, matching ShellBody in prefab_elevator_car.tscn: the frame is
## scenery that stops things, not something that reacts to being stopped.
const HULL_LAYER := 1

## One voxel of the recipe's 0.06 m lattice, and the whole reason it is here: with
## the beams laid exactly flush against the columns' outer faces the two surfaces
## were coplanar, and every junction dithered against itself in the level. Set to
## zero and the z-fighting comes straight back. A cross member bolted inside the
## flange rather than skimming it is also the more honest fabrication.
const BEAM_RECESS := 0.06

## How tall the frame stands above the pad.
@export_range(1.0, 120.0, 0.06, "or_greater", "suffix:m") var shaft_height := 7.68:
	set = _set_shaft_height

## Metres between beam rings. The knob the whole asset exists to offer.
@export_range(0.6, 20.0, 0.06, "or_greater", "suffix:m") var beam_spacing := 2.4:
	set = _set_beam_spacing

## Where the lowest ring sits. Defaulted clear of the 3.18 m car, because a ring
## across the doorway is a ring the player walks into on the way out.
@export_range(0.0, 20.0, 0.06, "or_greater", "suffix:m") var first_beam_height := 3.36:
	set = _set_first_beam_height

## The collar that masks the ceiling penetration. Its own height, not the frame's:
## a shaft rises past the rock it pierces, and the fitting belongs at the rock.
@export_range(0.0, 120.0, 0.06, "or_greater", "suffix:m") var hood_height := 5.4:
	set = _set_hood_height

@export var hood_enabled := true:
	set = _set_hood_enabled

@export var pad_enabled := true:
	set = _set_pad_enabled

var _meshes: Dictionary = {}
var _generated: Array[Node] = []


func _ready() -> void:
	_rebuild()


## Clear span between the columns' inner faces. Read by verify_elevator_shaft.gd
## and by anything that needs to know whether a car fits.
func clear_bore() -> float:
	var post: Mesh = _mesh(POST_MESH)
	var beam: Mesh = _mesh(BEAM_MESH)
	if post == null or beam == null:
		return 0.0
	return beam.get_aabb().size.x - post.get_aabb().size.x


## Height of each ring above the pad, lowest first.
func beam_ring_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	if beam_spacing <= 0.0:
		return heights
	var at := first_beam_height
	while at <= shaft_height:
		heights.append(at)
		at += beam_spacing
	return heights


func _set_shaft_height(metres: float) -> void:
	shaft_height = metres
	_rebuild()


func _set_beam_spacing(metres: float) -> void:
	beam_spacing = metres
	_rebuild()


func _set_first_beam_height(metres: float) -> void:
	first_beam_height = metres
	_rebuild()


func _set_hood_height(metres: float) -> void:
	hood_height = metres
	_rebuild()


func _set_hood_enabled(enabled: bool) -> void:
	hood_enabled = enabled
	_rebuild()


func _set_pad_enabled(enabled: bool) -> void:
	pad_enabled = enabled
	_rebuild()


## Rebuilds every generated child from the current knobs.
##
## NOTHING GETS AN owner. An unowned child is not serialised, so the .tscn stays
## six lines whatever the knobs say and a re-export cannot be clobbered by a stale
## copy of the frame saved into a scene.
func _rebuild() -> void:
	if not is_node_ready():
		return
	for node: Node in _generated:
		if is_instance_valid(node):
			node.free()
	_generated.clear()

	var post: Mesh = _mesh(POST_MESH)
	var beam: Mesh = _mesh(BEAM_MESH)
	if post == null or beam == null:
		return

	var post_size := post.get_aabb().size
	var beam_size := beam.get_aabb().size
	# The cross member is authored post-centre to post-centre, so half its length
	# is where a column stands. The beams then sit just inside the columns' outer
	# faces, which is what puts the ring at this radius and not at the column
	# centres - see BEAM_RECESS for why "just inside" and not "flush".
	var post_at := beam_size.x * 0.5
	var ring_at := post_at + post_size.x * 0.5 - beam_size.z * 0.5 - BEAM_RECESS

	var body := StaticBody3D.new()
	body.name = "ShaftBody"
	body.collision_layer = HULL_LAYER
	body.collision_mask = 0
	_adopt(body)

	_build_posts(post, post_size, post_at, body)
	_build_beams(beam, beam_size, ring_at, body)
	_build_fitting(HOOD_MESH, "Hood", hood_height, hood_enabled, body)
	_build_fitting(BASE_MESH, "Pad", 0.0, pad_enabled, body)


## Four columns as one MultiMesh, each scaled to the full height.
##
## SCALED, NOT STACKED. An I-beam has no detail along its length, so one tile
## stretched is indistinguishable from fifty tiles piled up and costs forty
## triangles instead of four thousand. It is also why the recipe keeps every
## colour on the post varying across X and Z only - a band across Y would smear.
func _build_posts(post: Mesh, post_size: Vector3, post_at: float, body: StaticBody3D) -> void:
	var stretch := shaft_height / post_size.y
	var corners: Array[Vector3] = [
		Vector3(-post_at, 0.0, -post_at),
		Vector3(post_at, 0.0, -post_at),
		Vector3(post_at, 0.0, post_at),
		Vector3(-post_at, 0.0, post_at),
	]
	var placements: Array[Transform3D] = []
	for index: int in corners.size():
		var turned := Basis(Vector3.UP, index * PI * 0.5).scaled(Vector3(1.0, stretch, 1.0))
		placements.append(Transform3D(turned, corners[index]))
		_add_box(
			body,
			"PostShape%d" % index,
			Vector3(post_size.x, shaft_height, post_size.z),
			corners[index] + Vector3.UP * shaft_height * 0.5
		)
	_adopt(_multi_mesh("Posts", post, placements))


## Every ring as one MultiMesh: four members a ring, yawed a quarter turn apart.
##
## ONE MultiMeshInstance3D AND NOT A NODE EACH, which is a first for shipping code
## here. A 7.7 m shaft is three rings and would not care, but the knob goes to
## 120 m, and fifty rings authored as separate nodes is two hundred draw calls in
## a web build that has none to spare.
func _build_beams(beam: Mesh, beam_size: Vector3, ring_at: float, body: StaticBody3D) -> void:
	var placements: Array[Transform3D] = []
	var shape := Vector3(beam_size.x, beam_size.y, beam_size.z)
	for ring: int in beam_ring_heights().size():
		var at := beam_ring_heights()[ring]
		for side: int in 4:
			var turn := side * PI * 0.5
			var basis := Basis(Vector3.UP, turn)
			var offset := basis * Vector3(0.0, at, -ring_at)
			placements.append(Transform3D(basis, offset))
			_add_box(
				body,
				"BeamShape%d_%d" % [ring, side],
				shape,
				offset + Vector3.UP * beam_size.y * 0.5,
				basis
			)
	if not placements.is_empty():
		_adopt(_multi_mesh("Beams", beam, placements))


## The hood or the pad: one mesh, one box, both optional.
func _build_fitting(
	mesh_name: String, node_name: String, at: float, enabled: bool, body: StaticBody3D
) -> void:
	if not enabled:
		return
	var mesh: Mesh = _mesh(mesh_name)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	# The pad is authored bottom-up like everything else, and this node's origin is
	# the plane the car stands on, so the pad hangs below it rather than sitting on
	# it. The hood is placed by its own knob and needs no such correction.
	var bounds := mesh.get_aabb()
	var drop := 0.0 if at > 0.0 else -bounds.size.y
	instance.position = Vector3(0.0, at + drop, 0.0)
	_adopt(instance)
	_add_box(
		body, "%sShape" % node_name, bounds.size, Vector3(0.0, at + drop + bounds.size.y * 0.5, 0.0)
	)


func _multi_mesh(
	node_name: String, mesh: Mesh, placements: Array[Transform3D]
) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	# instance_count last of the three: setting it allocates the buffer, and a
	# transform written before the mesh is assigned is discarded.
	multi.instance_count = placements.size()
	for index: int in placements.size():
		multi.set_instance_transform(index, placements[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	return instance


func _add_box(
	body: StaticBody3D, shape_name: String, size: Vector3, at: Vector3, orientation: Basis = Basis()
) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = shape_name
	shape.shape = box
	shape.transform = Transform3D(orientation, at)
	body.add_child(shape)


## Adds a generated child and remembers it, without an owner. See _rebuild.
func _adopt(node: Node) -> void:
	add_child(node)
	_generated.append(node)


## One mesh out of the model, by name.
##
## BY NAME, FROM THE CONTAINER SCENE, rather than as an exported Mesh: a name
## survives a re-import and an inline resource reference does not. The same reason
## ElevatorCar._hide_parts looks its meshes up instead of authoring visibility.
func _mesh(mesh_name: String) -> Mesh:
	if _meshes.is_empty():
		_load_meshes()
	return _meshes.get(mesh_name)


func _load_meshes() -> void:
	var model := MODEL.instantiate()
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_meshes[instance.name] = instance.mesh
	model.free()
	for wanted: String in [POST_MESH, BEAM_MESH, HOOD_MESH, BASE_MESH]:
		if not _meshes.has(wanted):
			push_error(
				(
					"elevator shaft: sm_elevator_shaft has no mesh named '%s'; the model was re-exported with different node names."
					% wanted
				)
			)
