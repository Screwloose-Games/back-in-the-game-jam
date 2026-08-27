@tool
class_name HudDamageOverlay
extends HudWidget

## Figma's Damage_Overlay: red bleeding in from all four corners on a hit, flaring
## together and fading out. Every corner is the same wedge, mirrored into place.

const DESIGN_SIZE := Vector2(1917.0, 1077.0)

## How far one wedge reaches along each screen edge. The mockup draws a curve that
## runs the whole way to the far corner, but the gradient filling it is spent well
## before then - nowhere on that curve does it exceed alpha 0.002 - so the triangle
## these two reaches cut off is the whole of what was ever visible.
const REACH_ACROSS := 0.469329
const REACH_DOWN := 0.386145

## The far end of the fill, and how far along it the corner already sits. The
## gradient starts off-canvas, so no pixel ever reaches full red: the corner is the
## brightest there is and it opens at 0.634.
const SPENT := Color(0.6, 0.0, 0.0, 0.0)
const CORNER_ALONG := 0.365802

## Where the flare peaks within a flash, and the curve it climbs. It drops away
## linearly from there, so a flash is not symmetric - it snaps on and eases off.
const PEAK_AT := 0.390438
const RISE_X1 := 0.814
const RISE_X2 := 0.37

## Stopwatch length of one flash: first red appearing to last red gone.
@export_range(0.05, 3.0, 0.001, "or_greater", "suffix:s") var flash_duration := 0.502:
	set(value):
		flash_duration = maxf(value, 0.01)
		queue_redraw()

@export_tool_button("Flash") var flash_action := flash

var _elapsed := 0.0
var _flashing := false


static func corner_tint() -> Color:
	return HudPalette.ALERT.lerp(SPENT, CORNER_ALONG)


## Up the mockup's curve to the peak, then straight back down.
static func flare_alpha(phase: float) -> float:
	if phase <= 0.0 or phase >= 1.0:
		return 0.0
	if phase < PEAK_AT:
		return HudEase.cubic(phase / PEAK_AT, RISE_X1, RISE_X2)
	return 1.0 - (phase - PEAK_AT) / (1.0 - PEAK_AT)


func _ready() -> void:
	super()
	set_process(false)


## The seam this widget was built for and waited on: HudState.damaged is a moment,
## not a level, so it drives the flash directly rather than through `status`.
func bind(state: HudState) -> void:
	state.damaged.connect(flash.unbind(1))


## Runs one flash from the start, whatever the last one was doing.
func flash() -> void:
	_elapsed = 0.0
	_flashing = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= flash_duration:
		_flashing = false
		set_process(false)
	queue_redraw()


func design_extent() -> Vector2:
	return DESIGN_SIZE


func _draw() -> void:
	if not _flashing:
		return
	var alpha := flare_alpha(_elapsed / flash_duration)
	if alpha <= 0.0:
		return
	for corner in 4:
		_draw_wedge(corner, alpha)


## Interpolating three vertices is exact rather than close, because a linear
## gradient is affine and the two outer ones sit where it has run out.
func _draw_wedge(corner: int, alpha: float) -> void:
	var horizontal := corner % 2 == 0
	var vertical := corner < 2
	var origin := Vector2(0.0 if horizontal else size.x, 0.0 if vertical else size.y)
	var across := size.x * REACH_ACROSS * (1.0 if horizontal else -1.0)
	var down := size.y * REACH_DOWN * (1.0 if vertical else -1.0)
	var points: PackedVector2Array = [
		origin, origin + Vector2(across, 0.0), origin + Vector2(0.0, down)
	]
	var tint := corner_tint()
	var colours: PackedColorArray = [Color(tint, tint.a * alpha), SPENT, SPENT]
	draw_polygon(points, colours)
