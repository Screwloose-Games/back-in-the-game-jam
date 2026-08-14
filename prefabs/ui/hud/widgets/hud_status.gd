@tool
class_name HudStatus
extends HudWidget

## Figma's STATUS: the suit occupant's face.
const DESIGN := Vector2(274.0, 274.0)

var _status := HudState.Status.NOMINAL


func design_extent() -> Vector2:
	return DESIGN


func _draw() -> void:
	draw_design_texture(HudArt.status_texture(_status), DESIGN * 0.5)


func bind(state: HudState) -> void:
	state.status_changed.connect(show_status)


func show_status(status: int) -> void:
	_status = status as HudState.Status
	queue_redraw()
