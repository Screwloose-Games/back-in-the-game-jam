@tool
class_name HudMineralScore
extends HudWidget

## The player's running mineral score, in the HUD's own pixel font.

const DESIGN := Vector2(255.0, 45.0)

@export var score_format := "SCORE %d"

@export var alignment := HORIZONTAL_ALIGNMENT_LEFT

var _score := 0


func design_extent() -> Vector2:
	return DESIGN


func scale_factor() -> float:
	return size.y / DESIGN.y


func _draw() -> void:
	HudDraw.text(
		self,
		Rect2(Vector2.ZERO, size),
		score_format % _score,
		HudMetrics.font_size(HudMetrics.FONT_SIZE_READOUT, scale_factor()),
		HudPalette.CHROME,
		alignment
	)


func bind(state: HudState) -> void:
	state.mineral_score_changed.connect(show_score)


func show_score(score: int) -> void:
	_score = score
	queue_redraw()
