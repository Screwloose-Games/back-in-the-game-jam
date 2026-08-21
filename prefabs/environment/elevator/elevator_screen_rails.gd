@tool
class_name ElevatorScreenRails
extends Control

## The quota terminal's non-verbal furniture: side ladders, a level gauge, corner
## brackets, a hazard strip and the warning glyph. One _draw() rather than sixty
## nodes, because this is procedural repetition and none of it is content.

const DESIGN := Vector2(512.0, 320.0)

const GAUGE_RECT := Rect2(11.0, 45.0, 12.0, 240.0)
const GAUGE_CELLS := 26
const LEFT_LADDER_X := 36.0
const RIGHT_LADDER_X := 471.0
const LADDER_TOP := 45.0
const LADDER_BOTTOM := 285.0
const LADDER_STEP := 6.0
const LADDER_SHORT := 9.0
const LADDER_LONG := 15.0
const BRACKET_INSET := 12.0
const BRACKET_ARM := 26.0
const HAZARD_Y := 286.0
const HAZARD_HEIGHT := 7.0
const HAZARD_ON := 3.0
const HAZARD_OFF := 5.0
const WARN_RECT := Rect2(487.0, 224.0, 18.0, 17.0)

@export var rail_color := Color(0.62, 0.95, 0.85, 0.85):
	set = _set_rail_color
@export var warn_color := Color(1.0, 0.22, 0.18):
	set = _set_warn_color
@export var gauge_low_color := Color(1.0, 0.22, 0.18)

var _alarming := true


func _draw() -> void:
	_draw_gauge()
	_draw_ladder(LEFT_LADDER_X, 1.0)
	_draw_ladder(RIGHT_LADDER_X, -1.0)
	_draw_brackets()
	_draw_hazard()
	_draw_warning()


## Recolours the alarm furniture. The DENIED breath itself lives in the shader, so
## this only decides whether the strip and glyph are lit at all.
func set_alarming(on: bool) -> void:
	if on == _alarming:
		return
	_alarming = on
	queue_redraw()


func _draw_gauge() -> void:
	var cell := GAUGE_RECT.size.y / float(GAUGE_CELLS)
	for i in GAUGE_CELLS:
		var top := GAUGE_RECT.position.y + float(i) * cell
		var lit := i < GAUGE_CELLS - 3
		var color := rail_color if lit else gauge_low_color
		if not lit and not _alarming:
			color = rail_color
		draw_rect(
			Rect2(GAUGE_RECT.position.x, top, GAUGE_RECT.size.x, cell - 1.0),
			Color(color, color.a * (0.35 if lit else 1.0))
		)


func _draw_ladder(x: float, direction: float) -> void:
	var index := 0
	var y := LADDER_TOP
	while y <= LADDER_BOTTOM:
		var length := LADDER_LONG if index % 5 == 0 else LADDER_SHORT
		var start := x if direction > 0.0 else x + LADDER_SHORT - length
		draw_rect(Rect2(start, y, length, 1.0), rail_color)
		y += LADDER_STEP
		index += 1


func _draw_brackets() -> void:
	var left := BRACKET_INSET + 48.0
	var right := DESIGN.x - BRACKET_INSET - 48.0
	var top := BRACKET_INSET + 12.0
	var bottom := DESIGN.y - BRACKET_INSET - 24.0
	for corner in 4:
		var x := left if corner % 2 == 0 else right
		var y := top if corner < 2 else bottom
		var dx := 1.0 if corner % 2 == 0 else -1.0
		var dy := 1.0 if corner < 2 else -1.0
		draw_rect(Rect2(minf(x, x + dx * BRACKET_ARM), y, BRACKET_ARM, 1.0), rail_color)
		draw_rect(Rect2(x, minf(y, y + dy * BRACKET_ARM), 1.0, BRACKET_ARM), rail_color)


func _draw_hazard() -> void:
	var color := warn_color if _alarming else rail_color
	var x := 55.0
	while x < DESIGN.x - 55.0:
		draw_rect(Rect2(x, HAZARD_Y, HAZARD_ON, HAZARD_HEIGHT), Color(color, 0.75))
		x += HAZARD_ON + HAZARD_OFF


func _draw_warning() -> void:
	var color := warn_color if _alarming else Color(rail_color, 0.35)
	var apex := Vector2(WARN_RECT.position.x + WARN_RECT.size.x * 0.5, WARN_RECT.position.y)
	var left := Vector2(WARN_RECT.position.x, WARN_RECT.end.y)
	var right := Vector2(WARN_RECT.end.x, WARN_RECT.end.y)
	draw_polyline(PackedVector2Array([apex, right, left, apex]), color, 1.5)
	draw_rect(Rect2(apex.x - 0.75, WARN_RECT.position.y + 5.0, 1.5, 6.0), color)
	draw_rect(Rect2(apex.x - 0.75, WARN_RECT.position.y + 13.0, 1.5, 1.5), color)


func _set_rail_color(value: Color) -> void:
	rail_color = value
	queue_redraw()


func _set_warn_color(value: Color) -> void:
	warn_color = value
	queue_redraw()
