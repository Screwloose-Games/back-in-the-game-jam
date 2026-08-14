@tool
class_name HudPower
extends HudWidget

## The suit's charge: Figma's POWER_BG behind Figma's POWER_LINES.
@export var background: Texture2D = HudArt.POWER_BG_04
@export var lines: Texture2D = HudArt.POWER_LINES
@export var lines_centre := Vector2(135.0, 129.0)

@export var spent_alpha := 0.22

var _fraction := 1.0


func design_extent() -> Vector2:
	return Vector2(background.get_size()) if background != null else Vector2(258.0, 257.0)


func _draw() -> void:
	var centre := design_extent() * 0.5
	draw_design_texture(background, centre)
	draw_design_texture(lines, lines_centre, Color(1.0, 1.0, 1.0, spent_alpha))
	draw_design_texture_reveal(lines, lines_centre, _fraction)


func bind(state: HudState) -> void:
	state.power_changed.connect(show_fraction)


func show_fraction(fraction: float) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	queue_redraw()
