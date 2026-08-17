@tool
class_name HudMinimap
extends HudWidget

## The radar dish: Figma's MINIMAP, its four ring layers pinging outward, and the
## contacts projected onto them - every ring grows from the shared centre,
## brightens, and vanishes at full size.

## Seconds for one ping, and the period the rings loop on. Measured, not chosen:
## do not round it to 1.3.
const SONAR_PERIOD := 1.3038

## Seconds each ring waits, indexed inner to outer. The gaps are 0.124, 0.139 and
## 0.125 - four separate start times, not one spacing, so do not even them out.
const SONAR_DELAYS: PackedFloat32Array = [0.0, 0.1236, 0.2625, 0.3873]

## Alpha at the top of the pulse, and where in a ring's own life that peak lands.
## All four rings peak at the same 0.8, which is why one curve drives every one.
const SONAR_PEAK_ALPHA := 0.935
const SONAR_PEAK_AT := 0.8

## Control points of the one curve every ring eases on, which is not a shape
## Godot's TRANS_* set contains.
const SONAR_EASE_X1 := 0.336
const SONAR_EASE_X2 := 0.753
const SONAR_EASE_STEPS := 4

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

## Off restores the four static rings this widget drew before the ping existed.
@export var sonar_enabled := true:
	set(value):
		sonar_enabled = value
		set_process(value)
		queue_redraw()

var _objective_shown := false
var _objective_at := Vector2.ZERO
var _elapsed := 0.0


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


## Where a ring sits in its own 0..1 life at this moment.
static func ring_phase(elapsed: float, ring: int) -> float:
	return fposmod((elapsed - SONAR_DELAYS[ring]) / SONAR_PERIOD, 1.0)


## Nothing at the centre, full size at the end of the ping.
static func ring_scale(phase: float) -> float:
	return sonar_ease(phase)


## Up to the peak, then back out - the ring vanishes at full size, not at the rim.
static func ring_alpha(phase: float) -> float:
	if phase < SONAR_PEAK_AT:
		return SONAR_PEAK_ALPHA * sonar_ease(phase / SONAR_PEAK_AT)
	var fall := (phase - SONAR_PEAK_AT) / (1.0 - SONAR_PEAK_AT)
	return SONAR_PEAK_ALPHA * (1.0 - sonar_ease(fall))


## Newton-solved for t given x; y(t) reduces to smoothstep because the outer
## control points are 0 and 1, so only the x mapping does anything.
static func sonar_ease(x: float) -> float:
	var target := clampf(x, 0.0, 1.0)
	if target <= 0.0 or target >= 1.0:
		return target
	var cx := 3.0 * SONAR_EASE_X1
	var bx := 3.0 * (SONAR_EASE_X2 - SONAR_EASE_X1) - cx
	var ax := 1.0 - cx - bx
	var t := target
	for _step in SONAR_EASE_STEPS:
		var slope := (3.0 * ax * t + 2.0 * bx) * t + cx
		if absf(slope) < 0.00001:
			break
		t -= (((ax * t + bx) * t + cx) * t - target) / slope
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _ready() -> void:
	super()
	set_process(sonar_enabled)


func _process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta, SONAR_PERIOD)
	queue_redraw()


func design_extent() -> Vector2:
	return HudArt.MINIMAP_SIZE


func _draw() -> void:
	draw_design_texture(HudArt.MINIMAP_BACKGROUND, HudArt.MINIMAP_BACKGROUND_CENTRE)
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
	if not sonar_enabled:
		draw_design_texture(texture, centre)
		return
	var phase := ring_phase(_elapsed, ring)
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
