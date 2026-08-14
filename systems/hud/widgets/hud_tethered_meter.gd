class_name HudTetheredMeter
extends HudWidget

## Figma's TETHERED_METER: the tether line, in red.
##
## The one component with no exported art, because it is the one whose content
## changes every metre. Figma's three variants read TETHERED 33m, TETHERED 33M and
## T - 33m, so the wording is an export rather than three scripts - which also makes
## it something a designer can try during the A/B instead of a code change.
##
## Redraws only when the whole-metre reading or the attachment changes; HudState does
## that rounding, for the same reason PowerHud rebuilds its strings on a clock rather
## than every frame.

## Figma: TETHERED_METER, 255x45, PixelPurl 60px, #FF0000.
const DESIGN := Vector2(255.0, 45.0)

## %d takes whole metres.
@export var attached_format := "TETHERED %dm"

## No mockup shows the detached state, so this is invented - but a readout that
## simply vanishes would leave you wondering whether the HUD had broken.
@export var detached_text := "UNTETHERED"

@export var alignment := HORIZONTAL_ALIGNMENT_LEFT

var _attached := false
var _metres := 0.0


func design_extent() -> Vector2:
	return DESIGN


## Scaled off the height rather than the width, unlike every other widget. The three
## variants say three different lengths of string in the same size of type, so the
## box has to be free to widen without the lettering growing with it.
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
