class_name HudPower
extends HudWidget

## The suit's charge: Figma's POWER_BG behind Figma's POWER_LINES.
##
## POWER_BG is the static half - the housing ring, the battery outline and the POWER
## lettering, all baked into one export. POWER_LINES is the strip of gold cells, and
## it is the only part that moves: it is revealed left to right by the charge, over a
## dimmed copy of itself so the cells you have spent still read as cells rather than
## as empty space.
##
## The three variants differ only in which pair of textures they carry and how far
## the strip sits inside the housing, so all of that is exported rather than coded.

## Where the cell strip's centre sits inside this widget, in design pixels. Figma:
## HUD 02 POWER_BG (274x273 at 40,27) with POWER_LINES (170x50 at 98,139); HUD 03
## (215x122 at 130,190) with (146x50 at 161,199); HUD 04 (258x257 at 111,95) with
## (170x50 at 161,199).
@export var background: Texture2D = HudArt.POWER_BG_04
@export var lines: Texture2D = HudArt.POWER_LINES
@export var lines_centre := Vector2(135.0, 129.0)

## How visible a spent cell stays.
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


## Sets how full the battery reads, 0 to 1. Connected straight to HudState's
## power_changed, so it redraws when the charge moves rather than on a clock.
func show_fraction(fraction: float) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	queue_redraw()
