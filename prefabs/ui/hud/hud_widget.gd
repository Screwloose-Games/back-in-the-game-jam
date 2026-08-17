@tool
class_name HudWidget
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bind(_state: HudState) -> void:
	pass


func design_extent() -> Vector2:
	return Vector2(100.0, 100.0)


func scale_factor() -> float:
	var extent := design_extent()
	if extent.x <= 0.0:
		return 1.0
	return size.x / extent.x


func scaled(value: float) -> float:
	return value * scale_factor()


func scaled_vec(value: Vector2) -> Vector2:
	return value * scale_factor()


func scaled_rect(rect: Rect2) -> Rect2:
	var factor := scale_factor()
	return Rect2(rect.position * factor, rect.size * factor)


## Stroke in design space, for art the widget draws rather than blits.
func draw_design_line(
	design_from: Vector2, design_to: Vector2, width: float, modulate := Color.WHITE
) -> void:
	if width <= 0.0:
		return
	draw_line(scaled_vec(design_from), scaled_vec(design_to), modulate, scaled(width), true)


## Closed stroke in design space, for outlines drawn rather than blitted.
func draw_design_outline(
	design_points: PackedVector2Array, width: float, modulate := Color.WHITE
) -> void:
	if width <= 0.0 or design_points.size() < 2:
		return
	var scaled_points := PackedVector2Array()
	for point in design_points:
		scaled_points.append(scaled_vec(point))
	scaled_points.append(scaled_points[0])
	draw_polyline(scaled_points, modulate, scaled(width), true)


func draw_design_texture(
	texture: Texture2D, design_centre: Vector2, modulate := Color.WHITE
) -> void:
	if texture == null:
		return
	var extent := Vector2(texture.get_size()) * scale_factor()
	var centre := scaled_vec(design_centre)
	draw_texture_rect(texture, Rect2(centre - extent * 0.5, extent), false, modulate)


## Blit scaled about the design centre, for art that grows out of a point.
func draw_design_texture_scaled(
	texture: Texture2D, design_centre: Vector2, factor: float, modulate := Color.WHITE
) -> void:
	if texture == null or factor <= 0.0:
		return
	var extent := Vector2(texture.get_size()) * scale_factor() * factor
	var centre := scaled_vec(design_centre)
	draw_texture_rect(texture, Rect2(centre - extent * 0.5, extent), false, modulate)


func draw_design_texture_reveal(
	texture: Texture2D, design_centre: Vector2, fraction: float, modulate := Color.WHITE
) -> void:
	if texture == null or fraction <= 0.0:
		return
	var source := Vector2(texture.get_size())
	var extent := source * scale_factor()
	var centre := scaled_vec(design_centre)
	var origin := centre - extent * 0.5
	var shown := clampf(fraction, 0.0, 1.0)
	draw_texture_rect_region(
		texture,
		Rect2(origin, Vector2(extent.x * shown, extent.y)),
		Rect2(Vector2.ZERO, Vector2(source.x * shown, source.y)),
		modulate
	)
