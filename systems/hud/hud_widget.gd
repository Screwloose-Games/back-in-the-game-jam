class_name HudWidget
extends Control

## Base for every HUD readout.
##
## Carries the one thing all of them share: the conversion from the Figma frame's
## coordinates to whatever size the node actually got. Widgets quote design pixels
## throughout and run everything through scaled() at draw time, so the numbers in the
## source stay the numbers in the Properties panel and the HUD still comes out right
## at any size.
##
## Nothing here runs _process. Each widget redraws when the value it reports changes
## and not otherwise, which is the rule power_bar.gd sets out.


func _ready() -> void:
	# A HUD that eats clicks is a bug found three prototypes later. Same rule the
	# power prototype applies to its crosshair and bar.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Connect to whatever this widget reports on. The base binds nothing; a widget that
## is pure chrome - the border, the reticle - simply does not override this.
func bind(_state: HudState) -> void:
	pass


## The widget's footprint in the 1920x1080 mockup. Overridden by every widget from
## its own DESIGN const or its texture rather than exported, so that resizing a node
## in the editor is the only thing a variant ever has to do - there is no second
## number to keep in step with the first.
func design_extent() -> Vector2:
	return Vector2(100.0, 100.0)


func scale_factor() -> float:
	var extent := design_extent()
	if extent.x <= 0.0:
		return 1.0
	return size.x / extent.x


func scaled(value: float) -> float:
	return value * scale_factor()


func scaled_vec(value: Vector2) -> Vector2:
	return value * scale_factor()


func scaled_rect(rect: Rect2) -> Rect2:
	var factor := scale_factor()
	return Rect2(rect.position * factor, rect.size * factor)


## Draws a Figma export at its natural size, centred on a point in design space.
##
## Centred rather than corner-anchored because Figma grows an export's bounding box
## to cover strokes and effects, and does it symmetrically - a node stated at
## 333.75x270.85 lands as a 339x276 PNG. Anchoring by corner would offset every asset
## by half its bleed and leave the HUD subtly wrong in a way that reads as sloppy
## tracing rather than as a bug.
func draw_design_texture(
	texture: Texture2D, design_centre: Vector2, modulate := Color.WHITE
) -> void:
	if texture == null:
		return
	var extent := Vector2(texture.get_size()) * scale_factor()
	var centre := scaled_vec(design_centre)
	draw_texture_rect(texture, Rect2(centre - extent * 0.5, extent), false, modulate)


## The same, revealed left to right - the fraction of the texture's width that is
## lit. Used by both power and the oxygen bar, whose cells fill in that direction
## because that is the way the mockup's specular sweep runs.
func draw_design_texture_reveal(
	texture: Texture2D, design_centre: Vector2, fraction: float, modulate := Color.WHITE
) -> void:
	if texture == null or fraction <= 0.0:
		return
	var source := Vector2(texture.get_size())
	var extent := source * scale_factor()
	var centre := scaled_vec(design_centre)
	var origin := centre - extent * 0.5
	var shown := clampf(fraction, 0.0, 1.0)
	draw_texture_rect_region(
		texture,
		Rect2(origin, Vector2(extent.x * shown, extent.y)),
		Rect2(Vector2.ZERO, Vector2(source.x * shown, source.y)),
		modulate
	)
