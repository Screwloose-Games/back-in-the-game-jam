@tool
class_name HudReticleZoom
extends HudWidget

## Figma's RETICLE as HUD 04 draws it: two bars, two diagonals and a centre
## triangle that close in together. The parts move independently, so this one is
## stroked rather than blitted - see [HudReticle] for the mockups that are one image.

const DESIGN_SIZE := Vector2(505.0, 70.0)
const STROKE := 5.0

## Everything is mirrored about this line, so only the left half is spelled out.
const CENTRE_X := 252.5

const BAR_FROM := Vector2(0.0, 35.0)
const BAR_TO := Vector2(137.353, 35.0)

## Chosen to run at exactly 50 degrees, which is the angle the mockup names.
const DIAGONAL_FROM := Vector2(216.64, 2.5)
const DIAGONAL_TO := Vector2(162.1, 67.5)

const TRIANGLE: PackedVector2Array = [
	Vector2(252.5, 16.75), Vector2(279.66, 55.05), Vector2(225.34, 55.05)
]
const TRIANGLE_PIVOT := Vector2(252.5, 35.9)

## How far each pair travels inward, and how far the triangle shrinks, at zoom 0.
## The mockup moved one bar a pixel further than the other; that gap is averaged
## away here rather than carried, so the compressed pose stays symmetric.
const BAR_TRAVEL := 34.823
const DIAGONAL_TRAVEL := 25.0
const COMPRESSED_SCALE := 0.7

## Compressed at 0, at rest at 1.
@export_range(0.0, 1.0, 0.001) var zoom := 1.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(next, zoom):
			return
		zoom = next
		queue_redraw()


static func bar_offset(pose: float) -> float:
	return BAR_TRAVEL * (1.0 - pose)


static func diagonal_offset(pose: float) -> float:
	return DIAGONAL_TRAVEL * (1.0 - pose)


static func triangle_scale(pose: float) -> float:
	return lerpf(COMPRESSED_SCALE, 1.0, pose)


static func mirrored(point: Vector2) -> Vector2:
	return Vector2(CENTRE_X + CENTRE_X - point.x, point.y)


func design_extent() -> Vector2:
	return DESIGN_SIZE


func _draw() -> void:
	_draw_pair(BAR_FROM, BAR_TO, bar_offset(zoom))
	_draw_pair(DIAGONAL_FROM, DIAGONAL_TO, diagonal_offset(zoom))
	_draw_triangle(triangle_scale(zoom))


## Keeps an editor preview of the pose out of every layout that stores this widget.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "zoom":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


## Mirroring the shifted point lands the right-hand part on its own inward shift.
func _draw_pair(from: Vector2, to: Vector2, shift: float) -> void:
	var moved_from := from + Vector2(shift, 0.0)
	var moved_to := to + Vector2(shift, 0.0)
	draw_design_line(moved_from, moved_to, STROKE, HudPalette.CHROME)
	draw_design_line(mirrored(moved_from), mirrored(moved_to), STROKE, HudPalette.CHROME)


## The stroke shrinks with the shape, the way scaling a stroked path does.
func _draw_triangle(factor: float) -> void:
	var points := PackedVector2Array()
	for point in TRIANGLE:
		points.append(TRIANGLE_PIVOT + (point - TRIANGLE_PIVOT) * factor)
	draw_design_outline(points, STROKE * factor, HudPalette.CHROME)
