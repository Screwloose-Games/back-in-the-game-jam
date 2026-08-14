class_name HudMinimap
extends HudWidget

## Figma's MINIMAP: the proximity dish, with contacts on it.
##
## Assembled from the layers Figma names rather than exported whole, because
## MINIMAP contains ENEMY_DOT01 through 05 sitting at the positions the mockup
## happened to draw them, and those have to move. So RADAR_BACKGROUND, the four
## RADAR_LINES rings and RADAR_REFLECTION come across as art, and the dots are
## stamped from ENEMY_DOT at wherever HudState says the contacts are.
##
## Contacts arrive in unit-disc coordinates already rotated into the dish's frame.
## Deciding what counts as a contact, and which way is up, belongs to whatever fills
## HudState; the minimap's job is to put dots on an ellipse.

var _contacts := PackedVector2Array()
var _objective_shown := false
var _objective_at := Vector2.ZERO


func design_extent() -> Vector2:
	return HudArt.MINIMAP_SIZE


func _draw() -> void:
	draw_design_texture(HudArt.MINIMAP_BACKGROUND, HudArt.MINIMAP_BACKGROUND_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES04, HudArt.MINIMAP_LINES04_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES03, HudArt.MINIMAP_LINES03_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES02, HudArt.MINIMAP_LINES02_CENTRE)
	draw_design_texture(HudArt.MINIMAP_LINES01, HudArt.MINIMAP_LINES01_CENTRE)
	draw_design_texture(HudArt.MINIMAP_REFLECTION, HudArt.MINIMAP_REFLECTION_CENTRE)

	for offset in _contacts:
		draw_design_texture(HudArt.ENEMY_DOT, _place(offset))
	if _objective_shown:
		_draw_objective()


func bind(state: HudState) -> void:
	state.contacts_changed.connect(show_contacts)
	state.objective_changed.connect(show_objective)


func show_contacts(contacts: PackedVector2Array) -> void:
	_contacts = contacts
	queue_redraw()


func show_objective(shown: bool, at: Vector2) -> void:
	_objective_shown = shown
	_objective_at = at
	queue_redraw()


## Drawn rather than blitted, and deliberately not RADAR_REFLECTION - that is the
## dish's own static highlight, already drawn above, and reusing it here put two
## identical green marks on the minimap, one of which never moved. Nor is it a tinted
## ENEMY_DOT: modulate multiplies, so a green tint over a red dot comes out near
## black. A square of the same size in the objective colour is the honest version.
func _draw_objective() -> void:
	var extent := Vector2(HudArt.ENEMY_DOT.get_size()) * scale_factor()
	var centre := scaled_vec(_place(_objective_at))
	draw_rect(Rect2(centre - extent * 0.5, extent), HudPalette.OBJECTIVE)


## Unit-disc coordinates onto the rings' ellipse. Clamped to the rim rather than
## dropped, so something closing in from off-dish still reads as pinned to the edge
## instead of silently not being there.
func _place(offset: Vector2) -> Vector2:
	var clamped := offset if offset.length() <= 1.0 else offset.normalized()
	return HudArt.MINIMAP_RINGS_CENTRE + clamped * HudArt.MINIMAP_RINGS_EXTENT
