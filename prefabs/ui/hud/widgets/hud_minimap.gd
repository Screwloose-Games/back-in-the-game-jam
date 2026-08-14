@tool
class_name HudMinimap
extends HudWidget

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

var _objective_shown := false
var _objective_at := Vector2.ZERO


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


func design_extent() -> Vector2:
	return HudArt.MINIMAP_SIZE


func _draw() -> void:
	draw_design_texture(HudArt.MINIMAP_BACKGROUND, HudArt.MINIMAP_BACKGROUND_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES04, HudArt.MINIMAP_LINES04_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES03, HudArt.MINIMAP_LINES03_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES02, HudArt.MINIMAP_LINES02_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES01, HudArt.MINIMAP_LINES01_CENTRE)
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
