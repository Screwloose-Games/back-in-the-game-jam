class_name HudStatus
extends HudWidget

## Figma's STATUS: the suit occupant's face.
##
## Three drawings, one per HudState.Status, taken straight from the HUD_UI Status
## Green, Yellow and Red frames the designer drew. That is why Status has exactly
## three values - the enum is sized to the art rather than the other way round.
##
## The frames are 315x315 while STATUS inside each HUD is stated at 274x274; the
## difference is the glow Figma includes in the export bounds, which is why this
## draws centred rather than to the node's rect.

## Figma: STATUS, 274x274 in every variant that has one.
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
