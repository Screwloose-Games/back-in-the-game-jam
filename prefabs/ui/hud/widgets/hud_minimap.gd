@tool
class_name HudMinimap
extends HudWidget

## The radar dish: Figma's MINIMAP, its four ring layers pinging outward, and the
## contacts projected onto them - every ring grows from the shared centre,
## brightens, and vanishes at full size.

## Where each ring starts, as a fraction of one ring's ramp, inner to outer. The
## gaps are uneven - four separate start times, not one spacing, so leave them be.
const SONAR_DELAY_FRACTIONS: PackedFloat32Array = [0.0, 0.0948, 0.201335, 0.297055]

## A whole ping outlasts one ring's ramp by however long the last ring waits.
const SONAR_SPAN := 1.297055

## Alpha at the top of the pulse, and where in a ring's own life that peak lands.
## All four rings peak at the same 0.8, which is why one curve drives every one.
const SONAR_PEAK_ALPHA := 0.935
const SONAR_PEAK_AT := 0.8

## Control points of the one curve every ring eases on, which is not a shape
## Godot's TRANS_* set contains.
const SONAR_EASE_X1 := 0.336
const SONAR_EASE_X2 := 0.753

@export var radar_blips := PackedVector3Array():
	set(value):
		radar_blips = value
		queue_redraw()

@export var max_distance := 30.0:
	set(value):
		max_distance = maxf(value, 0.0)
		queue_redraw()

@export var height_extent := HudArt.MINIMAP_HEIGHT_EXTENT:
	set(value):
		height_extent = value
		queue_redraw()

@export var show_height_stalks := true:
	set(value):
		show_height_stalks = value
		queue_redraw()

## Stopwatch length of one ping: first ring appearing to last ring gone.
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:s") var sonar_duration := 1.6911:
	set(value):
		sonar_duration = maxf(value, 0.01)
		queue_redraw()

@export_tool_button("Ping") var ping_action := ping

var _objective_shown := false
var _objective_at := Vector2.ZERO
var _elapsed := 0.0
var _pinging := false


static func in_range(offset: Vector3, distance_limit: float) -> bool:
	if distance_limit <= 0.0:
		return false
	return offset.length_squared() <= distance_limit * distance_limit


static func project(offset: Vector3, distance_limit: float, lift: float) -> Vector2:
	if distance_limit <= 0.0:
		return HudArt.MINIMAP_RINGS_CENTRE
	var norm := offset / distance_limit
	var dish := HudArt.MINIMAP_RINGS_CENTRE + Vector2(norm.x, norm.z) * HudArt.MINIMAP_RINGS_EXTENT
	return dish - Vector2(0.0, norm.y * lift)


## Where a ring sits in its own life: below 0 not started yet, above 1 finished.
static func ring_phase(elapsed: float, ring: int, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return elapsed * SONAR_SPAN / duration - SONAR_DELAY_FRACTIONS[ring]


## Nothing at the centre, full size at the end of the ping.
static func ring_scale(phase: float) -> float:
	return sonar_ease(phase)


## Up to the peak, then back out - the ring vanishes at full size, not at the rim.
static func ring_alpha(phase: float) -> float:
	if phase < SONAR_PEAK_AT:
		return SONAR_PEAK_ALPHA * sonar_ease(phase / SONAR_PEAK_AT)
	var fall := (phase - SONAR_PEAK_AT) / (1.0 - SONAR_PEAK_AT)
	return SONAR_PEAK_ALPHA * (1.0 - sonar_ease(fall))


static func sonar_ease(x: float) -> float:
	return HudEase.cubic(x, SONAR_EASE_X1, SONAR_EASE_X2)


func _ready() -> void:
	super()
	set_process(false)


## Runs one ping from the start, whatever the last one was doing.
func ping() -> void:
	_elapsed = 0.0
	_pinging = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= sonar_duration:
		_pinging = false
		set_process(false)
	queue_redraw()


func design_extent() -> Vector2:
	return HudArt.MINIMAP_SIZE


func _draw() -> void:
	draw_design_texture(HudArt.MINIMAP_BACKGROUND, HudArt.MINIMAP_BACKGROUND_CENTRE)
	if _pinging:
		_draw_ring(HudArt.MINIMAP_LINES04, HudArt.MINIMAP_LINES04_CENTRE, 3)
		_draw_ring(HudArt.MINIMAP_LINES03, HudArt.MINIMAP_LINES03_CENTRE, 2)
		_draw_ring(HudArt.MINIMAP_LINES02, HudArt.MINIMAP_LINES02_CENTRE, 1)
		_draw_ring(HudArt.MINIMAP_LINES01, HudArt.MINIMAP_LINES01_CENTRE, 0)
	draw_design_texture(HudArt.MINIMAP_REFLECTION, HudArt.MINIMAP_REFLECTION_CENTRE)

	for offset in _visible_blips():
		_draw_blip(offset)
	if _objective_shown:
		_draw_objective()


func bind(state: HudState) -> void:
	state.contacts_changed.connect(show_contacts)
	state.objective_changed.connect(show_objective)


func show_contacts(contacts: PackedVector3Array) -> void:
	radar_blips = contacts


func show_objective(shown: bool, at: Vector2) -> void:
	_objective_shown = shown
	_objective_at = at
	queue_redraw()


func _visible_blips() -> Array[Vector3]:
	var shown: Array[Vector3] = []
	for offset in radar_blips:
		if in_range(offset, max_distance):
			shown.append(offset)
	shown.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	return shown


func _draw_ring(texture: Texture2D, centre: Vector2, ring: int) -> void:
	var phase := ring_phase(_elapsed, ring, sonar_duration)
	if phase <= 0.0 or phase >= 1.0:
		return
	var alpha := ring_alpha(phase)
	if alpha <= 0.0:
		return
	draw_design_texture_scaled(texture, centre, ring_scale(phase), Color(1.0, 1.0, 1.0, alpha))


func _draw_blip(offset: Vector3) -> void:
	var at := project(offset, max_distance, height_extent)
	if show_height_stalks:
		var foot := project(Vector3(offset.x, 0.0, offset.z), max_distance, height_extent)
		if not at.is_equal_approx(foot):
			draw_line(scaled_vec(foot), scaled_vec(at), HudPalette.CHROME_DIM, scaled(2.0))
	draw_design_texture(HudArt.ENEMY_DOT, at)


func _draw_objective() -> void:
	var extent := Vector2(HudArt.ENEMY_DOT.get_size()) * scale_factor()
	var centre := scaled_vec(_place_disc(_objective_at))
	draw_rect(Rect2(centre - extent * 0.5, extent), HudPalette.OBJECTIVE)


func _place_disc(offset: Vector2) -> Vector2:
	var clamped := offset if offset.length() <= 1.0 else offset.normalized()
	return HudArt.MINIMAP_RINGS_CENTRE + clamped * HudArt.MINIMAP_RINGS_EXTENT
