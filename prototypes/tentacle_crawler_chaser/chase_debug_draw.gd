class_name ChaseDebugDraw
extends Node3D

## Wireframe of the baked navmesh and of the path the creature is currently
## walking. Hidden until F1.
##
## Worth having because the navmesh here is hand-assembled, and the failure mode
## that costs the most time is invisible: a mesh whose quads all exist and none of
## which share edges looks perfect and cannot be pathed across. The overlay makes
## the difference obvious - a path that stops dead at a surface boundary is a
## welding failure, a path that never appears is an empty map, and a mesh with
## nothing under the divider is the openness probe doing its job.
##
## Two meshes rather than one, because the navmesh is about 7000 line segments and
## the path is about ten. The navmesh is uploaded once when the bake finishes; only
## the path is rebuilt as the creature moves.

@export var baker: WallNavmeshBaker
@export var follower: ChaseTargetFollower
@export var navmesh_color := Color(0.24, 0.62, 0.72, 1.0)
@export var path_color := Color(1.0, 0.62, 0.2, 1.0)

var _navmesh_view: MeshInstance3D
var _path_view: MeshInstance3D
var _path_mesh: ImmediateMesh


func _ready() -> void:
	top_level = true
	visible = false

	_navmesh_view = _make_view(navmesh_color, false)
	_path_mesh = ImmediateMesh.new()
	_path_view = _make_view(path_color, true)
	_path_view.mesh = _path_mesh

	if baker != null:
		baker.baked.connect(_rebuild_navmesh)


func _process(_delta: float) -> void:
	if visible:
		_rebuild_path()


func _make_view(color: Color, always_on_top: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	# The chamber's fog closes down at 30 m and would swallow most of the mesh.
	material.disable_fog = true
	# The path draws through geometry on purpose: half of what you want to know
	# is where the creature is heading while it is still behind a wall. The
	# navmesh does not, or every surface in the room overlaps every other one.
	material.no_depth_test = always_on_top
	material.render_priority = 1 if always_on_top else 0

	var view := MeshInstance3D.new()
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	return view


func _rebuild_navmesh() -> void:
	var edges := baker.debug_edges()
	if edges.is_empty():
		_navmesh_view.mesh = null
		return

	# One array upload rather than 7000 surface_add_vertex calls, which is the
	# difference between a toggle and a stall.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = edges
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_navmesh_view.mesh = mesh


func _rebuild_path() -> void:
	_path_mesh.clear_surfaces()
	if follower == null:
		return
	var corners := follower.path_points()
	if corners.size() < 2:
		return

	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for corner: Vector3 in corners:
		_path_mesh.surface_add_vertex(corner)
	_path_mesh.surface_end()
