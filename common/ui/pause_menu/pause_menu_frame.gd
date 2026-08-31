@tool
class_name PauseMenuFrame
extends HudWidget

## Rounded-rectangle chrome frame for the pause menu, with HUD corner screws.
## The outline traces the live rect rather than design space, so it pins to its
## anchors at any aspect ratio.

const DESIGN := Vector2(1836.0, 1024.0)
const STROKE := 5.0
const CORNER := 20.0
const CORNER_STEPS := 4


func design_extent() -> Vector2:
	return DESIGN


func _draw() -> void:
	var outline := _rounded_outline()
	outline.append(outline[0])
	draw_polyline(outline, HudPalette.CHROME, scaled(STROKE), true)
	_draw_screws()


## Quadratic bevel through each corner.
func _rounded_outline() -> PackedVector2Array:
	var corners := PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	)
	var radius := scaled(CORNER)
	var points := PackedVector2Array()
	var count := corners.size()
	for index in count:
		var corner := corners[index]
		var previous := corners[(index + count - 1) % count]
		var following := corners[(index + 1) % count]
		var start := corner + (previous - corner).normalized() * radius
		var end := corner + (following - corner).normalized() * radius
		for step in CORNER_STEPS + 1:
			var along := float(step) / float(CORNER_STEPS)
			points.append(start.lerp(corner, along).lerp(corner.lerp(end, along), along))
	return points


func _draw_screws() -> void:
	var inset := scaled(HudArt.SCREW_INSET)
	var extent := Vector2(HudArt.SCREW.get_size()) * scale_factor()
	for corner in 4:
		var x := inset if corner % 2 == 0 else size.x - inset
		var y := inset if corner < 2 else size.y - inset
		draw_texture_rect(HudArt.SCREW, Rect2(Vector2(x, y) - extent * 0.5, extent), false)
