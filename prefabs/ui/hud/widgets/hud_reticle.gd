@tool
class_name HudReticle
extends HudWidget

## Figma's RETICLE, in whichever of the mockups' shapes the variant uses.
const DESIGN_WIDTH := 505.0

@export var texture: Texture2D = HudArt.RETICLE_04


func design_extent() -> Vector2:
	if texture == null:
		return Vector2(DESIGN_WIDTH, DESIGN_WIDTH)
	return Vector2(texture.get_size())


func _draw() -> void:
	draw_design_texture(texture, design_extent() * 0.5)
