extends SceneTree

## Checks what Godot actually made of the voxel props.
##
##   D:\Godot_v4.7.1-stable_win64.exe --headless --path <root> \
##     --script res://tools/voxel-props/verify_props_import.gd
##
## validate-model-files.py reads the glTF JSON, which is the right place to
## check the file. It cannot see what the importer then does with it, and four
## of the things these assets depend on are decided there and nowhere else:
##
## - The palette only survives if the material samples it with a NEAREST filter
##   and the texture is neither mipmapped nor block-compressed. The glTF sampler
##   asks for nearest; whether Godot honoured it is decided on import, and
##   detect_3d/compress_to would re-import the PNG as ETC2 the first time a 3D
##   material bound it. ETC2 compresses in 4x4 blocks and the palette IS a 4x4
##   block grid, so every swatch would become an average of itself.
## - The importer is free to rescale a scene. The 0.06 m voxel is the whole
##   style, so it gets measured after import, not before.
## - The anchor Empties on the laser are invisible to every check in the
##   validator, because nothing there looks at a node with no mesh. That is what
##   makes them free, and it is why they are asserted here.
## - A container scene that has been flattened into a baked copy still loads,
##   still renders and quietly stops tracking the model.

const VOXEL := 0.06
const TOLERANCE := 0.001

## stem -> the mesh nodes it must import as, in any order, and how many surfaces
## each mesh must carry. A lost emissive surface has no symptom but a dark lamp.
const EXPECTED := {
	"res://assets/art/gameplay/mining_laser/sm_mining_laser.gltf":
	{
		"meshes": {"cutter_body": 2},
		"anchors": ["muzzle_point", "fore_grip_point", "rear_grip_point"]
	},
	"res://assets/art/environment/elevator_car/sm_elevator_car.gltf":
	{"meshes": {"car_shell": 2, "door_left": 1, "door_right": 1}, "anchors": []},
	"res://assets/art/environment/elevator_shaft/sm_elevator_shaft.gltf":
	{"meshes": {"shaft_base": 1, "shaft_post": 1, "shaft_beam": 1, "shaft_hood": 1}, "anchors": []},
	"res://assets/art/environment/wall_switch/sm_wall_switch.gltf":
	{"meshes": {"switch_housing": 1, "switch_paddle": 1}, "anchors": []},
}


func _initialize() -> void:
	var failures := 0
	for path in EXPECTED:
		failures += _check(path, EXPECTED[path])
	if failures > 0:
		printerr("%d check(s) failed" % failures)
		quit(1)
		return
	print("all prop imports OK")
	quit(0)


func _check(path: String, expected: Dictionary) -> int:
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("%s: did not import as a PackedScene" % path)
		return 1

	var root := scene.instantiate()
	var problems := PackedStringArray()
	var meshes: Dictionary = {}
	var others: Dictionary = {}
	_collect(root, meshes, others)

	for name in expected["meshes"]:
		if not meshes.has(name):
			problems.append("no MeshInstance3D named '%s'" % name)
	for name in meshes:
		if not expected["meshes"].has(name):
			problems.append("unexpected MeshInstance3D '%s'" % name)

	for name in expected["anchors"]:
		if not others.has(name):
			problems.append("no anchor node '%s'" % name)

	for name in meshes:
		if not expected["meshes"].has(name):
			continue
		problems.append_array(_check_mesh(name, meshes[name], expected["meshes"][name]))

	problems.append_array(_check_container(path))
	root.free()

	if problems.is_empty():
		print("OK   %s" % path.get_file())
		return 0
	printerr("FAIL %s: %s" % [path.get_file(), ", ".join(problems)])
	return 1


func _check_mesh(name: String, instance: MeshInstance3D, surfaces: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var mesh := instance.mesh

	# basis, not transform: a translation is how an articulated part carries its
	# pivot and is expected. A rotation or a scale is not, and would mean the
	# writer let one through.
	if not instance.transform.basis.is_equal_approx(Basis.IDENTITY):
		problems.append("%s carries a rotation or scale: %s" % [name, instance.transform.basis])

	var aabb := mesh.get_aabb()
	for axis in 3:
		var span: float = aabb.size[axis]
		var voxels := span / VOXEL
		if absf(voxels - roundf(voxels)) > TOLERANCE:
			problems.append(
				(
					"%s axis %d spans %.4f m, not a whole number of %.2f m voxels"
					% [name, axis, span, VOXEL]
				)
			)

	if mesh.get_surface_count() != surfaces:
		problems.append(
			"%s has %d surface(s), expected %d" % [name, mesh.get_surface_count(), surfaces]
		)

	for surface in mesh.get_surface_count():
		problems.append_array(_check_material(name, surface, mesh.surface_get_material(surface)))
	return problems


## The palette checks. Everything here is invisible to the glTF validator and to
## the import log, and each one degrades the art silently rather than loudly.
func _check_material(name: String, surface: int, material: Material) -> PackedStringArray:
	var problems := PackedStringArray()
	var base := material as BaseMaterial3D
	if base == null:
		problems.append("%s surface %d has no BaseMaterial3D" % [name, surface])
		return problems

	if base.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		problems.append(
			(
				"%s surface %d filters the palette with %d, not NEAREST"
				% [name, surface, base.texture_filter]
			)
		)

	var texture := base.albedo_texture
	if texture == null:
		problems.append("%s surface %d has no albedo texture" % [name, surface])
		return problems

	var image := texture.get_image()
	if image == null:
		problems.append("%s surface %d albedo texture has no image" % [name, surface])
		return problems
	if image.is_compressed():
		problems.append(
			(
				"%s surface %d palette is block-compressed (format %d); the 4x4 swatches are gone"
				% [name, surface, image.get_format()]
			)
		)
	if image.has_mipmaps():
		problems.append(
			"%s surface %d palette has mipmaps; distant swatches will blend" % [name, surface]
		)
	return problems


## Every model needs a container scene beside it, and it has to stay inherited.
##
## A container flattened into a baked copy still loads, still renders and still
## looks right -- and quietly stops tracking the model, so a regenerated mesh
## never reaches the level. That failure has no symptom at the moment it
## happens, which is why it is asserted here.
func _check_container(model_path: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var scene_path := "%s.tscn" % model_path.get_basename()
	if not ResourceLoader.exists(scene_path):
		problems.append("no container scene at %s" % scene_path.get_file())
		return problems

	var text := FileAccess.get_file_as_string(scene_path)
	if text.contains("[sub_resource"):
		problems.append("%s is a baked copy, not an inherited scene" % scene_path.get_file())
	if not text.contains("instance=ExtResource"):
		problems.append("%s root does not instance the model" % scene_path.get_file())
	if not text.contains(model_path):
		problems.append("%s inherits something other than this model" % scene_path.get_file())
	return problems


func _collect(node: Node, meshes: Dictionary, others: Dictionary) -> void:
	var instance := node as MeshInstance3D
	if instance != null:
		meshes[String(node.name)] = instance
	elif node.get_parent() != null:
		others[String(node.name)] = node
	for child in node.get_children():
		_collect(child, meshes, others)
