@tool
class_name MainMenuFrame
extends HudWidget

## Same 1836x1024 and 5px stroke as HudBorder, so the title screen and the in-game
## chrome read as one frame at one size.
const DESIGN := Vector2(1836.0, 1024.0)
const STROKE := 5.0
const CORNER := 20.0
const CORNER_STEPS := 4

## Traced clockwise from the top of the left edge. The step at x 677 is the notch the
## title sits in, and is the one corner that turns inward.
const CORNERS: PackedVector2Array = [
	Vector2(0.0, 259.5),
	Vector2(677.0, 259.5),
	Vector2(677.0, 0.0),
	Vector2(1836.0, 0.0),
	Vector2(1836.0, 1024.0),
	Vector2(0.0, 1024.0)
]


func design_extent() -> Vector2:
	return DESIGN


func _draw() -> void:
	draw_design_outline(_rounded_outline(), STROKE, HudPalette.CHROME)


## Quadratic through each corner, which rounds the inward turn and the outward ones
## without either needing to know which it is.
func _rounded_outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := CORNERS.size()
	for index in count:
		var corner := CORNERS[index]
		var previous := CORNERS[(index + count - 1) % count]
		var following := CORNERS[(index + 1) % count]
		var start := corner + (previous - corner).normalized() * CORNER
		var end := corner + (following - corner).normalized() * CORNER
		for step in CORNER_STEPS + 1:
			var along := float(step) / float(CORNER_STEPS)
			points.append(start.lerp(corner, along).lerp(corner.lerp(end, along), along))
	return points
