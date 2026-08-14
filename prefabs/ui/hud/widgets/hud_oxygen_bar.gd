@tool
class_name HudOxygenBar
extends HudWidget

## Oxygen as HUD 02's horizontal bar: Figma's OXYGEN_BORDER around OXYGEN_LINES.

const DESIGN := Vector2(711.0, 71.0)
const LINES_CENTRE := Vector2(354.5, 36.0)

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
	draw_design_texture(HudArt.OXYGEN_BORDER, DESIGN * 0.5)
	draw_design_texture(HudArt.OXYGEN_LINES, LINES_CENTRE, Color(1.0, 1.0, 1.0, spent_alpha))
	draw_design_texture_reveal(
		HudArt.OXYGEN_LINES, LINES_CENTRE, _fraction, Color(1.0, 1.0, 1.0, _alarm_alpha())
	)


func bind(state: HudState) -> void:
	state.oxygen_changed.connect(show_fraction)


func show_fraction(fraction: float) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	if _fraction >= ALARM_FRACTION:
		_elapsed = 0.0
	queue_redraw()


func _alarm_alpha() -> float:
	if _fraction >= ALARM_FRACTION:
		return 1.0
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * ALARM_RATE)
	return lerpf(ALARM_DEPTH, 1.0, pulse)
