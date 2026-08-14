class_name HudBorder
extends HudWidget

## Figma's BORDER, with a Screw_01 at each corner.
##
## The only component with no exported texture, for two reasons. Figma states it at
## 1836x1024 and the repo's art gate blocks any PNG over 1024 in either dimension -
## and even without that, a bitmap border would be the wrong thing: this is the one
## element that has to meet all four screen edges, and stretch/aspect="expand" hands
## the game a canvas wider than 1280x720 on anything that is not 16:9. So the frame
## is drawn from its own rect and the screws are stamped from art.
##
## Pure chrome - it binds to nothing.

## Figma: BORDER, 1836x1024 at (40, 27), 5px stroke, 14px radius.
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
