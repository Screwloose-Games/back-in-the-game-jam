@tool
class_name HudOxygenRing
extends HudWidget

## Oxygen as HUD 03 and 04's ring: Figma's OXYGEN, wrapped round the power meter.

const DESIGN := Vector2(302.0, 301.0)
const STROKE := 22.0
const DASHES := 8

const FIRST_DASH := 6

const ARC_STEPS := 8

const ALARM_FRACTION := 0.2
const ALARM_RATE := 2.4
const ALARM_DEPTH := 0.45

@export var spent_alpha := 0.22

var _fraction := 1.0
var _elapsed := 0.0


func design_extent() -> Vector2:
	return DESIGN


func _process(delta: float) -> void:
	if _fraction >= ALARM_FRACTION:
		return
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	var centre := DESIGN * 0.5
	draw_design_texture(HudArt.OXYGEN_RING, centre, Color(1.0, 1.0, 1.0, spent_alpha))

	var lit := _fraction * float(DASHES)
	var alarm := _alarm_alpha()
	var period := TAU / float(DASHES)
	var outer := DESIGN * 0.5
	var inner := outer - Vector2.ONE * STROKE
	for i in DASHES:
		var alpha := clampf(lit - float(i), 0.0, 1.0) * alarm
		if alpha <= 0.0:
			continue
		var from_angle := float((i + FIRST_DASH) % DASHES) * period
		_draw_sector(centre, outer, inner, from_angle, from_angle + period, alpha)


func bind(state: HudState) -> void:
	state.oxygen_changed.connect(show_fraction)


func show_fraction(fraction: float) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	if _fraction >= ALARM_FRACTION:
		_elapsed = 0.0
	queue_redraw()


func _draw_sector(
	centre: Vector2,
	outer: Vector2,
	inner: Vector2,
	from_angle: float,
	to_angle: float,
	alpha: float
) -> void:
	var source := Vector2(HudArt.OXYGEN_RING.get_size())
	var origin := centre - source * 0.5
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()

	for i in ARC_STEPS + 1:
		var angle := lerpf(from_angle, to_angle, float(i) / float(ARC_STEPS))
		_append_point(points, uvs, centre + Vector2(cos(angle), sin(angle)) * outer, origin, source)
	for i in ARC_STEPS + 1:
		var angle := lerpf(to_angle, from_angle, float(i) / float(ARC_STEPS))
		_append_point(points, uvs, centre + Vector2(cos(angle), sin(angle)) * inner, origin, source)

	draw_polygon(points, PackedColorArray([Color(1.0, 1.0, 1.0, alpha)]), uvs, HudArt.OXYGEN_RING)


func _append_point(
	points: PackedVector2Array,
	uvs: PackedVector2Array,
	design_point: Vector2,
	origin: Vector2,
	source: Vector2
) -> void:
	points.append(scaled_vec(design_point))
	uvs.append((design_point - origin) / source)


func _alarm_alpha() -> float:
	if _fraction >= ALARM_FRACTION:
		return 1.0
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * ALARM_RATE)
	return lerpf(ALARM_DEPTH, 1.0, pulse)
