@tool
class_name HudTetheredMeter
extends HudWidget

## Figma's TETHERED_METER: the tether line, in red.

const DESIGN := Vector2(255.0, 45.0)

@export var attached_format := "TETHERED %dm"

@export var detached_text := "UNTETHERED"

@export var alignment := HORIZONTAL_ALIGNMENT_LEFT

var _attached := false
var _metres := 0.0


func design_extent() -> Vector2:
	return DESIGN


func scale_factor() -> float:
	return size.y / DESIGN.y


func _draw() -> void:
	var value := attached_format % roundi(_metres) if _attached else detached_text
	var color := HudPalette.ALERT if _attached else HudPalette.CHROME_DIM
	HudDraw.text(
		self,
		Rect2(Vector2.ZERO, size),
		value,
		HudMetrics.font_size(HudMetrics.FONT_SIZE_READOUT, scale_factor()),
		color,
		alignment
	)


func bind(state: HudState) -> void:
	state.tether_changed.connect(show_tether)


func show_tether(attached: bool, metres: float) -> void:
	_attached = attached
	_metres = metres
	queue_redraw()
