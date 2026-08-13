class_name DrillBeam
extends Node3D

## The laser drill: one ray walked through the rock, one cylinder drawn along it,
## and the rule that rock gives and crystal does not.
##
## Lives under the suit's HeadCamera, so its own local space is camera space and
## the ray needs no transform of its own. It runs in _physics_process, after the
## suit has already moved and turned this frame, so what it reports is where the
## crosshair actually is rather than where it was last frame.
##
## NO PHYSICS RAYCAST. Each node is asked to walk its own voxel field - see
## OreNode.cast. The collision shapes lag the field by a frame or two because
## remeshing runs on a budget, so a query against them would carve at a surface
## that is already stale. There is also nothing to broad-phase: there are four
## nodes.

const BEAM_MATERIAL := preload("res://prototypes/drill_and_mining/materials/beam_material.tres")

## What there is to drill, and where the spray goes. Both assigned by the
## prototype root, and re-assigned whenever it rebuilds the field.
var ore_nodes: Array[OreNode] = []
var debris_pool: OreDebrisPool

## Beam and impact geometry are built once and re-posed, never rebuilt.
var _beam_mesh: MeshInstance3D
var _impact_mesh: MeshInstance3D

var _carve_rate := DrillKnobs.CARVE_RATE
var _carve_radius := DrillKnobs.CARVE_RADIUS
var _range := DrillKnobs.DRILL_RANGE
var _debris_rate := DrillKnobs.DEBRIS_SPAWN_RATE

## The Poisson process behind the spray, in seconds: how long the current gap was
## drawn for, and how much of it is left. Negative remaining means no gap is
## running and the next cut draws one.
##
## Carried between frames, so the rate is never quantised to whatever the frame
## time happens to be. The DRAWN length is kept because it is not just a timer -
## it is the fragment: see _heft_of.
var _wait_drawn := 0.0
var _wait_remaining := -1.0

var _is_firing := false
var _target_node: OreNode
var _is_on_crystal := false


func _ready() -> void:
	position = Vector3.ZERO
	_build_beam()
	_build_impact()
	_stow()


func _physics_process(delta: float) -> void:
	# ESC frees the mouse, which is also the only way to reach the tuning panel.
	# Gating on the capture state means the drill is dead exactly while the panel
	# is clickable, so a click on a slider cannot also cut a hole in something.
	_is_firing = (
		Input.is_action_pressed(DrillKnobs.DRILL_ACTION)
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	if not _is_firing:
		_stow()
		return
	_fire(delta)


## Pushes the tuned numbers on. Called by the prototype root, at startup and
## again on every panel change.
func apply_tuning(
	carve_rate: float, carve_radius: float, beam_range: float, debris_rate: float
) -> void:
	_carve_rate = carve_rate
	_carve_radius = carve_radius
	_range = beam_range
	_debris_rate = debris_rate


## Whether the trigger is down and the mouse is captured. Read by the HUD.
func is_firing() -> bool:
	return _is_firing


## The node under the crosshair, or null.
func get_target_node() -> OreNode:
	return _target_node


## Whether what is under the crosshair is the crystal rather than rock.
func is_on_crystal() -> bool:
	return _is_on_crystal


func _fire(delta: float) -> void:
	var origin := global_position
	var aim := -global_transform.basis.z.normalized()

	var nearest := {}
	var nearest_node: OreNode = null
	for ore_node: OreNode in ore_nodes:
		if not is_instance_valid(ore_node):
			continue
		var hit := ore_node.cast(origin, aim, _range)
		if hit.is_empty():
			continue
		if nearest.is_empty() or hit["distance"] < nearest["distance"]:
			nearest = hit
			nearest_node = ore_node

	_target_node = null
	_is_on_crystal = false

	if nearest.is_empty():
		_hold_spray()
		_show_beam(origin + aim * _range, false)
		return

	var hit_point: Vector3 = nearest["position"]
	if nearest["is_crystal"]:
		# The whole of "indestructible": the beam stops on it, sparks, and takes
		# nothing off. Being refused by the thing you are digging for is worth
		# more than the beam sliding through it as though it were not there.
		_is_on_crystal = true
		_hold_spray()
		_show_beam(hit_point, true)
		return

	_target_node = nearest_node
	if nearest_node.carve(hit_point, _carve_radius, _carve_rate * delta):
		_throw_debris(hit_point, aim, nearest["normal"], delta)
	_show_beam(hit_point, true)


## Fragments come off at a rate rather than one per unit of rock removed.
##
## That split is the point of the whole rewrite: how fast the hole deepens and
## how violently the room fills up are now two numbers, where the eighty-chunk
## shell had them as one.
##
## The frame's time is SPENT DOWN rather than stepped once, so a rate high enough
## to owe several fragments in one frame gets them, and each carries its own gap.
func _throw_debris(hit_point: Vector3, aim: Vector3, surface_normal: Vector3, delta: float) -> void:
	if not DrillKnobs.DEBRIS_ENABLED or debris_pool == null or _debris_rate <= 0.0:
		return
	if _wait_remaining < 0.0:
		_draw_wait()
	# Once for the frame. Every fragment leaves along the same reflection and the
	# pool scatters each one inside DEBRIS_SPREAD_DEGREES of it.
	var thrown := _spray_direction(aim, surface_normal)
	var unspent := delta
	while unspent >= _wait_remaining:
		unspent -= _wait_remaining
		debris_pool.launch(hit_point, thrown, _heft_of(_wait_drawn))
		_draw_wait()
	_wait_remaining -= unspent


## Draws the gap to the next fragment from an exponential distribution, which is
## what makes arrivals a Poisson process rather than a metronome.
##
## `1.0 - randf()` rather than `randf()`, because randf() can return exactly zero
## and log(0) is negative infinity. The flip lands in (0, 1] instead, so the
## worst case is a gap of zero and never a gap of forever.
func _draw_wait() -> void:
	_wait_drawn = -log(1.0 - randf()) / _debris_rate
	_wait_remaining = _wait_drawn


## What one gap earned, 0 to 1. The pool turns it into size, mass and lifetime.
##
## MEASURED IN MEAN GAPS, so it means the same thing at any rate: a fragment is
## big because the drill hung on to it for longer than usual, not because the
## rate happens to be low. Exponential gaps put about 5% of fragments at the
## ceiling, which is what makes a slab an event rather than the texture.
func _heft_of(wait: float) -> float:
	return clampf(wait * _debris_rate / DrillKnobs.DEBRIS_HEFT_WAITS, 0.0, 1.0)


## Abandons the gap in progress, for whenever the beam is not cutting rock.
##
## The process is memoryless, so keeping the part-served gap would be defensible
## statistically and wrong in play: letting go of the trigger and pulling it again
## would bank the pause and hand you a slab for it.
func _hold_spray() -> void:
	_wait_remaining = -1.0


## Which way rock leaves the hole: the beam, mirrored in the face it landed on.
##
## The normal is the field's own gradient rather than anything read off the mesh,
## so the spray answers to the rock as it is this frame. Straight into a deep
## bore the face points back down the barrel and the spray comes back at you; a
## wall taken at a glance sheets it off sideways, the way a grinder throws. Those
## are the same thing, which is why there is no switch between them.
##
## Back along the beam where the field has no gradient to give - a spot the
## erosion has already flattened. That is the degenerate case of the reflection
## and not a different rule.
func _spray_direction(aim: Vector3, surface_normal: Vector3) -> Vector3:
	if surface_normal.is_zero_approx():
		return -aim
	return aim.bounce(surface_normal)


## Re-poses the cylinder to span muzzle to hit point, and parks the impact dot.
##
## The cylinder is built along +Y with height 1, so the basis does all the work:
## its Y column becomes the beam vector, and the other two carry the radius.
func _show_beam(hit_point: Vector3, has_hit: bool) -> void:
	var muzzle := DrillKnobs.MUZZLE_OFFSET
	var to_hit := to_local(hit_point) - muzzle
	var length := to_hit.length()
	if length < 0.001:
		_stow()
		return

	var along := to_hit / length
	var side := along.cross(Vector3.UP)
	if side.is_zero_approx():
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var radius := DrillKnobs.BEAM_RADIUS * (1.0 + randf_range(-1.0, 1.0) * DrillKnobs.BEAM_JITTER)

	_beam_mesh.transform = Transform3D(
		Basis(side * radius, along * length, along.cross(side) * radius), muzzle + to_hit * 0.5
	)
	_beam_mesh.visible = true

	_impact_mesh.visible = has_hit
	if has_hit:
		_impact_mesh.position = to_local(hit_point)
		_impact_mesh.scale = Vector3.ONE * randf_range(0.7, 1.3)


func _stow() -> void:
	_beam_mesh.visible = false
	_impact_mesh.visible = false
	_target_node = null
	_is_on_crystal = false
	_hold_spray()


func _build_beam() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	# Six sides, no caps. A billboarded quad would turn edge-on and vanish the
	# moment you drill straight down the barrel, which is exactly when you are
	# looking at it hardest; a prism never does.
	cylinder.radial_segments = 6
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false

	_beam_mesh = MeshInstance3D.new()
	_beam_mesh.name = "Beam"
	_beam_mesh.mesh = cylinder
	_beam_mesh.material_override = BEAM_MATERIAL
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam_mesh)


func _build_impact() -> void:
	var spark := SphereMesh.new()
	spark.radius = DrillKnobs.IMPACT_DOT_RADIUS
	spark.height = DrillKnobs.IMPACT_DOT_RADIUS * 2.0
	spark.radial_segments = 6
	spark.rings = 3

	_impact_mesh = MeshInstance3D.new()
	_impact_mesh.name = "Impact"
	_impact_mesh.mesh = spark
	_impact_mesh.material_override = BEAM_MATERIAL
	_impact_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impact_mesh)
