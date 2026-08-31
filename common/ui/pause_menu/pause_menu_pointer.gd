@tool
class_name PauseMenuPointer
extends MainMenuPointer

## MainMenuPointer mirrored: the arrow sits left of the focused item, head pointing
## right at it.

const MIRROR_HEAD: PackedVector2Array = [
	Vector2(124.7, 16.4), Vector2(101.6, 0.0), Vector2(101.6, 32.3)
]

const MIRROR_TAIL_FROM := Vector2(0.0, 16.2)
const MIRROR_TAIL_TO := Vector2(97.9, 16.2)


func track(menu: Control) -> void:
	menu.get_viewport().gui_focus_changed.connect(_on_focus_changed.bind(menu))


func _draw() -> void:
	draw_design_outline(MIRROR_HEAD, STROKE, HudPalette.CHROME)
	draw_design_line(MIRROR_TAIL_FROM, MIRROR_TAIL_TO, STROKE, HudPalette.CHROME)


func _on_focus_changed(focused: Control, menu: Control) -> void:
	if menu.is_ancestor_of(focused):
		_settle_beside(focused)


## Deferred: focus can arrive before the menu has laid out.
func _settle_beside(item: Control) -> void:
	_place_beside.call_deferred(item)


func _place_beside(item: Control) -> void:
	var host := get_parent() as Control
	if host == null:
		return
	var rect := item.get_global_rect()
	var origin: Vector2 = host.get_global_transform().affine_inverse() * rect.position
	position = Vector2(
		origin.x - size.x - HudMetrics.px(GAP), origin.y + (rect.size.y - size.y) * 0.5
	)
	visible = true
