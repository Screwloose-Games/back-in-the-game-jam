class_name HudReticle
extends HudWidget

## Figma's RETICLE, in whichever of the mockups' shapes the variant uses.
##
## Pure chrome - it binds to nothing. It stays a widget rather than a bare
## TextureRect so that it scales off design pixels like everything else, and so the
## three shapes are one exported field rather than three scenes.

## Figma: RETICLE is 505 wide in all three variants, and 131, 86 and 66 tall in
## HUD 02, 03 and 04. The height comes off the texture, so only the width is fixed.
const DESIGN_WIDTH := 505.0

@export var texture: Texture2D = HudArt.RETICLE_04


func design_extent() -> Vector2:
	if texture == null:
		return Vector2(DESIGN_WIDTH, DESIGN_WIDTH)
	return Vector2(texture.get_size())


func _draw() -> void:
	draw_design_texture(texture, design_extent() * 0.5)
