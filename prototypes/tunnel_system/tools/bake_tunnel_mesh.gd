extends SceneTree

## Bakes paths/tunnel_paths.tscn into baked/tunnel_geometry.tscn plus one mesh
## and one collision shape per chunk.
##
##   godot --headless --path <root> --script res://prototypes/tunnel_system/tools/bake_tunnel_mesh.gd
##
## Reads the Path3D CURVES IN THE SCENE, never the layout table in
## tunnel_knobs.gd - which is what makes "drag a curve point in the editor, re-run
## this, fly it" the actual workflow rather than an aspiration.
##
## Everything under baked/ is generated. Editing it by hand is wasted work; the
## next run overwrites the lot.

const CHUNK_PREFIX := "tunnel_chunk_"


func _initialize() -> void:
	var error := _check_knobs()
	if error == "":
		error = _run()
	if error != "":
		printerr("REFUSING TO EMIT: %s" % error)
		quit(1)
		return
	quit(0)


func _run() -> String:
	var paths_scene := load(_res("../paths/tunnel_paths.tscn")) as PackedScene
	if paths_scene == null:
		return "could not load paths/tunnel_paths.tscn - run build_tunnel_paths.gd first"
	var paths_root := paths_scene.instantiate()

	var network := TunnelNetwork.from_scene(
		paths_root.get_node_or_null("Paths"), paths_root.get_node_or_null("Chambers")
	)
	if network.routes.is_empty():
		return "tunnel_paths.tscn contains no usable Path3D nodes"

	print(
		(
			"baking %d routes / %d segments / %d chambers at %.2f m cells..."
			% [
				network.routes.size(),
				network.segment_count(),
				network.chamber_centers.size(),
				TunnelKnobs.CELL_SIZE,
			]
		)
	)

	var baker := TunnelSdfBaker.new()
	var bake_error := baker.bake(network)
	if bake_error != "":
		return bake_error
	if baker.skipped_quads > 0:
		return (
			"%d quads had a missing corner cell, which means the shell has holes in it"
			% baker.skipped_quads
		)

	var meshes := baker.chunk_meshes()
	var baked_dir := _res("../baked")
	DirAccess.make_dir_recursive_absolute(baked_dir)
	var removed := _clear_stale(baked_dir)

	var root := Node3D.new()
	root.name = "TunnelGeometry"
	var rock: Material = load(_res("../materials/tunnel_rock.tres"))
	for key: Vector3i in meshes:
		_emit_chunk(root, key, meshes[key], rock, baked_dir)

	var scene_path := baked_dir.path_join("tunnel_geometry.tscn")
	var write_error := _write_scene(root, scene_path)
	root.free()
	paths_root.free()
	if write_error != "":
		return write_error

	# Measured by walking the directory AFTER every save has completed. Summing
	# each file's length immediately after ResourceSaver.save() returns reads it
	# before the write is flushed, and under-reports by a factor of three - which
	# is worse than not reporting it, because it looks like a measurement.
	var mesh_bytes := _bytes_matching(baked_dir, "_shape.res", false)
	var shape_bytes := _bytes_matching(baked_dir, "_shape.res", true)

	print(
		(
			"wrote %s\n  %d chunks, %d triangles, %d vertices, %.1f MB mesh + %.1f MB collision (%d stale files removed)\n  %d surface cells from %d candidates, winding %.1f%% air-facing%s, %.1f s"
			% [
				scene_path,
				meshes.size(),
				baker.triangle_count,
				baker.vertex_count,
				float(mesh_bytes) / 1048576.0,
				float(shape_bytes) / 1048576.0,
				removed,
				baker.surface_cells,
				baker.cells_considered,
				baker.winding_agreement * 100.0,
				" (AUTO-FLIPPED)" if baker.winding_flipped else "",
				baker.bake_seconds,
			]
		)
	)
	return ""


## Knob relationships the baker cannot survive being wrong about.
func _check_knobs() -> String:
	var chunk_cells := TunnelKnobs.CHUNK_SIZE / TunnelKnobs.CELL_SIZE
	if absf(chunk_cells - round(chunk_cells)) > 1e-6:
		return (
			"CHUNK_SIZE %.3f is not a whole number of %.3f m cells - chunk boundaries would land mid-cell and open seams"
			% [TunnelKnobs.CHUNK_SIZE, TunnelKnobs.CELL_SIZE]
		)
	return ""


func _write_scene(root: Node3D, scene_path: String) -> String:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return "pack() failed"
	if ResourceSaver.save(packed, scene_path) != OK:
		return "save(%s) failed" % scene_path
	_relativise(scene_path)
	return ""


## One StaticBody3D per chunk, carrying its mesh and its own trimesh collider.
##
## The mesh and the shape are saved as separate binary resources rather than
## embedded: a ConcavePolygonShape3D inlined into a text scene writes every
## triangle out as three unindexed vertices in ASCII, which for this network is
## tens of megabytes of .tscn that no diff can survive.
func _emit_chunk(
	root: Node3D, key: Vector3i, mesh: ArrayMesh, rock: Material, baked_dir: String
) -> void:
	var slug := "%s_%s_%s" % [_axis_slug(key.x), _axis_slug(key.y), _axis_slug(key.z)]
	var mesh_path := baked_dir.path_join("%s%s.res" % [CHUNK_PREFIX, slug])
	if ResourceSaver.save(mesh, mesh_path) != OK:
		printerr("save(%s) failed" % mesh_path)
		return

	var shape := mesh.create_trimesh_shape()
	var shape_path := baked_dir.path_join("%s%s_shape.res" % [CHUNK_PREFIX, slug])
	if ResourceSaver.save(shape, shape_path) != OK:
		printerr("save(%s) failed" % shape_path)
		return

	# SAVING A RESOURCE DOES NOT GIVE THE IN-MEMORY OBJECT ITS PATH. Without
	# take_over_path, `mesh` and `shape` are still pathless as far as
	# PackedScene.pack() can tell, so it inlines both of them into the .tscn as
	# sub_resources - every vertex and every collision triangle, base64'd into a
	# text file. That produced a 22.5 MB scene next to 10.5 MB of .res files
	# nothing referenced, and it does not error, does not warn, and loads fine.
	mesh.take_over_path(mesh_path)
	shape.take_over_path(shape_path)

	var body := StaticBody3D.new()
	body.name = "chunk_%s" % slug
	body.collision_layer = TunnelKnobs.HULL_LAYER
	body.collision_mask = 0
	_adopt(body, root, root)

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	mesh_node.material_override = rock
	# No global illumination contribution: there is no baked light down here and
	# GI on a few hundred chunks is pure cost on GL Compatibility.
	mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_adopt(mesh_node, body, root)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_adopt(collision, body, root)


## Chunk indices are signed, so -2 becomes "m2" rather than "-2" - a leading
## minus in a filename is legal but reads as a command-line flag everywhere else.
func _axis_slug(value: int) -> String:
	return ("m%d" % -value) if value < 0 else ("p%d" % value)


## Drops chunk resources left by a previous bake. A layout change moves chunks,
## and an orphan .res is still loadable, so nothing would ever complain about a
## stale wall sitting in the middle of a tunnel that no longer exists.
func _clear_stale(baked_dir: String) -> int:
	var dir := DirAccess.open(baked_dir)
	if dir == null:
		return 0
	var removed := 0
	for name: String in dir.get_files():
		if name.begins_with(CHUNK_PREFIX) and name.ends_with(".res"):
			if dir.remove(name) == OK:
				removed += 1
	return removed


## Total bytes of chunk resources whose name does or does not end in `suffix`.
func _bytes_matching(baked_dir: String, suffix: String, want_suffix: bool) -> int:
	var dir := DirAccess.open(baked_dir)
	if dir == null:
		return 0
	var total := 0
	for name: String in dir.get_files():
		if not name.begins_with(CHUNK_PREFIX) or not name.ends_with(".res"):
			continue
		if name.ends_with(suffix) != want_suffix:
			continue
		var file := FileAccess.open(baked_dir.path_join(name), FileAccess.READ)
		if file == null:
			continue
		total += file.get_length()
		file.close()
	return total


## add_child THEN set owner, or PackedScene.pack() silently drops the node.
func _adopt(node: Node, parent: Node, root: Node) -> void:
	parent.add_child(node)
	node.owner = root


## ResourceSaver writes absolute res:// paths and FLAG_RELATIVE_PATHS still does
## nothing to text scenes in 4.7.1. Derived from this script's location, never
## written down.
func _relativise(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("could not reopen %s to relativise its paths" % path)
		return
	var text := file.get_as_text()
	file.close()
	text = text.replace(_res("..") + "/", "../")
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(text)
	out.close()


func _res(relative_path: String) -> String:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	return dir.path_join(relative_path).simplify_path()
