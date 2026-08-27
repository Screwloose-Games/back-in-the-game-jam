@tool
class_name ArcHazard
extends Node3D

## A burst life-support cube's cable, still live. Electricity arcs between two anchors;
## stand anywhere near the line between them and the arc holds, draining the charge you
## have been carefully managing for reasons that are not your fault. With nobody there
## it simply arcs now and then, which is what makes it read as scenery until it isn't.

## A fixed seed while the editor is previewing, so the bolt does not shimmer while a
## designer is trying to place the anchors.
const EDITOR_PREVIEW_SEED := 20260824

@export_group("Arc")

## The two ends. They default to this prefab's own markers, so it works dropped into a
## level -- and a designer can still point one at a wreck outside the prefab.
@export var anchor_a: Node3D
@export var anchor_b: Node3D

## Seconds between idle bursts, and how much that varies either way.
@export_range(0.2, 20.0, 0.1, "suffix:s") var idle_interval_s: float = 1.5
@export_range(0.0, 10.0, 0.1, "suffix:s") var idle_interval_jitter_s: float = 0.8

## How long one burst lasts. Also how long the bolt keeps going after you leave.
@export_range(0.05, 2.0, 0.05, "suffix:s") var arc_duration_s: float = 0.5

## Segments in the bolt, and how far each one wanders off the straight line.
@export_range(2, 24, 1) var segments: int = 10
@export_range(0.0, 1.0, 0.01, "suffix:m") var jaggedness: float = 0.18

@export var arc_color := Color(0.62, 0.82, 1.0)
@export_range(0.0, 16.0, 0.1) var light_energy: float = 2.5

@export_group("Field")

## How far off the line between the anchors the arc still reaches you.
@export_range(0.2, 12.0, 0.1, "suffix:m") var field_radius: float = 3.0

## This placement's share of the two figures on PlayerSettings, so one cable can be
## nastier than another without a second copy of either number to drift.
@export_range(0.0, 4.0, 0.05) var damage_scale: float = 1.0
@export_range(0.0, 4.0, 0.05) var drain_scale: float = 1.0

var _mesh := ImmediateMesh.new()
var _rng := RandomNumberGenerator.new()
var _next_burst := 0.0
var _burst_left := 0.0

@onready var _arc: MeshInstance3D = $Arc
@onready var _light: OmniLight3D = $ArcLight
@onready var _sfx: AudioStreamPlayer3D = $Sfx


func _ready() -> void:
	if anchor_a == null:
		anchor_a = $AnchorA
	if anchor_b == null:
		anchor_b = $AnchorB
	_arc.mesh = _mesh
	_light.light_color = arc_color
	_next_burst = _draw_interval()
	_go_dark()


func _process(delta: float) -> void:
	if anchor_a == null or anchor_b == null:
		return
	if Engine.is_editor_hint():
		_rng.seed = EDITOR_PREVIEW_SEED
		_build_bolt()
		_light.light_energy = light_energy
		return
	var inside := _occupants()
	if inside.is_empty():
		_run_intermittent(delta)
		return
	_run_continuous(delta, inside)


## Everyone close enough to the line between the anchors, with their share of it.
##
## Geometry rather than an Area3D: the field is a capsule around an arbitrary segment,
## which an Area3D cannot be without rebuilding its shape every time a marker moves.
func _occupants() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var from := anchor_a.global_position
	var to := anchor_b.global_position
	for body: Node3D in HazardDamage.players(get_tree()):
		var nearest := Geometry3D.get_closest_point_to_segment(body.global_position, from, to)
		var share := HazardDamage.falloff(body.global_position.distance_to(nearest), field_radius)
		if share > 0.0:
			found.append({"body": body, "share": share})
	return found


## The arc holds for as long as anyone is in it, and bills them every frame it does.
func _run_continuous(delta: float, inside: Array[Dictionary]) -> void:
	_burst_left = arc_duration_s
	_next_burst = _draw_interval()
	_build_bolt()
	_light.light_energy = light_energy
	_play()
	for entry: Dictionary in inside:
		var body: Node3D = entry["body"]
		var share: float = entry["share"]
		var health := HazardDamage.health_of(body)
		if health == null:
			continue
		# The damage here is small on purpose -- the charge is the bill -- so the suit
		# is told it is being held rather than left to infer it from a number nobody
		# can see moving.
		health.electrify()
		var power := HazardDamage.power_of(body)
		if power != null:
			power.spend(
				health.settings.hazard_arc_power_drain_per_second * drain_scale * share * delta
			)
		health.take_damage(
			health.settings.hazard_arc_damage_per_second * damage_scale * share * delta,
			PlayerHealth.Source.ARC
		)


## Nobody near it: one burst every idle_interval_s or so, costing nothing.
func _run_intermittent(delta: float) -> void:
	if _burst_left > 0.0:
		_burst_left -= delta
		_build_bolt()
		if _burst_left <= 0.0:
			_go_dark()
		return
	_next_burst -= delta
	if _next_burst > 0.0:
		return
	_burst_left = arc_duration_s
	_next_burst = _draw_interval()
	_light.light_energy = light_energy
	_play()


## Rebuilt every frame it is visible, because a bolt that holds still is a wire.
func _build_bolt() -> void:
	var from := to_local(anchor_a.global_position)
	var to := to_local(anchor_b.global_position)
	var axis := to - from
	_mesh.clear_surfaces()
	if axis.length_squared() <= 0.0:
		return
	var heading := axis.normalized()
	var side := heading.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = heading.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := heading.cross(side).normalized()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in segments + 1:
		var wander := Vector3.ZERO
		# The ends stay welded to their anchors; only the middle wanders.
		if i > 0 and i < segments:
			wander = (
				side * _rng.randf_range(-jaggedness, jaggedness)
				+ up * _rng.randf_range(-jaggedness, jaggedness)
			)
		_mesh.surface_set_color(arc_color)
		_mesh.surface_add_vertex(from.lerp(to, float(i) / float(segments)) + wander)
	_mesh.surface_end()
	var midpoint := from.lerp(to, 0.5)
	_light.position = midpoint
	_sfx.position = midpoint


func _go_dark() -> void:
	_mesh.clear_surfaces()
	_light.light_energy = 0.0
	if _sfx.playing:
		_sfx.stop()


func _play() -> void:
	if _sfx.stream != null and not _sfx.playing:
		_sfx.play(0.0)


func _draw_interval() -> float:
	var jitter := _rng.randf_range(-idle_interval_jitter_s, idle_interval_jitter_s)
	return maxf(idle_interval_s + jitter, 0.1)
