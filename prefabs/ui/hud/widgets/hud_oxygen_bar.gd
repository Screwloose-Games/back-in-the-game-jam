@tool
class_name HudOxygenBar
extends HudWidget

## Oxygen as HUD 02's horizontal bar.

## Figma states OXYGEN_BORDER at this size.
const DESIGN := Vector2(711.0, 71.0)

## Where OXYGEN_LINES sits inside that box, as a center.
const LINES_CENTRE := Vector2(354.5, 36.0)

## How much oxygen is left, 0..1.
@export_range(0.0, 1.0, 0.01) var fraction := 1.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(next, fraction):
			return
		fraction = next
		queue_redraw()

@export_group("Art")

## Figma's OXYGEN_BORDER. Also the widget's design extent.
@export var border: Texture2D = HudArt.OXYGEN_BORDER:
	set(value):
		if value == border:
			return
		border = value
		update_configuration_warnings()
		queue_redraw()

## Figma's OXYGEN_LINES, drawn twice: once dim across the whole bar, once bright and
## clipped to [member fraction].
@export var lines: Texture2D = HudArt.OXYGEN_LINES:
	set(value):
		if value == lines:
			return
		lines = value
		update_configuration_warnings()
		queue_redraw()

## Centre of [member lines] in design coordinates.
@export var lines_centre: Vector2 = LINES_CENTRE:
	set(value):
		if value.is_equal_approx(lines_centre):
			return
		lines_centre = value
		update_configuration_warnings()
		queue_redraw()

## Alpha of the spent portion.
@export_range(0.0, 1.0, 0.01) var spent_alpha := 0.22:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(next, spent_alpha):
			return
		spent_alpha = next
		queue_redraw()


func design_extent() -> Vector2:
	return Vector2(border.get_size()) if border != null else DESIGN


func _draw() -> void:
	draw_design_texture(border, design_extent() * 0.5)
	draw_design_texture(lines, lines_centre, Color(1.0, 1.0, 1.0, spent_alpha))
	draw_design_texture_reveal(lines, lines_centre, fraction)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if border == null:
		warnings.append(
			"No border texture, so the bar has no frame and falls back to a %s design box." % DESIGN
		)
	if lines == null:
		warnings.append("No lines texture, so the bar draws a frame but can never draw a level.")
	elif not _lines_fit():
		warnings.append(
			(
				"lines_centre %s puts the lines outside the %s design box."
				% [lines_centre, design_extent()]
			)
		)
	return warnings


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "fraction":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


func bind(state: HudState) -> void:
	if not state.oxygen_changed.is_connected(show_fraction):
		state.oxygen_changed.connect(show_fraction)
	show_fraction(state.oxygen)


func show_fraction(value: float) -> void:
	fraction = value


func _lines_fit() -> bool:
	var extent := Vector2(lines.get_size())
	return Rect2(Vector2.ZERO, design_extent()).encloses(Rect2(lines_centre - extent * 0.5, extent))
