class_name OreNode
extends Node3D

## One crystal, buried in a ball of destructible rock.
##
## This is the only destructible thing in the prototype. The chamber walls are
## not, the pillars are not, and nothing here generalises to them - a node is a
## 2.4 m cube of signed distance field, not terrain.
##
## THREE THINGS ARE KEPT DELIBERATELY OUT OF STEP, and knowing which is which is
## most of understanding this file:
##
##   the FIELD    always current. The drill erodes it and reads it back the same
##                frame, so what you cut is exactly what you aimed at.
##   the MESH     one or two frames behind under sustained fire. Remeshing is
##                GDScript and runs on a budget - see DrillKnobs.REMESH_BUDGET.
##   the COLLISION rebuilt with the mesh, so equally behind. Nothing that has to
##                be exact uses it: the drill walks the field, and this exists so
##                that you bump into a node while flying.

## Emitted the moment the rock lets go, before the crystal has moved.
signal crystal_freed(node: OreNode)

enum CrystalState {
	EMBEDDED,
	FREE,
	COLLECTED,
}

const ROCK_MATERIAL := preload("res://prototypes/drill_and_mining/materials/rock_material.tres")
const CRYSTAL_MATERIAL := preload(
	"res://prototypes/drill_and_mining/materials/crystal_material.tres"
)

## The golden angle, PI * (3 - sqrt(5)), written out because a call to sqrt() is
## not allowed in a const expression.
const GOLDEN_ANGLE := 2.399963229728653

## Where fragments go. Assigned by the prototype root before build(); a node
## without one simply carves in silence, which is also what DEBRIS_ENABLED off
## looks like.
var debris_pool: OreDebrisPool

var _field: VoxelField
var _mesher := SurfaceNetMesher.new()
var _crystal: RigidBody3D
var _crystal_mesh: MeshInstance3D
var _crystal_collider: CollisionShape3D
var _rock_body: StaticBody3D

## One MeshInstance3D and one CollisionShape3D per sub-chunk, by grid position.
var _meshes := {}
var _shapes := {}

var _escape_directions := PackedVector3Array()
var _crystal_state := CrystalState.EMBEDDED
var _release_authority := true
var _hardness := 1.0
var _escape_clearance := DrillKnobs.ESCAPE_CLEARANCE
var _original_solid_corners := 1

## Set by a carve, cleared once the escape test has been re-run. The test is a
## few hundred field samples, so it runs when something changed and not per frame.
var _escape_check_pending := false

## The widest clear tube out of the crystal found by the last escape test, in
## metres. Cached rather than measured on demand: the HUD reads it every frame
## and it can only change when rock does.
var _widest_opening := 0.0

## Seconds until the escape test may run again. See ESCAPE_CHECK_INTERVAL.
var _escape_cooldown := 0.0


func _process(delta: float) -> void:
	if _field == null:
		return
	_flush_remesh(DrillKnobs.REMESH_BUDGET)
	_escape_cooldown -= delta
	if _escape_check_pending and _escape_cooldown <= 0.0:
		_escape_cooldown = DrillKnobs.ESCAPE_CHECK_INTERVAL
		_escape_check_pending = false
		_measure_escape()


## Everything the last carve left owing, at once, with no frame budget and no
## cooldown.
##
## Public so the headless suite can pump a node without a frame - _process never
## fires inside a single _ready, and a verifier that silently tested nothing is
## worse than no verifier.
func run_pending_work() -> void:
	if _field == null:
		return
	_flush_remesh(_field.subchunks_per_axis ** 3)
	if _escape_check_pending:
		_escape_check_pending = false
		_measure_escape()


## Generates the whole node. `node_seed` makes it reproducible and `hardness`
## divides the carve rate.
func build(node_seed: int, hardness: float, clearance: float) -> void:
	_hardness = maxf(hardness, 0.01)
	_escape_clearance = clearance

	var rng := RandomNumberGenerator.new()
	rng.seed = node_seed

	_field = VoxelField.new(
		DrillKnobs.FIELD_RESOLUTION, DrillKnobs.VOXEL_SIZE, DrillKnobs.SUBCHUNK_CELLS
	)
	_field.fill_sphere(DrillKnobs.NODE_RADIUS, DrillKnobs.NODE_SURFACE_NOISE, rng)
	_original_solid_corners = maxi(_field.count_solid_corners(), 1)

	_build_crystal()
	_build_rock_body()
	_build_escape_directions()
	# Everything, once, before the first frame is drawn. The per-frame budget is
	# for carving; a node that faded in over nine frames on load would just look
	# broken.
	_flush_remesh(_field.subchunks_per_axis ** 3)


## Pushes the tuned numbers that reach into an already-generated node. Must not
## write back to the settings resource - it is called from the changed signal.
func apply_tuning(clearance: float) -> void:
	_escape_clearance = clearance
	if _crystal_state == CrystalState.EMBEDDED:
		_escape_check_pending = true


## Eats away at the rock around a world-space point. `amount` is how far the
## surface should recede at the centre of the bore, before this node's hardness.
## Returns true if any rock actually went.
func carve(world_point: Vector3, radius: float, amount: float) -> bool:
	if _field == null:
		return false
	var eaten := _field.erode(to_local(world_point), radius, amount / _hardness)
	if eaten and _crystal_state == CrystalState.EMBEDDED:
		_escape_check_pending = true
	return eaten


## How far along a ray this node's rock is, in metres, or -1 for a miss.
##
## Answers for the crystal too, and says which it was, because the beam has to
## stop on a crystal and refuse to cut it - and once the rock in front of the
## crystal is gone there is nothing in the field left to stop the ray.
func cast(world_origin: Vector3, world_direction: Vector3, max_distance: float) -> Dictionary:
	if _field == null:
		return {}
	var origin := to_local(world_origin)
	var direction := (to_local(world_origin + world_direction) - origin).normalized()

	var crystal_distance := _crystal_hit(origin, direction, max_distance)
	var rock_distance := _field.raymarch(origin, direction, max_distance)

	if rock_distance < 0.0 and crystal_distance < 0.0:
		return {}
	var on_crystal := (
		rock_distance < 0.0 or (crystal_distance >= 0.0 and crystal_distance < rock_distance)
	)
	var distance := crystal_distance if on_crystal else rock_distance
	var landing := origin + direction * distance
	return {
		"distance": distance,
		"position": world_origin + world_direction * distance,
		"is_crystal": on_crystal,
		"normal": _surface_normal(landing, on_crystal),
	}


## Whether the rock has let go of the crystal yet.
func is_crystal_free() -> bool:
	return _crystal_state != CrystalState.EMBEDDED


## Enables the one peer allowed to derive a release from the mutable field.
## Single-player nodes retain authority unless their multiplayer owner opts out.
func set_release_authority(has_authority: bool) -> void:
	_release_authority = has_authority
	if _crystal_state == CrystalState.FREE:
		_crystal.freeze = not _release_authority


func get_crystal_state() -> CrystalState:
	return _crystal_state


## Marks a loose crystal collected without deleting the replicated body.
## Only the authoritative simulation may originate this transition.
func collect_crystal() -> bool:
	if not _release_authority or _crystal_state != CrystalState.FREE:
		return false
	_set_crystal_state(CrystalState.COLLECTED)
	return true


## Applies an authoritative crystal snapshot. A non-authoritative FREE crystal
## remains frozen so local physics cannot fight the incoming transforms.
func apply_crystal_replica_state(
	state: int, world_transform: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3
) -> void:
	if state < CrystalState.EMBEDDED or state > CrystalState.COLLECTED:
		push_warning("Ignoring invalid replicated crystal state: %d" % state)
		return
	var replica_state: CrystalState = state as CrystalState
	_set_crystal_state(replica_state)
	_crystal.global_transform = world_transform
	_crystal.linear_velocity = linear_velocity
	_crystal.angular_velocity = angular_velocity


## Restores the crystal body to its generated, buried state.
func reset_crystal_to_embedded() -> void:
	_set_crystal_state(CrystalState.EMBEDDED)
	_crystal.transform = Transform3D.IDENTITY
	_crystal.linear_velocity = Vector3.ZERO
	_crystal.angular_velocity = Vector3.ZERO
	# A reset can follow a FREE or COLLECTED session, where field imports do not
	# schedule an escape measurement. Invalidate every derived opening value so
	# the fresh field cannot inherit stale HUD/release state from the old session.
	_widest_opening = 0.0
	_escape_cooldown = 0.0
	_escape_check_pending = true


## Full-field snapshots are intentionally a boundary on OreNode: networking
## does not need to know how the destructible field stores its corners.
func export_field_values() -> PackedFloat32Array:
	if _field == null:
		return PackedFloat32Array()
	return _field.export_values()


func import_field_values(values: PackedFloat32Array) -> bool:
	if _field == null:
		return false
	var imported := _field.import_values(values)
	if imported and _crystal_state == CrystalState.EMBEDDED:
		_escape_check_pending = true
	return imported


## The crystal body, so the prototype root can watch it being collected.
func get_crystal() -> RigidBody3D:
	return _crystal


## How much of the rock is left, 0 to 1. The HUD's "rock" reading.
func get_rock_fraction() -> float:
	if _field == null:
		return 0.0
	return _field.solid_fraction(_original_solid_corners)


## How wide the widest clear tube out of the crystal was when the rock last
## moved, in metres - the HUD's countdown to the crystal coming loose.
func get_widest_opening() -> float:
	return _widest_opening


# --- Generation ------------------------------------------------------------


func _build_crystal() -> void:
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = DrillKnobs.CRYSTAL_RADIUS
	crystal_mesh.height = DrillKnobs.CRYSTAL_RADIUS * 2.0
	# Coarse on purpose: at these counts a sphere comes out as a rough gem with
	# flat faces to catch the lamp, which is what a crystal wants and a smooth
	# ball is not.
	crystal_mesh.radial_segments = 7
	crystal_mesh.rings = 4

	_crystal_mesh = MeshInstance3D.new()
	_crystal_mesh.mesh = crystal_mesh
	_crystal_mesh.material_override = CRYSTAL_MATERIAL

	var shape := SphereShape3D.new()
	shape.radius = DrillKnobs.CRYSTAL_RADIUS
	_crystal_collider = CollisionShape3D.new()
	_crystal_collider.shape = shape

	_crystal = RigidBody3D.new()
	_crystal.name = "Crystal"
	_crystal.gravity_scale = 0.0
	_crystal.mass = DrillKnobs.CRYSTAL_MASS
	# Frozen rather than a StaticBody3D that gets swapped out later: the release
	# is then three property writes on a body that has been there all along.
	_crystal.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_crystal.freeze = true
	_crystal.can_sleep = false
	_crystal.collision_layer = DrillKnobs.ORE_LAYER
	_crystal.collision_mask = 0
	_crystal.add_child(_crystal_mesh)
	_crystal.add_child(_crystal_collider)
	add_child(_crystal)


## One static body for all the rock, carrying one collision shape per sub-chunk.
## Splitting the shapes is what lets a carve rebuild the part that changed
## instead of the whole node.
func _build_rock_body() -> void:
	_rock_body = StaticBody3D.new()
	_rock_body.name = "Rock"
	_rock_body.collision_layer = DrillKnobs.ORE_LAYER
	_rock_body.collision_mask = 0
	add_child(_rock_body)


func _build_escape_directions() -> void:
	_escape_directions.resize(DrillKnobs.ESCAPE_PROBE_COUNT)
	for index in DrillKnobs.ESCAPE_PROBE_COUNT:
		var height := 1.0 - 2.0 * (float(index) + 0.5) / float(DrillKnobs.ESCAPE_PROBE_COUNT)
		var ring_radius := sqrt(maxf(0.0, 1.0 - height * height))
		var angle := float(index) * GOLDEN_ANGLE
		_escape_directions[index] = Vector3(
			cos(angle) * ring_radius, height, sin(angle) * ring_radius
		)


# --- Remeshing -------------------------------------------------------------


## Rebuilds up to `limit` dirty sub-chunks. Everything the budget does not reach
## stays queued and is picked up next frame.
func _flush_remesh(limit: int) -> void:
	for subchunk: Vector3i in _field.take_dirty(limit):
		_rebuild_subchunk(subchunk)


func _rebuild_subchunk(subchunk: Vector3i) -> void:
	var normals := PackedVector3Array()
	var triangles := _mesher.build(_field, subchunk, normals)

	var mesh_instance: MeshInstance3D = _meshes.get(subchunk)
	var collider: CollisionShape3D = _shapes.get(subchunk)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Rock%d_%d_%d" % [subchunk.x, subchunk.y, subchunk.z]
		mesh_instance.material_override = ROCK_MATERIAL
		add_child(mesh_instance)
		_meshes[subchunk] = mesh_instance

		collider = CollisionShape3D.new()
		collider.shape = ConcavePolygonShape3D.new()
		_rock_body.add_child(collider)
		_shapes[subchunk] = collider

	if triangles.is_empty():
		mesh_instance.mesh = null
		# A shape with no faces is how a sub-chunk stops colliding. Disabling the
		# node instead defers to the next physics step; emptying it does not.
		(collider.shape as ConcavePolygonShape3D).set_faces(PackedVector3Array())
		return

	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = triangles
	surface[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	mesh_instance.mesh = mesh
	# The same array serves both, which is the other reason the mesher emits
	# unshared vertices: a faceted surface is already a triangle soup.
	(collider.shape as ConcavePolygonShape3D).set_faces(triangles)


# --- Getting the crystal out -----------------------------------------------


## Walks every escape direction once, records the widest tube any of them offers,
## and frees the crystal if that is wide enough.
##
## One pass answers both questions because the field's own value is the clearance
## - the narrowest sample along a probe IS how wide a tube fits down it - so
## there is nothing to search for and the readout costs the same as the test.
func _measure_escape() -> void:
	var reach := _field.half_extent() + DrillKnobs.VOXEL_SIZE
	var start_distance := DrillKnobs.CRYSTAL_RADIUS + DrillKnobs.VOXEL_SIZE
	var widest := 0.0
	var best_direction := Vector3.UP
	for direction: Vector3 in _escape_directions:
		var narrowest := _field.narrowest_along(
			direction * start_distance, direction, reach - start_distance
		)
		if narrowest > widest:
			widest = narrowest
			best_direction = direction
	_widest_opening = widest
	if (
		_release_authority
		and _crystal_state == CrystalState.EMBEDDED
		and widest >= _escape_clearance
	):
		_free_crystal(best_direction)


func _free_crystal(escape_direction: Vector3) -> void:
	_set_crystal_state(CrystalState.FREE)
	# The layer change is the state change: the suit's collector masks
	# CRYSTAL_LAYER and not ORE_LAYER, so nothing has to remember to switch a
	# pickup on. The mask drops to the hull alone so a crystal cannot wedge in
	# the rock it was just cut out of, which would read as the release rule being
	# broken.
	crystal_freed.emit(self)
	_crystal.apply_impulse(escape_direction.normalized() * DrillKnobs.CRYSTAL_FREE_IMPULSE)
	_crystal.angular_velocity = Vector3(0.4, 1.0, -0.3).normalized() * DrillKnobs.CRYSTAL_FREE_SPIN


func _set_crystal_state(state: CrystalState) -> void:
	_crystal_state = state
	_crystal_mesh.visible = state != CrystalState.COLLECTED
	_crystal_collider.disabled = state == CrystalState.COLLECTED

	match state:
		CrystalState.EMBEDDED:
			_crystal.collision_layer = DrillKnobs.ORE_LAYER
			_crystal.collision_mask = 0
			_crystal.freeze = true
		CrystalState.FREE:
			_crystal.collision_layer = DrillKnobs.CRYSTAL_LAYER
			_crystal.collision_mask = DrillKnobs.HULL_LAYER
			_crystal.freeze = not _release_authority
		CrystalState.COLLECTED:
			_crystal.collision_layer = 0
			_crystal.collision_mask = 0
			_crystal.freeze = true
			_crystal.linear_velocity = Vector3.ZERO
			_crystal.angular_velocity = Vector3.ZERO


## Where a ray meets the crystal's sphere, or -1. Analytic rather than a physics
## query, so it is answered in the same local space and on the same frame as the
## field walk it is being compared against.
## Which way the hit surface faces, in world space. Zero where there is no
## answer, which the caller has to expect - see VoxelField.sample_normal.
##
## The crystal is a sphere on the node's own origin, so its normal is the hit
## point itself; rock defers to the field's gradient.
func _surface_normal(local_point: Vector3, on_crystal: bool) -> Vector3:
	var local_normal := (
		local_point.normalized() if on_crystal else _field.sample_normal(local_point)
	)
	if local_normal.is_zero_approx():
		return Vector3.ZERO
	return (global_transform.basis * local_normal).normalized()


func _crystal_hit(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if _crystal == null or _crystal_state != CrystalState.EMBEDDED:
		return -1.0
	var to_centre := -origin
	var along := to_centre.dot(direction)
	var gap_squared := to_centre.length_squared() - along * along
	var radius_squared := DrillKnobs.CRYSTAL_RADIUS * DrillKnobs.CRYSTAL_RADIUS
	if gap_squared > radius_squared:
		return -1.0
	var half_chord := sqrt(radius_squared - gap_squared)
	var near := along - half_chord
	if near < 0.0:
		near = along + half_chord
	if near < 0.0 or near > max_distance:
		return -1.0
	return near
