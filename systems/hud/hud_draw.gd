class_name HudDraw
extends RefCounted

## What the HUD still draws rather than blits: the border, and text.
##
## Everything else comes out of Figma as a PNG now - see hud_art.gd. Two things
## cannot:
##
## BORDER, because Figma states it at 1836x1024 and the repo's art gate blocks any
## PNG over 1024 in either dimension. That is the rule doing its job rather than
## getting in the way: the border is the one element that must meet all four screen
## edges, and stretch/aspect="expand" hands the game a canvas wider than 1280x720 on
## anything that is not 16:9, so a fixed bitmap would be wrong even if it fitted.
##
## TETHERED_METER, because its content changes every metre.
##
## The border is drawn on a HudMetrics.DOT lattice to match the Pixelate effect Figma
## has on it. Note that a UV-quantising shader cannot reproduce that: quantising UV
## only changes texture sampling, and draw_rect emits solid-colour primitives with no
## source texture. Pixelating already-rasterised vector geometry means reading it
## back, which on GL Compatibility means hint_screen_texture behind a BackBufferCopy -
## a full framebuffer copy per frame on the web target, which would also pixelate the
## 3D scene showing through the HUD. Drawing on the lattice is exact and free.

const FONT := preload("res://assets/art/ui/font/PixelPurl.ttf")

## How far apart consecutive arc samples are placed before snapping, as a fraction of
## a dot. Below half a dot the dedupe throws most samples away for nothing; above it
## the lattice starts showing gaps on tight corners.
const ARC_STEP_RATIO := 0.4


## A rounded rectangle outline in dots: four straight runs, four quarter arcs.
static func dot_frame(
	canvas: CanvasItem, rect: Rect2, thickness: float, radius: float, color: Color
) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	dot_line(canvas, Vector2(left + r, top), Vector2(right - r, top), thickness, color)
	dot_line(canvas, Vector2(left + r, bottom), Vector2(right - r, bottom), thickness, color)
	dot_line(canvas, Vector2(left, top + r), Vector2(left, bottom - r), thickness, color)
	dot_line(canvas, Vector2(right, top + r), Vector2(right, bottom - r), thickness, color)
	if r <= 0.0:
		return
	var arc := Vector2(r, r)
	dot_arc(canvas, Vector2(left + r, top + r), arc, PI, PI * 1.5, thickness, color)
	dot_arc(canvas, Vector2(right - r, top + r), arc, PI * 1.5, TAU, thickness, color)
	dot_arc(canvas, Vector2(right - r, bottom - r), arc, 0.0, PI * 0.5, thickness, color)
	dot_arc(canvas, Vector2(left + r, bottom - r), arc, PI * 0.5, PI, thickness, color)


## A straight run of dots. Thickness is rounded to whole dots, minimum one.
static func dot_line(
	canvas: CanvasItem, from: Vector2, to: Vector2, thickness: float, color: Color
) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.0:
		return
	var normal := Vector2(-delta.y, delta.x).normalized()
	var layers := maxi(1, roundi(thickness / HudMetrics.DOT))
	var steps := maxi(1, ceili(length / (HudMetrics.DOT * ARC_STEP_RATIO)))
	var seen := {}
	for layer in layers:
		var offset := normal * (float(layer) - float(layers - 1) * 0.5) * HudMetrics.DOT
		for i in steps + 1:
			var point := from.lerp(to, float(i) / float(steps)) + offset
			_stamp(canvas, point, color, seen)


## An arc of dots, for the border's corners.
static func dot_arc(
	canvas: CanvasItem,
	centre: Vector2,
	radii: Vector2,
	from_angle: float,
	to_angle: float,
	thickness: float,
	color: Color
) -> void:
	var span := to_angle - from_angle
	var reach := maxf(radii.x, radii.y)
	if reach <= 0.0 or is_zero_approx(span):
		return
	var steps := maxi(1, ceili(absf(span) * reach / (HudMetrics.DOT * ARC_STEP_RATIO)))
	var layers := maxi(1, roundi(thickness / HudMetrics.DOT))
	var seen := {}
	for layer in layers:
		var inset := (float(layer) - float(layers - 1) * 0.5) * HudMetrics.DOT
		var ring := Vector2(maxf(radii.x + inset, 0.0), maxf(radii.y + inset, 0.0))
		for i in steps + 1:
			var angle := from_angle + span * float(i) / float(steps)
			var point := centre + Vector2(cos(angle) * ring.x, sin(angle) * ring.y)
			_stamp(canvas, point, color, seen)


## Text on the dot lattice. align is a HORIZONTAL_ALIGNMENT_* constant; the string is
## drawn inside a box the full width of rect so centring works without measuring.
static func text(
	canvas: CanvasItem, rect: Rect2, value: String, size: int, color: Color, align: int
) -> void:
	var origin := HudMetrics.snap_vec(Vector2(rect.position.x, rect.position.y + float(size) * 0.8))
	canvas.draw_string(FONT, origin, value, align, rect.size.x, size, color)


## One dot, deduped against the ones already placed this call. Snapping alone is not
## enough: consecutive arc samples routinely land on the same lattice cell, and
## overdrawing a translucent chrome colour onto itself makes those cells darker than
## their neighbours - a moire that follows the curvature.
static func _stamp(canvas: CanvasItem, point: Vector2, color: Color, seen: Dictionary) -> void:
	var cell := Vector2i(floori(point.x / HudMetrics.DOT), floori(point.y / HudMetrics.DOT))
	if seen.has(cell):
		return
	seen[cell] = true
	canvas.draw_rect(
		Rect2(
			float(cell.x) * HudMetrics.DOT,
			float(cell.y) * HudMetrics.DOT,
			HudMetrics.DOT,
			HudMetrics.DOT
		),
		color
	)
