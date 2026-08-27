class_name PlayerRadarDetector
extends Area3D

## The suit's radar: a sphere grown from the player at `radar_pulse_speed` until it
## reaches `radar_range`, reporting whatever its surface crosses on the way out. The
## pulse is literal rather than a distance test, so a contact is announced at the
## moment the wavefront actually arrives -- which is what lets the HUD's expanding
## rings and the blip agree with each other.

## Fired as a pulse leaves, carrying everything the dish needs to draw it.
signal pulse_started(range_m: float, sweep_seconds: float, interval: float)

## One contact, once per pulse, at the moment the wavefront reached it.
signal detected_detectable(detectable: RadarDetectable)

## The collapsed radius between pulses. Never exactly zero: a degenerate shape is a
## broadphase special case nobody needs, and 0.05 m is inside the 0.4 m hull anyway.
const SEED_RADIUS := 0.05

@export var settings: PlayerSettings

var _elapsed := 0.0
var _radius := SEED_RADIUS
var _sweeping := false
var _reported := {}
var _sphere: SphereShape3D

@onready var body: CharacterBody3D = get_parent()
@onready var power: PlayerPowerClient = %PowerClient
@onready var visibility: PlayerVisibility = %Visibility


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerRadarDetector has no settings; running on PlayerSettings defaults.")
	# An 80 m sphere on a copy nobody is looking through, feeding a HUD PlayerUi has
	# already freed. The same gate PlayerSfx puts on the helmet cues.
	if not visibility.is_local_player:
		monitoring = false
		set_physics_process(false)
		return
	# Masked to detectables alone. A pulse this size that also masked the hull would
	# test against every wall in the asteroid, every step, for nothing.
	collision_layer = 0
	collision_mask = settings.radar_detectable_layers
	monitorable = false
	monitoring = true
	_build_pulse()
	area_entered.connect(_on_area_entered)
	_start_pulse()


## Physics rather than idle: overlaps are recomputed once per physics step, so growing
## at render rate issues writes that are thrown away and makes the sweep frame-dependent.
func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _sweeping:
		_advance_sweep(delta)
		return
	if _elapsed >= settings.radar_interval:
		_start_pulse()


## A contact in the player's own frame -- the FULL basis, so something ahead of you
## reads as ahead whichever way the suit happens to be pointed.
func local_offset(world_point: Vector3) -> Vector3:
	return RadarPulse.local_offset(body.global_transform, world_point)


func is_sweeping() -> bool:
	return _sweeping


## Built rather than authored: a SphereShape3D saved in a .tscn is ONE resource shared
## by every instance of that scene, so two players would grow the same sphere.
func _build_pulse() -> void:
	_sphere = SphereShape3D.new()
	_sphere.radius = SEED_RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = _sphere
	add_child(collider)


func _start_pulse() -> void:
	_elapsed = 0.0
	_reported.clear()
	# A dead suit gets no sweep. The tick, the rings and the blips are all the radar
	# saying it is on, so it must not do any of them for free -- the same shape as
	# PlayerLamp, where the switch stays on and the beam simply does not light.
	if not power.has_power():
		return
	# The return is ignored on purpose: gating on has_power() and then taking whatever
	# is left buys the last pulse out of a nearly empty suit, which is the generosity
	# the lamp and the laser already show.
	power.spend(settings.radar_power_per_pulse)
	_radius = SEED_RADIUS
	_sphere.radius = _radius
	_sweeping = true
	pulse_started.emit(
		settings.radar_range,
		RadarPulse.sweep_seconds(settings.radar_range, settings.radar_pulse_speed),
		settings.radar_interval
	)
	# Anything already inside the seed sphere never fires area_entered, because its
	# overlap began before this pulse did. A 2 m echo means that is anything within
	# arm's reach, which is the one contact the radar must not go quiet about.
	for area: Area3D in get_overlapping_areas():
		_on_area_entered(area)


func _advance_sweep(delta: float) -> void:
	# Held at full reach for the step AFTER it arrives, then collapsed. Overlaps are
	# reported from the previous step, so collapsing on the frame that clamps would
	# leave the outermost shell untested and a contact at exactly range never seen.
	if _radius >= settings.radar_range:
		_sweeping = false
		_radius = SEED_RADIUS
		_sphere.radius = _radius
		return
	_radius = minf(_radius + settings.radar_pulse_speed * delta, settings.radar_range)
	_sphere.radius = _radius


func _on_area_entered(area: Area3D) -> void:
	if not _sweeping:
		return
	var detectable := area as RadarDetectable
	if detectable == null:
		return
	# One report per contact per pulse. A player thrusting hard enough can leave the
	# growing sphere and re-enter it inside one sweep, and the radar must not paint the
	# same creature twice for it.
	var id := detectable.get_instance_id()
	if _reported.has(id):
		return
	_reported[id] = true
	detected_detectable.emit(detectable)
