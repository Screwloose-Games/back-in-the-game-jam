class_name HudMetrics
extends RefCounted

## The one place the Figma numbers become Godot numbers.
##
## The mockups are drawn at 1920x1080 and the game runs at 1280x720, so every
## measurement in this HUD arrives two thirds smaller than the design file says.
## Converting at the point of use would put that ratio in thirty places and turn the
## next design revision into a search-and-replace; converting here lets every widget
## quote Figma verbatim and stay readable next to the mockup.

## The Figma frame. HUDInterface_01 through _04 are all exactly this.
const DESIGN_SIZE := Vector2(1920.0, 1080.0)

## project.godot's viewport. NOT the window, and not something to lay out against:
## with stretch/aspect="expand" the canvas is at least this and grows on non-16:9
## displays, which is why nothing here returns a screen position and every widget is
## anchored instead.
const BASE_SIZE := Vector2(1280.0, 720.0)

const SCALE := 1280.0 / 1920.0

## One HUD dot, in canvas units - six design pixels, which is where Figma's Pixelate
## effect lands in the mockups. The chrome that carries that effect is drawn on this
## lattice rather than pixelated afterwards; see hud_draw.gd for why.
const DOT := 4.0

## PixelPurl has a 1024 unit em and every glyph bbox and advance in the file is a
## multiple of 64, so the font is only crisp at 1024/64 = 16 pixels and its
## multiples. The mockup's 40px and 60px convert to 26.7 and 40 canvas units, and
## neither is a multiple of 16 - rendered there the stems land on half pixels, which
## is the one thing that makes a pixel font look broken. These are the nearest sizes
## that hold the mockup's 2:3 ratio between the two, at the cost of running 20%
## larger than a literal conversion.
const FONT_SIZE_LABEL := 32
const FONT_SIZE_READOUT := 48


## Design pixels to canvas units. For positions and for anything that then gets
## snapped; sizes inside _draw() want dots() instead.
static func px(design: float) -> float:
	return design * SCALE


static func size_px(design: Vector2) -> Vector2:
	return design * SCALE


static func rect_px(design: Rect2) -> Rect2:
	return Rect2(design.position * SCALE, design.size * SCALE)


## Design pixels to whole dots of canvas units. Never returns zero for a positive
## input, so a hairline in the design file stays visible rather than vanishing.
static func dots(design: float) -> float:
	if design <= 0.0:
		return 0.0
	return maxf(DOT, snappedf(design * SCALE, DOT))


static func snap(value: float) -> float:
	return snappedf(value, DOT)


static func snap_vec(value: Vector2) -> Vector2:
	return Vector2(snappedf(value.x, DOT), snappedf(value.y, DOT))


## Grows the rect outwards to the lattice rather than rounding both edges, so a
## snapped rect never ends up thinner than the one asked for.
static func snap_rect(rect: Rect2) -> Rect2:
	var start := Vector2(floorf(rect.position.x / DOT) * DOT, floorf(rect.position.y / DOT) * DOT)
	var end := Vector2(ceilf(rect.end.x / DOT) * DOT, ceilf(rect.end.y / DOT) * DOT)
	return Rect2(start, end - start)


## How many dashes a dashed stroke of this pattern makes once round a closed curve.
## Figma states the O2 ring as a 60/60 dash on a 302px circle and leaves the count
## implied; pi * 302 / 120 is 7.9, which is the eight arc segments HUD 03 draws
## discretely. Rounded rather than floored so the pattern closes up instead of
## leaving a long gap where it meets itself.
static func dash_count(circumference: float, dash: float, gap: float) -> int:
	var period := dash + gap
	if period <= 0.0:
		return 0
	return maxi(1, roundi(circumference / period))


## The crisp font size for a widget drawn at some factor other than the nominal one.
## PixelPurl only has whole pixels at multiples of sixteen, so this snaps rather than
## scaling smoothly - a HUD at an odd size renders slightly larger or smaller text
## instead of blurry text.
static func font_size(base: int, factor: float) -> int:
	var raw := float(base) * factor / SCALE
	return maxi(16, int(snappedf(raw, 16.0)))


## Ramanujan's approximation. The radar is a squashed circle and its dashed outer
## ring needs a perimeter to divide up; the exact figure is an elliptic integral and
## this is within a rounding error of it at these eccentricities.
static func ellipse_circumference(radii: Vector2) -> float:
	var a := radii.x
	var b := radii.y
	var h := (a - b) * (a - b) / ((a + b) * (a + b)) if a + b > 0.0 else 0.0
	return PI * (a + b) * (1.0 + 3.0 * h / (10.0 + sqrt(4.0 - 3.0 * h)))
