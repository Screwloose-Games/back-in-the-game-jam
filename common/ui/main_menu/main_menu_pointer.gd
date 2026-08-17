@tool
class_name MainMenuPointer
extends HudWidget

const DESIGN := Vector2(124.7, 32.3)
const STROKE := 5.0

## Hollow head, so the backdrop reads through it the way the mockup's does.
const HEAD: PackedVector2Array = [Vector2(0.0, 16.4), Vector2(23.1, 0.0), Vector2(23.1, 32.3)]

const TAIL_FROM := Vector2(26.8, 16.2)
const TAIL_TO := Vector2(124.7, 16.2)

## Clear of the longest label in the mockup, and measured from each label's own end so
## a shorter item does not leave the head stranded mid-screen.
const GAP := 51.0


func design_extent() -> Vector2:
	return DESIGN


## Keyboard focus and mouse hover therefore share one cursor.
func follow(items: Array[Button]) -> void:
	for item in items:
		item.focus_entered.connect(_settle_beside.bind(item))
		item.mouse_entered.connect(item.grab_focus)
	if not items.is_empty():
		items[0].grab_focus()


func _draw() -> void:
	draw_design_outline(HEAD, STROKE, HudPalette.CHROME)
	draw_design_line(TAIL_FROM, TAIL_TO, STROKE, HudPalette.CHROME)


func _settle_beside(item: Button) -> void:
	var host := get_parent() as Control
	if host == null:
		return
	var rect := item.get_global_rect()
	var origin: Vector2 = host.get_global_transform().affine_inverse() * rect.position
	position = Vector2(
		origin.x + rect.size.x + HudMetrics.px(GAP), origin.y + (rect.size.y - size.y) * 0.5
	)
	visible = true
