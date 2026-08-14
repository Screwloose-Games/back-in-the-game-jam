@tool
class_name HudBorder
extends HudWidget

const DESIGN := Vector2(1836.0, 1024.0)
const STROKE := 5.0
const CORNER := 14.0

@export var show_screws := true


func design_extent() -> Vector2:
	return DESIGN


func _draw() -> void:
	HudDraw.dot_frame(
		self, Rect2(Vector2.ZERO, size), HudMetrics.dots(STROKE), scaled(CORNER), HudPalette.CHROME
	)
	if not show_screws:
		return
	var inset := scaled(HudArt.SCREW_INSET)
	var extent := Vector2(HudArt.SCREW.get_size()) * scale_factor()
	for corner in 4:
		var x := inset if corner % 2 == 0 else size.x - inset
		var y := inset if corner < 2 else size.y - inset
		draw_texture_rect(HudArt.SCREW, Rect2(Vector2(x, y) - extent * 0.5, extent), false)
