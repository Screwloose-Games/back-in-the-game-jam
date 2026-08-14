class_name HudMetrics
extends RefCounted

const DESIGN_SIZE := Vector2(1920.0, 1080.0)

const BASE_SIZE := Vector2(1280.0, 720.0)

const SCALE := 1280.0 / 1920.0

const DOT := 4.0

const FONT_SIZE_LABEL := 32
const FONT_SIZE_READOUT := 48


static func px(design: float) -> float:
	return design * SCALE


static func size_px(design: Vector2) -> Vector2:
	return design * SCALE


static func rect_px(design: Rect2) -> Rect2:
	return Rect2(design.position * SCALE, design.size * SCALE)


static func dots(design: float) -> float:
	if design <= 0.0:
		return 0.0
	return maxf(DOT, snappedf(design * SCALE, DOT))


static func snap(value: float) -> float:
	return snappedf(value, DOT)


static func snap_vec(value: Vector2) -> Vector2:
	return Vector2(snappedf(value.x, DOT), snappedf(value.y, DOT))


static func snap_rect(rect: Rect2) -> Rect2:
	var start := Vector2(floorf(rect.position.x / DOT) * DOT, floorf(rect.position.y / DOT) * DOT)
	var end := Vector2(ceilf(rect.end.x / DOT) * DOT, ceilf(rect.end.y / DOT) * DOT)
	return Rect2(start, end - start)


static func dash_count(circumference: float, dash: float, gap: float) -> int:
	var period := dash + gap
	if period <= 0.0:
		return 0
	return maxi(1, roundi(circumference / period))


static func font_size(base: int, factor: float) -> int:
	var raw := float(base) * factor / SCALE
	return maxi(16, int(snappedf(raw, 16.0)))


static func ellipse_circumference(radii: Vector2) -> float:
	var a := radii.x
	var b := radii.y
	var h := (a - b) * (a - b) / ((a + b) * (a + b)) if a + b > 0.0 else 0.0
	return PI * (a + b) * (1.0 + 3.0 * h / (10.0 + sqrt(4.0 - 3.0 * h)))
