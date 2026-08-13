class_name MultiplayerDrillTool
extends Node3D

## Presentation-only drill beam used by the multiplayer player scene.
##
## The multiplayer world decides whether a ray hit and whether a carve is
## accepted. This node only poses disposable beam and impact meshes; it never
## references OreNode, the debris pool, or authoritative mining state.

const BEAM_MATERIAL := preload("res://prototypes/drill_and_mining/materials/beam_material.tres")
const REMOTE_PULSE_SECONDS := 0.12

var _beam_mesh: MeshInstance3D
var _impact_mesh: MeshInstance3D
var _preview_endpoint := Vector3.ZERO
var _preview_has_hit := false
var _preview_active := false
var _pulse_remaining := 0.0


func _ready() -> void:
	_build_beam()
	_build_impact()
	_stow()


func _process(delta: float) -> void:
	if _pulse_remaining <= 0.0:
		return
	_pulse_remaining = maxf(_pulse_remaining - delta, 0.0)
	if _pulse_remaining > 0.0:
		return
	if _preview_active:
		_pose_beam(_preview_endpoint, _preview_has_hit)
	else:
		_stow()


func show_preview(endpoint: Vector3, has_hit: bool, active: bool) -> void:
	if not endpoint.is_finite():
		active = false
	_preview_endpoint = endpoint
	_preview_has_hit = has_hit
	_preview_active = active
	if active:
		_pose_beam(endpoint, has_hit)
	elif _pulse_remaining <= 0.0:
		_stow()


func pulse(endpoint: Vector3) -> void:
	if not endpoint.is_finite():
		return
	_pulse_remaining = REMOTE_PULSE_SECONDS
	_pose_beam(endpoint, true)


func _pose_beam(endpoint: Vector3, has_hit: bool) -> void:
	if _beam_mesh == null or _impact_mesh == null:
		return
	var muzzle := DrillKnobs.MUZZLE_OFFSET
	var to_endpoint := to_local(endpoint) - muzzle
	var length := to_endpoint.length()
	if length < 0.001:
		_stow()
		return

	var along := to_endpoint / length
	var side := along.cross(Vector3.UP)
	if side.is_zero_approx():
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var radius := DrillKnobs.BEAM_RADIUS
	_beam_mesh.transform = Transform3D(
		Basis(side * radius, along * length, along.cross(side) * radius),
		muzzle + to_endpoint * 0.5,
	)
	_beam_mesh.visible = true

	_impact_mesh.visible = has_hit
	if has_hit:
		_impact_mesh.position = to_local(endpoint)
		_impact_mesh.scale = Vector3.ONE


func _stow() -> void:
	if _beam_mesh != null:
		_beam_mesh.visible = false
	if _impact_mesh != null:
		_impact_mesh.visible = false


func _build_beam() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
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
