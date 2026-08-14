extends SceneTree

## Bakes the carved blockout to one static mesh and writes it out as glTF.
##
## The level is a couple of hundred CSG brushes recomputed every time the scene
## loads, which is how it stays editable and is not something anyone can open in
## Blender. This resolves the booleans once and hands over the result.
##
## GLTF SEPARATE, NOT GLB, and named with the sm_ prefix under assets/art, because
## documentation/pipeline/pipeline.yaml says so for anything shaped like a model.
## The pipeline has no phase covering a level exported as one, so this follows the
## static-mesh rules rather than inventing its own.
##
## NORMALS ARE LEFT ALONE. SurfaceTool.generate_normals would smooth across every
## corner in the mines and turn machine-cut drifts into melted tubes. CSG already
## marks the round brushes smooth and the flat ones flat, and the downstream
## Blender pass is where a decision about shading belongs.
##
##     godot --headless --path . --script res://tools/level_design/export_level_model.gd
##     ... export_level_model.gd -- --level=res://levels/design/level_mine_blockout.tscn

const DEFAULT_LEVEL := "res://levels/design/level_full_blockout.tscn"
const OUTPUT_DIRECTORY := "res://assets/art/environment/level_blockout"

## Frames to let the CSG tree resolve before baking. The combiner rebuilds on a
## deferred call, and baking too early returns the mesh from before the carve.
const SETTLE_FRAMES := 180


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var level_path := _requested_level()
	var level := load(level_path).instantiate() as MineLevel
	if level == null:
		printerr("export_level_model: %s does not have a MineLevel root" % level_path)
		quit(1)
		return
	level.name = "Level"
	root.add_child(level)

	var builder := LevelGeometryBuilder.new()
	builder.name = "LevelGeometry"
	builder.build_on_ready = false
	root.add_child(builder)
	builder.level_path = builder.get_path_to(level)
	builder.build()
	for frame: int in SETTLE_FRAMES:
		await process_frame

	var combiner := builder.get_node_or_null("HullCombiner") as CSGCombiner3D
	if combiner == null:
		printerr("export_level_model: nothing was carved")
		quit(1)
		return

	var baked := combiner.bake_static_mesh()
	if baked == null or baked.get_surface_count() == 0:
		printerr("export_level_model: the carve produced no mesh to bake")
		quit(1)
		return

	var mesh := _welded(baked)
	var model_name := "sm_%s" % level_path.get_file().get_basename()
	var written := _write_gltf(mesh, model_name)
	if written.is_empty():
		quit(1)
		return

	_report(mesh, model_name, written)
	quit(0)


## The baked mesh with its coincident vertices joined up.
##
## CSG emits every triangle standalone, so the raw bake has three unshared
## vertices per face and no index buffer at all - several times the file size, and
## an importer that cannot tell a seam from a smooth join. Indexing merges only
## vertices that agree on everything including the normal, so a hard edge stays a
## hard edge.
func _welded(baked: ArrayMesh) -> ArrayMesh:
	var rock := StandardMaterial3D.new()
	rock.resource_name = "rock"
	rock.albedo_color = Color(0.34, 0.35, 0.37)
	rock.metallic = 0.1
	rock.metallic_specular = 0.3
	rock.roughness = 0.85

	var mesh := ArrayMesh.new()
	# Distinct from the material's name: glTF namespaces both together and renames
	# the loser, which is how a material called "rock" arrives in Blender as "rock2".
	mesh.resource_name = "level_rock"
	for surface: int in baked.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(baked, surface)
		tool.index()
		tool.generate_tangents()
		tool.set_material(rock)
		tool.commit(mesh)
	return mesh


## Writes the mesh as glTF Separate and returns the file it wrote, or "" on failure.
func _write_gltf(mesh: ArrayMesh, model_name: String) -> String:
	if DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY) != OK:
		printerr("export_level_model: could not create %s" % OUTPUT_DIRECTORY)
		return ""

	# Both nodes stay at identity: validate-model-files.py fails any pivot carrying
	# a rotation over half a degree or a scale off 1.0, and a level baked anywhere
	# other than its own origin is a level nobody can line anything else up against.
	var holder := Node3D.new()
	holder.name = model_name
	var surface := MeshInstance3D.new()
	surface.name = "%s_mesh" % model_name
	surface.mesh = mesh
	holder.add_child(surface)
	surface.owner = holder
	root.add_child(holder)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(holder, state)
	if append_error != OK:
		printerr("export_level_model: append_from_scene failed (%d)" % append_error)
		return ""

	var target := "%s/%s.gltf" % [OUTPUT_DIRECTORY, model_name]
	var write_error := document.write_to_filesystem(state, target)
	if write_error != OK:
		printerr("export_level_model: write_to_filesystem failed (%d)" % write_error)
		return ""
	return target


func _report(mesh: ArrayMesh, model_name: String, target: String) -> void:
	var triangles := 0
	for surface: int in mesh.get_surface_count():
		triangles += mesh.surface_get_array_index_len(surface) / 3
	var bounds := mesh.get_aabb()

	print("wrote %s" % target)
	print("  %d triangles in %d surface(s)" % [triangles, mesh.get_surface_count()])
	print(
		(
			"  %.0f x %.0f x %.0f m, centred on %.1f, %.1f, %.1f"
			% [
				bounds.size.x,
				bounds.size.y,
				bounds.size.z,
				bounds.get_center().x,
				bounds.get_center().y,
				bounds.get_center().z,
			]
		)
	)
	# Godot numbers the buffers it writes, so the geometry lands beside the .gltf as
	# <name>0.bin rather than <name>.bin. Listed rather than guessed, because the
	# .bin is the half that actually has to be committed with it.
	var written := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(OUTPUT_DIRECTORY):
		if not file_name.begins_with(model_name):
			continue
		if not (file_name.ends_with(".gltf") or file_name.ends_with(".bin")):
			continue
		var handle := FileAccess.open("%s/%s" % [OUTPUT_DIRECTORY, file_name], FileAccess.READ)
		if handle == null:
			continue
		written.append("%s %.1f MB" % [file_name, handle.get_length() / 1048576.0])
	print("  %s" % ", ".join(written))


func _requested_level() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			return argument.substr("--level=".length())
	return DEFAULT_LEVEL
